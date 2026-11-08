# HandBrake with NVIDIA NVENC in Docker

[![Build and publish](https://github.com/zedred79/handbrake-nvenc/actions/workflows/build.yml/badge.svg)](https://github.com/zedred79/handbrake-nvenc/actions/workflows/build.yml)
[![Image on GHCR](https://img.shields.io/badge/ghcr.io-zedred79%2Fhandbrake--nvenc-blue?logo=docker)](https://github.com/zedred79/handbrake-nvenc/pkgs/container/handbrake-nvenc)

[HandBrake](https://handbrake.fr/) video transcoder, with **NVIDIA NVENC/NVDEC
hardware encoding and decoding**, packaged as a Docker image. It includes the
HandBrake GUI, which you use from any web browser, the `HandBrakeCLI` command
line tool, and a **watch folder** that converts every video you drop into it.

This image is built on top of the excellent
[jlesage/docker-handbrake](https://github.com/jlesage/docker-handbrake): it
reuses its start scripts, web interface and automatic conversion, so all of its
settings work the same way. The difference is the operating system: jlesage's
image is based on Alpine Linux, where the NVIDIA driver libraries cannot be
used. This image is built on **Ubuntu 26.04 LTS** with NVENC/NVDEC enabled.

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick start (`docker run`)](#quick-start-docker-run)
- [Docker Compose](#docker-compose)
- [Using the GUI](#using-the-gui)
- [Hardware encoding with NVENC](#hardware-encoding-with-nvenc)
- [Automatic conversion (watch folder)](#automatic-conversion-watch-folder)
- [Configuration reference](#configuration-reference)
- [Exposing it on the internet with SWAG](#exposing-it-on-the-internet-with-swag)
- [Optical drives (DVD / Blu-ray)](#optical-drives-dvd--blu-ray)
- [Image tags and updates](#image-tags-and-updates)
- [Building the image yourself](#building-the-image-yourself)
- [Troubleshooting](#troubleshooting)
- [Differences from jlesage/docker-handbrake](#differences-from-jlesagedocker-handbrake)
- [Credits and licenses](#credits-and-licenses)

---

## Features

- **NVENC hardware encoders**: H.264, H.265 (8 and 10 bit) and AV1 (8 and
  10 bit, on GPUs that support it).
- **NVDEC hardware decoding** of the source video.
- **HandBrake GUI in the browser** (port 5800), with optional VNC access
  (port 5900).
- **Watch folder**: videos dropped in `/watch` are converted automatically
  with the preset you choose. HandBrake already includes NVENC presets.
- **Same options as jlesage/docker-handbrake**: every
  `AUTOMATED_CONVERSION_*` variable, hooks, multiple watch folders, the web
  file manager.
- **Always up to date**: a daily GitHub Actions job follows jlesage's
  releases and builds, tests and publishes each new HandBrake version.

## Requirements

- A Linux host with an **NVIDIA GPU**. According to the
  [HandBrake NVENC documentation](https://handbrake.fr/docs/en/latest/technical/video-nvenc.html),
  HandBrake needs a GeForce RTX **Turing (RTX 2060) or newer**, or an
  equivalent professional/data-center GPU. The
  [NVENC support matrix](https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new)
  shows which codecs your GPU can encode. AV1, for example, needs an RTX 40
  series or newer.
- The **NVIDIA driver** installed on the host, **version 610 or later**
  (HandBrake's documented minimum, see the link above). With an older driver
  the NVEnc encoders do not appear.
- **Docker** with the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

Check that Docker can see the GPU before going further:

```sh
docker run --rm --gpus all ubuntu nvidia-smi
```

If this prints your GPU, you are ready. If it fails, fix the driver or the
Container Toolkit first: this image cannot work without them.

## Quick start (`docker run`)

```sh
docker run -d \
  --name handbrake \
  --gpus all \
  -p 5800:5800 \
  -e USER_ID=$(id -u) \
  -e GROUP_ID=$(id -g) \
  -e TZ=Europe/London \
  -v /docker/handbrake/config:/config:rw \
  -v /path/to/your/videos:/storage:ro \
  -v /docker/handbrake/watch:/watch:rw \
  -v /docker/handbrake/output:/output:rw \
  --restart unless-stopped \
  ghcr.io/zedred79/handbrake-nvenc:latest
```

Then open **http://\<your-server-ip\>:5800** in a browser.

What each part does:

| Option | Meaning |
|---|---|
| `--gpus all` | Gives the container access to the NVIDIA GPU(s). Use `--gpus device=0` to pick one GPU. |
| `-p 5800:5800` | Web interface. Add `-p 5900:5900` if you also want to connect with a VNC client. |
| `USER_ID` / `GROUP_ID` | The user that runs HandBrake and owns the converted files. `$(id -u)` / `$(id -g)` use your current user. See [User and group IDs](#user-and-group-ids). |
| `TZ` | Time zone, used in logs. [List of time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). |
| `/config` | Settings, presets, logs. Keep it to keep your configuration across updates. |
| `/storage` | Your videos, mounted read-only, so you can open them from the GUI. |
| `/watch` | Watch folder: videos placed here are converted automatically. |
| `/output` | Where converted videos are written. |

## Docker Compose

This is the recommended way to run the container. Save it as
`docker-compose.yml`:

```yaml
services:
  handbrake:
    image: ghcr.io/zedred79/handbrake-nvenc:latest
    container_name: handbrake
    restart: unless-stopped
    ports:
      - "5800:5800"     # web interface
      # - "5900:5900"   # VNC (optional)
    environment:
      - USER_ID=1000                 # `id -u` of the owner of your media
      - GROUP_ID=1000                # `id -g`
      - TZ=Europe/London
      - KEEP_APP_RUNNING=1           # restart HandBrake if it is closed
      - DARK_MODE=1
      - WEB_FILE_MANAGER=1           # upload/download files from the browser
      # Watch folder: convert with the GPU
      - AUTOMATED_CONVERSION_PRESET=Hardware/H.265 NVENC 1080p
      - AUTOMATED_CONVERSION_FORMAT=mkv
    volumes:
      - ./config:/config:rw
      - /path/to/your/videos:/storage:ro
      - ./watch:/watch:rw
      - ./output:/output:rw
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all             # or: device_ids: ["0"]
              capabilities: [gpu, video, compute, utility]
```

Start it, and look at the log:

```sh
docker compose up -d
docker compose logs -f
```

### Ready-made setup with a `.env` file

The [`lan/`](lan/) folder of this repository contains the same Compose file,
with all paths and options read from a `.env` file, so you never need to edit
the YAML:

```sh
git clone https://github.com/zedred79/handbrake-nvenc.git
cd handbrake-nvenc/lan
cp .env.example .env      # set USER_ID/GROUP_ID, folders, preset...
docker compose up -d
```

It serves the web interface over plain HTTP, without a login. Use it on your
local network only. To reach HandBrake from the internet, put it behind a
reverse proxy: see [Exposing it on the internet with SWAG](#exposing-it-on-the-internet-with-swag).

## Using the GUI

Open `http://<server-ip>:5800`. The HandBrake window is shown directly in the
browser.

- **Open Source** lets you browse the container's filesystem. Your videos are
  in `/storage`. Save the result to `/output`.
- A small tab on the left edge of the page opens the **control panel**. It
  has fullscreen, clipboard, image quality and scaling settings, and the
  **file manager** (folder icon). Use the file manager to upload sources and
  download results when `WEB_FILE_MANAGER=1`.
- You can also connect with any VNC client to port 5900 if you published it.
  Set `VNC_PASSWORD` to protect it.

## Hardware encoding with NVENC

### In the GUI

In the **Video** tab, choose one of the **NVEnc** encoders, for example
*H.265 (NVEnc)*. Or start from a ready-made preset: **Presets → Hardware →
H.265 NVENC 1080p** (or **H.265 NVENC 2160p 4K**).

NVEnc encoders only appear when HandBrake can use the GPU. If you do not see
them, see [Troubleshooting](#troubleshooting).

### From the command line

`HandBrakeCLI` is included in the image. You can run it inside the running
container:

```sh
docker exec -u 1000:1000 handbrake HandBrakeCLI \
  -i "/storage/My Movie.mkv" \
  -o "/output/My Movie.mkv" \
  --preset "Hardware/H.265 NVENC 1080p" \
  --enable-hw-decoding nvdec
```

or choose the encoder and quality yourself:

```sh
docker exec -u 1000:1000 handbrake HandBrakeCLI \
  -i "/storage/My Movie.mkv" -o "/output/My Movie.mkv" \
  -e nvenc_h265_10bit -q 24 --enable-hw-decoding nvdec \
  --all-audio --all-subtitles
```

`-u 1000:1000` runs the command as your `USER_ID:GROUP_ID`, so the output
file is not owned by root.

Available NVENC encoders: `nvenc_h264`, `nvenc_h265`, `nvenc_h265_10bit`,
`nvenc_av1`, `nvenc_av1_10bit`. Your GPU must support the codec.
`--enable-hw-decoding nvdec` also decodes the source on the GPU.

### Check that the GPU is really used

```sh
# GPU visible inside the container
docker exec handbrake nvidia-smi

# NVENC encoders available to HandBrake
docker exec handbrake HandBrakeCLI --help 2>&1 | grep -i nvenc

# While encoding: the "enc" (and "dec") columns must be above 0
nvidia-smi dmon -s u
```

## Automatic conversion (watch folder)

Every video placed in `/watch` is converted with the preset set in
`AUTOMATED_CONVERSION_PRESET` and written to `/output`. Progress is shown in
the GUI and in `docker logs handbrake`. The full log is
`/config/log/hb/conversion.log`.

To convert with the GPU, use one of HandBrake's hardware presets:

```yaml
- AUTOMATED_CONVERSION_PRESET=Hardware/H.265 NVENC 1080p
```

or your own preset. Create it in the GUI: set everything up, choose an NVEnc
encoder, then **Presets → Save New Preset**. Then refer to it as
`<category>/<name>`, for example `My Presets/Movies NVENC`. Presets saved in
the GUI are stored in `/config` and the watch folder uses them too.

Useful options:

| Variable | Default | Description |
|---|---|---|
| `AUTOMATED_CONVERSION` | `1` | `0` disables the watch folder. |
| `AUTOMATED_CONVERSION_PRESET` | `General/Very Fast 1080p30` | Preset, as `<category>/<name>`. The default encodes on the CPU: set an NVENC preset to use the GPU. |
| `AUTOMATED_CONVERSION_FORMAT` | `mp4` | Output container (`mp4`, `mkv`, `webm`). |
| `AUTOMATED_CONVERSION_KEEP_SOURCE` | `1` | `0` deletes the source after a successful conversion. |
| `AUTOMATED_CONVERSION_OUTPUT_SUBDIR` | | Subfolder of `/output`. `SAME_AS_SRC` keeps the source's folder structure. |
| `AUTOMATED_CONVERSION_OVERWRITE_OUTPUT` | `0` | `1` overwrites existing output files. |
| `AUTOMATED_CONVERSION_SOURCE_STABLE_TIME` | `5` | Seconds a file must stay unchanged before it is processed, so that files still being copied are not picked up. |
| `AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS` | | Extra `HandBrakeCLI` arguments, e.g. `--enable-hw-decoding nvdec`. |
| `AUTOMATED_CONVERSION_NON_VIDEO_FILE_ACTION` | `ignore` | `copy` copies non-video files (subtitles, NFO...) to the output. |
| `AUTOMATED_CONVERSION_USE_TRASH` | `0` | With `KEEP_SOURCE=0`, move sources to `/trash` instead of deleting them. |

The full list is in the
[upstream documentation](https://github.com/jlesage/docker-handbrake#environment-variables).

**Multiple watch folders.** Mount more folders as `/watch2`, `/watch3`, ...
(up to `AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS`, default 5). Each one can have
its own settings: add the folder number to the end of the variable name.
For example, use 1080p for movies and 4K for a second folder:

```yaml
environment:
  - AUTOMATED_CONVERSION_PRESET=Hardware/H.265 NVENC 1080p
  - AUTOMATED_CONVERSION_PRESET_2=Hardware/H.265 NVENC 2160p 4K
volumes:
  - ./watch:/watch:rw
  - ./watch-4k:/watch2:rw
```

**Discs.** ISO files and `VIDEO_TS` / `BDMV` folders are converted too, one
output file per title.

**Hooks.** Shell scripts in `/config/hooks/` run before and after each
conversion, for example to notify you or move files. Example scripts with a
`.example` suffix are copied there. See the
[upstream documentation](https://github.com/jlesage/docker-handbrake#hooks).

## Configuration reference

### Volumes

| Container path | Mode | Description |
|---|---|---|
| `/config` | rw | Settings, presets, logs, hooks. |
| `/storage` | ro | Files you want to open from the GUI. |
| `/watch` | rw | Watch folder (plus `/watch2`, `/watch3`, ... if used). |
| `/output` | rw | Converted videos. |
| `/trash` | rw | Optional, used with `AUTOMATED_CONVERSION_USE_TRASH=1`. |

### Ports

| Port | Description |
|---|---|
| 5800 | Web interface (HTTP, or HTTPS with `SECURE_CONNECTION=1`). |
| 5900 | VNC (optional). |

### Main environment variables

| Variable | Default | Description |
|---|---|---|
| `USER_ID` / `GROUP_ID` | `1000` | User and group that run HandBrake and own the files it writes. |
| `TZ` | `Etc/UTC` | Time zone. |
| `UMASK` | `0022` | Permissions of new files (`0002` makes them group-writable). |
| `KEEP_APP_RUNNING` | `0` | `1` restarts HandBrake if it is closed or crashes. |
| `DARK_MODE` | `0` | `1` enables the dark theme. |
| `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` | `1920` / `1080` | Size of the HandBrake window. |
| `WEB_FILE_MANAGER` | `0` | `1` enables the file manager in the web interface. |
| `VNC_PASSWORD` | | Password for VNC clients. |
| `HANDBRAKE_GUI` | `1` | `0` disables the GUI and keeps only the watch folder. |
| `HANDBRAKE_DEBUG` | `0` | `1` enables HandBrake debug logs (they grow fast). |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Which GPUs the container sees (`all`, an index such as `0`, or a UUID from `nvidia-smi -L`). |
| `NVIDIA_DRIVER_CAPABILITIES` | `all` | Must include `video` for NVENC/NVDEC. Leave it at `all`. |
| `SECURE_CONNECTION` | `0` | `1` serves the web interface over HTTPS with a self-signed certificate. |
| `WEB_AUTHENTICATION` | `0` | `1` adds a login page. **Requires `SECURE_CONNECTION=1`.** |
| `WEB_AUTHENTICATION_USERNAME` / `_PASSWORD` | | Credentials for the login page. |

All the other options of the base image (web audio, web terminal,
notifications, etc.) are described in the
[jlesage/docker-handbrake documentation](https://github.com/jlesage/docker-handbrake#environment-variables).

### User and group IDs

HandBrake inside the container runs as `USER_ID:GROUP_ID`. Set them to the
owner of your media folders, otherwise HandBrake may not be able to write to
`/output` or `/watch`. Find the values on the host with:

```sh
id your-user
# uid=1000(your-user) gid=1000(your-user) ...
```

## Exposing it on the internet with SWAG

The web interface gives full control of HandBrake and of the mounted folders.
**Do not publish port 5800 on the internet as it is.** Put the container
behind a reverse proxy that handles HTTPS and authentication. This repository
contains a ready configuration for
[SWAG](https://github.com/linuxserver/docker-swag) in [`lan/swag/`](lan/swag/):

1. Copy [`lan/swag/handbrake.subdomain.conf`](lan/swag/handbrake.subdomain.conf)
   to `<swag config>/nginx/proxy-confs/`. Your DNS must have a record for
   `handbrake.<your-domain>`, and the SWAG certificate must cover it
   (`SUBDOMAINS=handbrake`, or a wildcard).
2. Create a user for HTTP basic authentication. It is enabled by default in
   the conf. Omit `-c` if `.htpasswd` already exists:
   ```sh
   docker exec -it swag htpasswd -c /config/nginx/.htpasswd <user>
   ```
   If you use Authelia, Authentik, LDAP or Tinyauth, enable the matching
   lines instead, **in both `location` blocks** of the file.
3. In `lan/.env`, set `SWAG_NETWORK` to the Docker network SWAG is on, then
   start HandBrake with the SWAG override. It joins that network and stops
   publishing port 5800 on the host:
   ```sh
   docker compose -f docker-compose.yml -f docker-compose.swag.yml up -d
   ```
4. Restart SWAG (`docker restart swag`) and open
   `https://handbrake.<your-domain>`.

The conf also handles the WebSocket connections used by the remote desktop
and the file manager. They are protected by the same login. They also stay
open when the screen is idle: SWAG's default 240 s timeout would otherwise
disconnect the session.

If you use another reverse proxy, forward everything to `http://handbrake:5800`
with WebSocket support (`Upgrade`/`Connection` headers) and long read
timeouts.

## Optical drives (DVD / Blu-ray)

Pass the drive to the container:

```yaml
devices:
  - /dev/sr0:/dev/sr0
  - /dev/sg0:/dev/sg0
```

`lsscsi -g` on the host shows which devices belong to the drive. The container
log also tells you at startup which devices it found and which are missing.
In the GUI, open `/dev/sr0` as the source.

Encrypted DVDs need **libdvdcss**, which is **not included** in the published
image for legal reasons. If its use is legal where you live, build the image
yourself with `--build-arg ENABLE_DVDCSS=true` (see below).

## Image tags and updates

| Tag | Content |
|---|---|
| `latest` | Latest build. |
| `1.11.2` | A given HandBrake version (latest build of it). |
| `1.11.2-v26.09.1` | HandBrake version + the jlesage release it is based on. Use this to pin an exact version. |

A [GitHub Actions workflow](.github/workflows/build.yml) runs every day and
checks the latest release of jlesage/docker-handbrake. When it changes, the
workflow:

1. builds the image with the new HandBrake version and helper versions;
2. runs a smoke test: the binaries start, the NVENC encoders are built in,
   the container starts, and the web interface answers;
3. publishes it to GHCR, and only then records the new versions in
   [`versions.env`](versions.env).

If a build fails, an issue is opened and the previous image stays
available. The CI runners have no GPU, so the smoke test cannot run a real
NVENC encode.

To update your container:

```sh
docker compose pull && docker compose up -d
```

> GitHub pauses scheduled workflows in repositories with no activity for 60
> days. If that happens, re-enable the workflow from the *Actions* tab or run
> it manually.

## Building the image yourself

```sh
git clone https://github.com/zedred79/handbrake-nvenc.git
cd handbrake-nvenc
docker buildx build --load -t handbrake-nvenc .
```

HandBrake and its libraries (FFmpeg, x265, SVT-AV1, ...) are compiled from
source, so the first build takes a while: from about 20 minutes to over an
hour, depending on the CPU.

Build arguments (defaults in the [`Dockerfile`](Dockerfile) and
[`versions.env`](versions.env)):

| Argument | Description |
|---|---|
| `HANDBRAKE_VERSION` | HandBrake version to build. |
| `DOCKER_HANDBRAKE_VERSION` | jlesage/docker-handbrake release used for scripts and patches. |
| `BASEIMAGE_VERSION` | Version of `jlesage/baseimage-gui`. |
| `UBUNTU_VERSION` | Ubuntu release (base image and build stages). |
| `ENABLE_DVDCSS` | `true` builds and includes libdvdcss. |
| `HANDBRAKE_DEBUG_MODE` | HandBrake debug build: `none`, `min`, `std`, `max`. |

## Troubleshooting

**No NVEnc encoders in the GUI / `Cannot load libnvidia-encode.so.1` in the
log.** HandBrake cannot reach the NVIDIA libraries. Check, in order:

- `docker run --rm --gpus all ubuntu nvidia-smi` works on the host;
- the container is started with `--gpus all` (or the `deploy` section in
  Compose);
- `NVIDIA_DRIVER_CAPABILITIES` includes `video` (default `all`);
- the host driver is version 610 or later (`nvidia-smi` shows it), and the
  GPU is a Turing (RTX 20 series) or newer.

Without a GPU this message is normal: HandBrake still works, but only with the
CPU encoders.

**Encoding fails with "out of memory" or "OpenEncodeSessionEx failed".**
GeForce cards limit the number of NVENC encodes that can run at the same time.
Lower the number of parallel jobs, or check that other programs (Plex,
Jellyfin, OBS...) are not using all of them.

**The container restarts in a loop.** Look at `docker logs handbrake`.
`WEB_AUTHENTICATION=1` and `WEB_NOTIFICATION=1` refuse to start without
`SECURE_CONNECTION=1`. Behind a reverse proxy, leave all three at `0` and let
the proxy handle HTTPS and login.

**"Permission denied" when writing to `/output` or `/watch`.** `USER_ID` and
`GROUP_ID` do not match the owner of the host folders. See
[User and group IDs](#user-and-group-ids).

**Behind a reverse proxy the screen stays black or keeps reconnecting.**
The proxy must forward WebSocket connections (`/websockify`,
`/ws-filemanager`) with the `Upgrade` and `Connection` headers and a long
timeout. The [SWAG conf](lan/swag/handbrake.subdomain.conf) does this.

## Differences from jlesage/docker-handbrake

| | jlesage/docker-handbrake | this image |
|---|---|---|
| Base OS | Alpine Linux | Ubuntu 26.04 LTS |
| NVIDIA NVENC / NVDEC | not usable (NVIDIA libraries need glibc) | enabled |
| Intel Quick Sync (QSV) / AMD VCE | enabled | disabled |
| libdvdcss | included | optional at build time (`ENABLE_DVDCSS=true`) |
| Scripts, web UI, settings | | the same, taken from the jlesage release |

## Credits and licenses

- [HandBrake](https://handbrake.fr/) is licensed under the
  [GPL-2.0](https://github.com/HandBrake/HandBrake/blob/master/LICENSE).
- [jlesage/docker-handbrake](https://github.com/jlesage/docker-handbrake) and
  [jlesage/docker-baseimage-gui](https://github.com/jlesage/docker-baseimage-gui)
  by Jocelyn Le Sage (MIT): start scripts, web interface and automatic
  conversion.
- [zocker-160/handbrake-nvenc-docker](https://github.com/zocker-160/handbrake-nvenc-docker)
  inspired the NVENC build.

NVIDIA, NVENC and NVDEC are trademarks of NVIDIA Corporation. This project is
not affiliated with HandBrake, jlesage or NVIDIA.
