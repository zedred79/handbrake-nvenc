# handbrake-nvenc

HandBrake (GUI in the browser + CLI) with **NVIDIA NVENC/NVDEC** hardware
encoding, packaged as a Docker image on Ubuntu 26.04 LTS.

It reuses the start scripts, watch-folder automation and environment variables
of [jlesage/docker-handbrake](https://github.com/jlesage/docker-handbrake) (all
`AUTOMATED_CONVERSION_*` options work the same), and replaces the Alpine build
with an Ubuntu one so the NVIDIA driver libraries can be used. Inspired by
[zocker-160/handbrake-nvenc-docker](https://github.com/zocker-160/handbrake-nvenc-docker).

## Always up to date

A GitHub Actions workflow runs daily and follows the latest release of
`jlesage/docker-handbrake`: HandBrake version, base image and helper versions
are read from there. When something changes, the image is built, smoke-tested,
pushed to GHCR, and only then `versions.env` is updated. If the build fails, an
issue is opened and the previous image stays available.

Tags: `latest`, `<handbrake version>` (e.g. `1.11.2`),
`<handbrake version>-<jlesage release>`.

> GitHub disables scheduled workflows in a repository with no activity for 60
> days. Re-enable from the Actions tab if that happens (or trigger the workflow
> manually).

## Requirements

- Docker with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- A recent NVIDIA driver on the host

## Run

```sh
docker run -d --name handbrake --gpus all -p 5800:5800 \
  -v ./config:/config -v ./storage:/storage:ro \
  -v ./watch:/watch -v ./output:/output \
  ghcr.io/zedred79/handbrake-nvenc:latest
```

Open http://localhost:5800 and pick an `NVEnc` encoder. See
`docker-compose.yml` for a Compose example.

## Differences from upstream jlesage image

- Ubuntu instead of Alpine (NVIDIA libraries are glibc-only)
- NVENC/NVDEC enabled; Intel QSV/VCE disabled
- libdvdcss is **not** installed by default; build with
  `--build-arg ENABLE_DVDCSS=true` if it is legal for you to use it

## Notes

- The CI smoke test has no GPU: it checks that the binaries run and contain
  the NVENC encoders, and that the container starts (web UI on port 5800,
  HandBrake GUI running). A real encode needs a machine with an NVIDIA GPU.
- HandBrake is GPL-2.0; the jlesage scripts are MIT. Add a LICENSE file for
  your own changes.
