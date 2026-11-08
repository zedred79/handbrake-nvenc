# syntax=docker/dockerfile:1
#
# HandBrake with NVIDIA NVENC/NVDEC on top of jlesage/baseimage-gui (Ubuntu).
#
# Based on the work of jlesage (https://github.com/jlesage/docker-handbrake)
# and zocker-160 (https://github.com/zocker-160/handbrake-nvenc-docker).
#
# All versions are build args; the defaults below are overridden in CI with
# the values from versions.env.

ARG UBUNTU_VERSION=26.04
ARG BASEIMAGE_VERSION=4.14.0
ARG HANDBRAKE_VERSION=1.11.2
ARG DOCKER_HANDBRAKE_VERSION=v26.09.1
ARG CPU_FEATURES_VERSION=0.11.0
ARG HANDBRAKE_DEBUG_MODE=none
ARG ENABLE_DVDCSS=false

# ---------------------------------------------------------------------------
# Upstream files (rootfs with the start scripts + patches) from jlesage.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS upstream
ARG DOCKER_HANDBRAKE_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir /upstream \
 && curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors "https://codeload.github.com/jlesage/docker-handbrake/tar.gz/refs/tags/${DOCKER_HANDBRAKE_VERSION}" \
    | tar xz --strip-components=1 -C /upstream \
 && test -d /upstream/rootfs \
 && test -f /upstream/src/handbrake/maximized-window.patch

# ---------------------------------------------------------------------------
# cpu_features (used by the upstream scripts for CPU detection).
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS cpu_features
ARG CPU_FEATURES_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl cmake make g++ \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir /src \
 && curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors "https://github.com/google/cpu_features/archive/refs/tags/v${CPU_FEATURES_VERSION}.tar.gz" \
    | tar xz --strip-components=1 -C /src \
 && cmake -S /src -B /src/build \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_EXECUTABLE=ON \
 && cmake --build /src/build -j"$(nproc)" \
 && install -D /src/build/list_cpu_features /out/bin/list_cpu_features

# ---------------------------------------------------------------------------
# HandBrake build (GUI + CLI) with NVENC/NVDEC.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS builder
ARG HANDBRAKE_VERSION
ARG HANDBRAKE_DEBUG_MODE
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    appstream autoconf automake autopoint build-essential bzip2 ca-certificates \
    cargo cargo-c clang cmake curl desktop-file-utils diffutils file gettext git \
    intltool libass-dev libbz2-dev libdbus-glib-1-dev libdrm-dev \
    libfontconfig-dev libfreetype-dev libfribidi-dev libglib2.0-dev \
    libgstreamer-plugins-base1.0-dev libgtk-4-dev libgudev-1.0-dev \
    libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnotify-dev \
    libnuma-dev libogg-dev libopus-dev libpciaccess-dev libsamplerate0-dev \
    libspeex-dev libssl-dev libtheora-dev libtool libtool-bin libturbojpeg0-dev \
    libva-dev libvorbis-dev libvpx-dev libx264-dev libxml2-dev m4 make meson \
    nasm ninja-build patch pkg-config python3 rustc tar xz-utils yasm zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

COPY --from=upstream /upstream/src/handbrake/maximized-window.patch /tmp/maximized-window.patch

RUN mkdir /tmp/handbrake \
 && curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors "https://github.com/HandBrake/HandBrake/releases/download/${HANDBRAKE_VERSION}/HandBrake-${HANDBRAKE_VERSION}-source.tar.bz2" \
    | tar xj --strip-components=1 -C /tmp/handbrake \
 && patch -d /tmp/handbrake -p1 < /tmp/maximized-window.patch

# NVENC/NVDEC use the headers bundled in HandBrake's contrib; the NVIDIA
# driver libraries are injected at runtime by the NVIDIA container toolkit.
# QSV/VCE are disabled on purpose (this image targets NVIDIA GPUs).
RUN cd /tmp/handbrake && ./configure \
      --verbose \
      --prefix=/usr \
      --build=build \
      --debug="${HANDBRAKE_DEBUG_MODE}" \
      --enable-fdk-aac \
      --enable-x265 \
      --enable-libdovi \
      --enable-numa \
      --enable-nvenc \
      --enable-nvdec \
      --disable-qsv \
      --disable-vce

RUN make -C /tmp/handbrake/build -j"$(nproc)"
RUN make DESTDIR=/install -C /tmp/handbrake/build -j1 install \
 && rm -rf /install/usr/include /install/usr/lib/pkgconfig \
           /install/usr/share/metainfo /install/usr/share/applications \
 && rm -f /install/usr/lib/*.la

# Work out which Ubuntu packages provide the shared libraries the binaries
# link against, so the runtime stage installs exactly those (no hardcoded
# soname/package names that break on every Ubuntu release).
RUN set -eu; \
    ldd /install/usr/bin/ghb /install/usr/bin/HandBrakeCLI > /tmp/ldd.txt; \
    if grep -q "not found" /tmp/ldd.txt; then cat /tmp/ldd.txt; echo "Unresolved libraries"; exit 1; fi; \
    awk '/=> \// {print $3}' /tmp/ldd.txt | sort -u | while read -r f; do \
        dpkg-query -S "$(readlink -f "$f")" 2>/dev/null | head -n1 | sed 's/[:,].*//' || true; \
    done | sort -u > /runtime-pkgs.txt; \
    echo "Runtime packages:"; cat /runtime-pkgs.txt; \
    test -s /runtime-pkgs.txt

# ---------------------------------------------------------------------------
# Final image.
# ---------------------------------------------------------------------------
FROM jlesage/baseimage-gui:ubuntu-${UBUNTU_VERSION}-v${BASEIMAGE_VERSION}
ARG HANDBRAKE_VERSION
ARG ENABLE_DVDCSS
ARG DOCKER_IMAGE_VERSION=
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

COPY --from=builder /runtime-pkgs.txt /tmp/runtime-pkgs.txt

RUN apt-get update \
 && xargs -a /tmp/runtime-pkgs.txt apt-get install -y --no-install-recommends \
 && apt-get install -y --no-install-recommends \
      adwaita-icon-theme bash ca-certificates coreutils expect findutils \
      fonts-cantarell gstreamer1.0-libav gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good librsvg2-common lsscsi pciutils x11-utils \
 && if [ "${ENABLE_DVDCSS}" = "true" ]; then \
      apt-get install -y libdvd-pkg && dpkg-reconfigure libdvd-pkg; \
    fi \
 && apt-get autoremove -y && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/runtime-pkgs.txt

# Generate and install favicons.
RUN apt-get update \
 && install_app_icon.sh "https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/handbrake-icon.png" \
 && apt-get autoremove -y && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=upstream /upstream/rootfs/ /
COPY --from=builder /install/ /
COPY --from=cpu_features /out/bin/list_cpu_features /usr/bin/list_cpu_features

RUN set-cont-env APP_NAME "HandBrake" \
 && set-cont-env APP_VERSION "${HANDBRAKE_VERSION}" \
 && set-cont-env DOCKER_IMAGE_VERSION "${DOCKER_IMAGE_VERSION}" \
 && set-cont-env DISABLE_GLX 1

# NVIDIA container toolkit: expose the GPU and the video encode/decode libs.
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all

# Public environment variables (same defaults as jlesage/docker-handbrake).
ENV \
    HANDBRAKE_DEBUG=0 \
    HANDBRAKE_GUI=1 \
    HANDBRAKE_GUI_QUEUE_STARTUP_ACTION=NONE \
    AUTOMATED_CONVERSION=1 \
    AUTOMATED_CONVERSION_PRESET="General/Very Fast 1080p30" \
    AUTOMATED_CONVERSION_FORMAT=mp4 \
    AUTOMATED_CONVERSION_SOURCE_STABLE_TIME=5 \
    AUTOMATED_CONVERSION_SOURCE_MIN_DURATION=10 \
    AUTOMATED_CONVERSION_SOURCE_MAIN_TITLE_DETECTION=0 \
    AUTOMATED_CONVERSION_KEEP_SOURCE=1 \
    AUTOMATED_CONVERSION_WATCH_DIR=AUTO \
    AUTOMATED_CONVERSION_OUTPUT_DIR=/output \
    AUTOMATED_CONVERSION_OUTPUT_SUBDIR= \
    AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0 \
    AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS= \
    AUTOMATED_CONVERSION_NON_VIDEO_FILE_ACTION=ignore \
    AUTOMATED_CONVERSION_NON_VIDEO_FILE_EXTENSIONS="jpg jpeg bmp png gif txt nfo" \
    AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS=5 \
    AUTOMATED_CONVERSION_CHECK_INTERVAL=5 \
    AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS= \
    AUTOMATED_CONVERSION_NO_GUI_PROGRESS=0 \
    AUTOMATED_CONVERSION_USE_TRASH=0 \
    AUTOMATED_CONVERSION_TRASH_DIR=/trash

VOLUME ["/config"]
VOLUME ["/storage"]
VOLUME ["/output"]
VOLUME ["/watch"]
VOLUME ["/trash"]

LABEL \
      org.opencontainers.image.title="handbrake-nvenc" \
      org.opencontainers.image.description="HandBrake GUI/CLI with NVIDIA NVENC, on jlesage/baseimage-gui" \
      org.opencontainers.image.version="${HANDBRAKE_VERSION}"
