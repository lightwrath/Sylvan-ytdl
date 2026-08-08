#!/usr/bin/env python3
"""Download recent videos from a configured list of YouTube channels."""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import yt_dlp
from yt_dlp.utils import DateRange


LOGGER = logging.getLogger("youtube_downloader")


def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        config = json.load(file)

    if not isinstance(config, dict):
        raise ValueError("The config file must contain a JSON object")
    if not config.get("channels"):
        raise ValueError("The config file must contain at least one channel")

    for channel in config["channels"]:
        if not isinstance(channel, dict) or not channel.get("name") or not channel.get("url"):
            raise ValueError('Each channel must have a "name" and a "url"')

    return config


def safe_folder_name(name: str) -> str:
    """Prevent a channel name from creating paths outside the download folder."""
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    return name or "unnamed-channel"


def download_channel(
    channel: dict[str, str],
    output_root: Path,
    cutoff: date,
    cookies_file: Path | None = None,
    max_videos_to_check: int = 100,
) -> int:
    channel_dir = output_root / safe_folder_name(channel["name"])
    channel_dir.mkdir(parents=True, exist_ok=True)

    # The archive is the reliable duplicate check (video IDs are used, not titles).
    # nooverwrites also protects files that existed before the archive was created.
    options = {
        "format": "bestvideo*+bestaudio/best",
        "outtmpl": str(channel_dir / "%(upload_date)s - %(title)s [%(id)s].%(ext)s"),
        "download_archive": str(channel_dir / ".yt-dlp-download-archive"),
        # YoutubeDL's Python API expects a DateRange. The CLI's dateafter
        # option is not sufficient when passed directly as an API parameter.
        "daterange": DateRange(
            cutoff.strftime("%Y%m%d"),
            date.today().strftime("%Y%m%d"),
        ),
        # Avoid requesting metadata for hundreds of historical videos. The
        # channel feeds are newest-first; 0 means inspect the full feed.
        "noplaylist": False,
        "sleep_interval_requests": 0.75,
        "nooverwrites": True,
        "continuedl": True,
        # Large YouTube streams can occasionally hit transient read, DNS, or
        # TLS failures. Retry them without aborting the whole channel.
        "socket_timeout": 60,
        "retries": 10,
        "fragment_retries": 10,
        "extractor_retries": 5,
        "file_access_retries": 5,
        "ignoreerrors": True,
        "merge_output_format": "mp4",
    }
    if cookies_file is not None:
        options["cookiefile"] = str(cookies_file)
    if max_videos_to_check:
        options["playlistend"] = max_videos_to_check

    LOGGER.info("Checking %s (since %s)", channel["name"], cutoff.isoformat())
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            return ydl.download([channel["url"]])
    except Exception:
        LOGGER.exception("Could not process channel %s", channel["name"])
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-c", "--config", type=Path, default=Path("channels.json"))
    parser.add_argument(
        "--days",
        type=int,
        help="Override the number of previous days to check (default: config or 7)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    try:
        config = load_config(args.config)
        days = args.days if args.days is not None else int(config.get("days", 7))
        if days < 0:
            raise ValueError("days must be zero or greater")

        output_root = Path(config.get("download_folder", "./downloads")).expanduser()
        output_root.mkdir(parents=True, exist_ok=True)
        cutoff = date.today() - timedelta(days=days)

        cookies_file_value = config.get("cookies_file")
        cookies_file = (
            Path(cookies_file_value).expanduser()
            if cookies_file_value
            else None
        )
        if cookies_file is not None and not cookies_file.is_file():
            raise ValueError(f"cookies_file does not exist: {cookies_file}")

        max_videos_to_check = int(config.get("max_videos_to_check", 100))
        if max_videos_to_check < 0:
            raise ValueError("max_videos_to_check must be zero or greater")

        failures = sum(
            download_channel(
                channel,
                output_root,
                cutoff,
                cookies_file,
                max_videos_to_check,
            )
            != 0
            for channel in config["channels"]
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        LOGGER.error("Configuration error: %s", error)
        return 2

    if failures:
        LOGGER.error("%d channel(s) failed", failures)
        return 1
    LOGGER.info("Finished")
    return 0


if __name__ == "__main__":
    sys.exit(main())
