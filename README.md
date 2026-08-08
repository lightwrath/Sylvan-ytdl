# YouTube recent-video downloader

Downloads videos uploaded within the configured number of previous days, creating one directory per channel. A per-channel yt-dlp archive prevents videos from being downloaded twice.

## Install

The deployment helper creates a virtual environment, installs yt-dlp, and checks for ffmpeg:

```bash
./youtube-downloader.sh install
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

The download folder and default seven-day window are set in `channels.json`. Override the window for one run with:

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
