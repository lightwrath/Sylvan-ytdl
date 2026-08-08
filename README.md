# YouTube recent-video downloader

Downloads videos uploaded within the configured number of previous days, creating one directory per channel. A per-channel yt-dlp archive prevents videos from being downloaded twice.

## Install

The deployment helper creates a virtual environment, installs yt-dlp, and checks for ffmpeg:

```bash
./youtube-downloader.sh install
```

The requirements install yt-dlp's default extras, including the EJS challenge-solver distribution needed by YouTube's current JavaScript checks. Deno is also checked by the helper; the current EJS solver requires Deno 2.3 or newer. Alpine 3.20 ships an older Deno, so use this if necessary:

```sh
apk add --no-cache --repository https://dl-cdn.alpinelinux.org/alpine/edge/community deno
```

`ffmpeg` is recommended (and is required when yt-dlp needs to merge separate video and audio streams). The helper only warns if it is missing. On Debian/Ubuntu:

```bash
sudo apt install ffmpeg
```

## Configure and run

Edit `channels.json`, replacing the example channel with channel URLs such as `https://www.youtube.com/@channel/videos`:

```bash
./youtube-downloader.sh start
```

The download folder, default seven-day window, and maximum of 100 newest videos inspected per channel are set in `channels.json`. The maximum prevents excessive requests and YouTube rate limiting; set `max_videos_to_check` to `0` to inspect the full channel feed. Override the window for one run with:

```bash
./youtube-downloader.sh start --days 14
```

For periodic execution, use cron, for example every day at 03:00:

```cron
0 3 * * * /opt/youtube-downloader/youtube-downloader.sh start >> /var/log/youtube-downloader.log 2>&1
```

The script can also install dependencies and run immediately:

```bash
./youtube-downloader.sh install-start
```

## YouTube authentication cookies

If YouTube reports `Sign in to confirm you’re not a bot`, export cookies from a browser where YouTube is working and store them securely on the server. Use the Netscape-format cookies file and set its permissions:

```bash
mkdir -p /root/.config/sylvan-ytdl
chmod 700 /root/.config/sylvan-ytdl
chmod 600 /root/.config/sylvan-ytdl/youtube-cookies.txt
```

Add the path to `channels.json`:

```json
"cookies_file": "/root/.config/sylvan-ytdl/youtube-cookies.txt"
```

The cookies file is intentionally excluded from Git. Cookies expire and may need to be exported again periodically. Do not commit or share the file.
