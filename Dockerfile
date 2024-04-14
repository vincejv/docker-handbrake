#
# handbrake Dockerfile
#

# Docker image version is provided via build arg.
ARG DOCKER_IMAGE_VERSION=

# Define software versions.
ARG HANDBRAKE_VERSION=1.7.3
ARG LIBVA_VERSION=2.20.0
ARG INTEL_VAAPI_DRIVER_VERSION=2.4.1
ARG GMMLIB_VERSION=22.3.12
ARG INTEL_MEDIA_DRIVER_VERSION=23.3.5
ARG INTEL_MEDIA_SDK_VERSION=23.2.2
ARG INTEL_ONEVPL_GPU_RUNTIME_VERSION=23.3.4
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

COPY --from=xx / /
COPY src/handbrake /build
RUN /build/build.sh \
    "$HANDBRAKE_VERSION" \
    "$HANDBRAKE_URL" \
    "$HANDBRAKE_DEBUG_MODE"
RUN xx-verify \
    /tmp/handbrake-install/usr/bin/HandBrakeCLI
