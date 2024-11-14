# syntax=docker/dockerfile:1.10

# Please see https://docs.docker.com/engine/reference/builder for information about
# the extended buildx capabilities used in this file.
# Make sure multiarch TARGETPLATFORM is available for interpolation
# See: https://docs.docker.com/build/building/multi-platform/
ARG TARGETPLATFORM=${TARGETPLATFORM}
ARG BUILDPLATFORM=${BUILDPLATFORM}

# Base image
ARG DEBIAN_VERSION="bookworm"
FROM docker.io/debian:${DEBIAN_VERSION}-slim AS debian


# Timezone used by the Docker container and runtime, change with [--build-arg TZ=Europe/Berlin]
ARG TZ="Etc/UTC"
# Linux UID (user id) for the mastodon user, change with [--build-arg UID=1234]
ARG UID="991"
# Linux GID (group id) for the mastodon user, change with [--build-arg GID=1234]
ARG GID="991"

# Apply Mastodon build options based on options above
ENV \
  TZ=${TZ}

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

ARG TARGETPLATFORM

RUN echo "Target platform is $TARGETPLATFORM"

RUN \
# Remove automatic apt cache Docker cleanup scripts
  rm -f /etc/apt/apt.conf.d/docker-clean; \
# Sets timezone
  echo "${TZ}" > /etc/localtime; \
# Creates mastodon user/group and sets home directory
  groupadd -g "${GID}" mastodon; \
  useradd -l -u "${UID}" -g "${GID}" -m -d /opt/mastodon mastodon; \
# Creates /mastodon symlink to /opt/mastodon
  ln -s /opt/mastodon /mastodon;

# Set /opt/mastodon as working directory
WORKDIR /opt/mastodon

# hadolint ignore=DL3008,DL3005
RUN \
# Mount Apt cache and lib directories from Docker buildx caches
--mount=type=cache,id=apt-cache-${TARGETPLATFORM},target=/var/cache/apt,sharing=locked \
--mount=type=cache,id=apt-lib-${TARGETPLATFORM},target=/var/lib/apt,sharing=locked \
# Apt update & upgrade to check for security updates to Debian image
  apt-get update; \
  apt-get dist-upgrade -yq; \
# Install jemalloc, curl and other necessary components
  apt-get install -y --no-install-recommends \
    curl \
    file \
    libjemalloc2 \
    patchelf \
    procps \
    tini \
    tzdata \
    wget \
  ;

# Create temporary build layer from base image
FROM debian AS build

ARG TARGETPLATFORM

# hadolint ignore=DL3008
RUN \
# Mount Apt cache and lib directories from Docker buildx caches
--mount=type=cache,id=apt-cache-${TARGETPLATFORM},target=/var/cache/apt,sharing=locked \
--mount=type=cache,id=apt-lib-${TARGETPLATFORM},target=/var/lib/apt,sharing=locked \
# Install build tools and bundler dependencies from APT
  apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    cmake \
    git \
    libgdbm-dev \
    libglib2.0-dev \
    libgmp-dev \
    libicu-dev \
    libidn-dev \
    libpq-dev \
    libssl-dev \
    libtool \
    meson \
    nasm \
    pkg-config \
    shared-mime-info \
    xz-utils \
	# libvips components
    libcgif-dev \
    libexif-dev \
    libexpat1-dev \
    libgirepository1.0-dev \
    libheif-dev \
    libimagequant-dev \
    libjpeg62-turbo-dev \
    liblcms2-dev \
    liborc-dev \
    libspng-dev \
    libtiff-dev \
    libwebp-dev \
  # ffmpeg components
    libdav1d-dev \
    liblzma-dev \
    libmp3lame-dev \
    libopus-dev \
    libsnappy-dev \
    libvorbis-dev \
    libvpx-dev \
    libx264-dev \
    libx265-dev \
  ;

# libvips version to compile, change with [--build-arg VIPS_VERSION="8.15.2"]
# renovate: datasource=github-releases depName=libvips packageName=libvips/libvips
ARG VIPS_VERSION=8.16.0
# libvips download URL, change with [--build-arg VIPS_URL="https://github.com/libvips/libvips/releases/download"]
ARG VIPS_URL=https://github.com/libvips/libvips/releases/download

WORKDIR /usr/local/libvips/src
# Download and extract libvips source code
ADD ${VIPS_URL}/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz /usr/local/libvips/src/
RUN tar xf vips-${VIPS_VERSION}.tar.xz;

WORKDIR /usr/local/libvips/src/vips-${VIPS_VERSION}

# Configure and compile libvips
RUN \
  meson setup build --prefix /usr/local/libvips --libdir=lib -Ddeprecated=false -Dintrospection=disabled -Dmodules=disabled -Dexamples=false; \
  cd build; \
  ninja; \
  ninja install;

# ffmpeg version to compile, change with [--build-arg FFMPEG_VERSION="7.0.x"]
# renovate: datasource=repology depName=ffmpeg packageName=openpkg_current/ffmpeg
ARG FFMPEG_VERSION=7.1
# ffmpeg download URL, change with [--build-arg FFMPEG_URL="https://ffmpeg.org/releases"]
ARG FFMPEG_URL=https://ffmpeg.org/releases

WORKDIR /usr/local/ffmpeg/src
# Download and extract ffmpeg source code
ADD ${FFMPEG_URL}/ffmpeg-${FFMPEG_VERSION}.tar.xz /usr/local/ffmpeg/src/
RUN tar xf ffmpeg-${FFMPEG_VERSION}.tar.xz;

WORKDIR /usr/local/ffmpeg/src/ffmpeg-${FFMPEG_VERSION}

# Configure and compile ffmpeg
RUN \
  ./configure \
    --prefix=/usr/local/ffmpeg \
    --toolchain=hardened \
    --disable-debug \
    --disable-devices \
    --disable-doc \
    --disable-ffplay \
    --disable-network \
    --disable-static \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-gpl \
    --enable-libdav1d \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libsnappy \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libwebp \
    --enable-libx264 \
    --enable-libx265 \
    --enable-shared \
    --enable-version3 \
  ; \
  make -j$(nproc); \
  make install;

# RUN \
#   ldconfig; \
# # Smoketest media processors
#   vips -v; \
#   ffmpeg -version; \
#   ffprobe -version;

ENTRYPOINT ["/usr/bin/tini", "--"]
