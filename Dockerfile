#
# handbrake Dockerfile
#
# https://github.com/jlesage/docker-handbrake
#

# Docker image version is provided via build arg.
ARG DOCKER_IMAGE_VERSION=

# Define software versions.
ARG HANDBRAKE_VERSION=1.7.3
ARG CPU_FEATURES_VERSION=0.9.0

# Define software download URLs.
ARG HANDBRAKE_URL=https://github.com/HandBrake/HandBrake/releases/download/${HANDBRAKE_VERSION}/HandBrake-${HANDBRAKE_VERSION}-source.tar.bz2
ARG CPU_FEATURES_URL=https://github.com/google/cpu_features/archive/refs/tags/v${CPU_FEATURES_VERSION}.tar.gz

# Set to 'max' to keep debug symbols.
ARG HANDBRAKE_DEBUG_MODE=none

# Get Dockerfile cross-compilation helpers.
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

# Build HandBrake.
FROM --platform=$BUILDPLATFORM ubuntu:jammy AS handbrake
ARG TARGETPLATFORM
ARG HANDBRAKE_VERSION
ARG HANDBRAKE_URL
ARG HANDBRAKE_DEBUG_MODE
ARG MARCH

# COPY --from=xx / /
COPY src/handbrake /build
RUN /build/build.sh \
    "$HANDBRAKE_VERSION" \
    "$HANDBRAKE_URL" \
    "$HANDBRAKE_DEBUG_MODE" \
    "$MARCH"
# RUN xx-verify \
#     /tmp/handbrake-install/usr/bin/ghb \
#     /tmp/handbrake-install/usr/bin/HandBrakeCLI

# Build cpu_features.
FROM --platform=$BUILDPLATFORM ubuntu:jammy AS cpu_features
ARG TARGETPLATFORM
ARG CPU_FEATURES_URL
COPY --from=xx / /
COPY src/cpu_features /build
RUN /build/build.sh "$CPU_FEATURES_URL"
RUN xx-verify /tmp/cpu_features-install/bin/list_cpu_features

# Pull base image.
FROM jlesage/baseimage-gui:ubuntu-22.04-v4

ARG HANDBRAKE_VERSION
ARG DOCKER_IMAGE_VERSION

# Define working directory.
WORKDIR /tmp

# Install dependencies.
RUN \
    add-pkg \
        libgtk-3-0 \
        libgudev-1.0-0 \
        libdbus-glib-1-dev \
        libnotify-dev \
        libsamplerate0 \
        libass9 \
        libjansson4 \
        liblzma5 \
        libbz2-1.0 \
        libnuma1 \
        # Media codecs:
        libtheora0 \
        libmp3lame0 \
        libvorbis0a \
        libvorbisenc2 \
        libspeex1 \
        libturbojpeg \
        libvpx7 \
        # A font is needed.
        fonts-cantarell \
        # For main, big icons:
        librsvg2-dev \
        # For all other small icons:
        adwaita-icon-theme \
        # For optical drive listing:
        lsscsi \
        # For watchfolder
        bash \
        coreutils \
        findutils \
        expect

# Generate and install favicons.
RUN \
    APP_ICON_URL=https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/handbrake-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"

# Add files.
COPY rootfs/ /
COPY --from=handbrake /tmp/handbrake-install /
COPY --from=handbrake /usr/local/lib/libopus.so* /usr/lib/libx264.so* /usr/lib/x86_64-linux-gnu/
COPY --from=cpu_features /tmp/cpu_features-install/bin/list_cpu_features /usr/bin/

# Set internal environment variables.
RUN \
    set-cont-env APP_NAME "HandBrake" && \
    set-cont-env APP_VERSION "$HANDBRAKE_VERSION" && \
    set-cont-env DOCKER_IMAGE_VERSION "$DOCKER_IMAGE_VERSION" && \
    true

# Set public environment variables.
ENV \
    HANDBRAKE_DEBUG=0 \
    HANDBRAKE_GUI=1 \
    AUTOMATED_CONVERSION=1 \
    AUTOMATED_CONVERSION_PRESET="General/Very Fast 1080p30" \
    AUTOMATED_CONVERSION_FORMAT=mp4 \
    AUTOMATED_CONVERSION_SOURCE_STABLE_TIME=5 \
    AUTOMATED_CONVERSION_SOURCE_MIN_DURATION=10 \
    AUTOMATED_CONVERSION_SOURCE_MAIN_TITLE_DETECTION=0 \
    AUTOMATED_CONVERSION_KEEP_SOURCE=1 \
    AUTOMATED_CONVERSION_OUTPUT_DIR=/output \
    AUTOMATED_CONVERSION_OUTPUT_SUBDIR= \
    AUTOMATED_CONVERSION_OVERWRITE_OUTPUT=0 \
    AUTOMATED_CONVERSION_VIDEO_FILE_EXTENSIONS= \
    AUTOMATED_CONVERSION_NON_VIDEO_FILE_ACTION=ignore \
    AUTOMATED_CONVERSION_NON_VIDEO_FILE_EXTENSIONS="jpg jpeg bmp png gif txt nfo" \
    AUTOMATED_CONVERSION_MAX_WATCH_FOLDERS=5 \
    AUTOMATED_CONVERSION_CHECK_INTERVAL=5 \
    AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS= \
    AUTOMATED_CONVERSION_INSTALL_PKGS= \
    AUTOMATED_CONVERSION_NO_GUI_PROGRESS=0 \
    AUTOMATED_CONVERSION_USE_TRASH=0

# Define mountable directories.
VOLUME ["/storage"]
VOLUME ["/output"]
VOLUME ["/watch"]
VOLUME ["/trash"]

# Metadata.
LABEL \
      org.label-schema.name="handbrake" \
      org.label-schema.description="Docker container for HandBrake" \
      org.label-schema.version="${DOCKER_IMAGE_VERSION:-}" \
      org.label-schema.vcs-url="https://github.com/jlesage/docker-handbrake" \
      org.label-schema.schema-version="1.0"
