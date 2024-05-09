#!/bin/sh
#
# Script to build HandBrake.
#
# Support for QSV requires multiple components:
#
# - libva: implementation for VA-API (Video Acceleration API), an open-source
#   library and API specification, which provides access to graphics hardware
#   acceleration capabilities for video processing.  It consists of a main
#   library and driver-specific acceleration backends for each supported
#   hardware vendor (aka drivers for libva).
#
# - Intel VAAPI driver
#   - Driver for libva.
#   - Used for older Intel generation CPUs.
#   - Provides `i965_drv_video.so` (under `/usr/lib/dri/`).
#
# - Intel Media Driver
#   - Driver for libva.
#   - Used for newer Intel generation CPUs.
#   - Provides `iHD_drv_video.so` (under `/usr/lib/dri/`).
#   - Depends on gmmlib.
#
# - Intel Media SDK
#   - High level library that provides API to access hardware-accelerated video
#     decode, encode and filtering on Intel graphics hardware platforms.
#   - Discontinued.
#   - Depends on libva.
#   - Provides `libmfx.so`, the dispatcher used to select the runtime
#     implementation to use (`libmfxhw64.so` or `libmfx-gen.so) depending on the
#     CPU.
#     - It is not used by HandBrake.
#     - HandBrake has an embedded version of the oneVPL dispatcher (libvpl.so),
#       statically linked.
#   - Provides `libmfxhw64.so`, a runtime implementation for older Intel CPUs.
#     It also includes its plugins (under `/usr/lib/mfx/`):
#     - `plugins/libmfx_hevce_hw64.so`
#     - `plugins/libmfx_hevc_fei_hw64.so`
#     - `plugins/libmfx_vp9e_hw64.so`
#     - `plugins/libmfx_h264la_hw64.so`
#     - `plugins/libmfx_hevcd_hw64.so`
#     - `plugins/libmfx_hevcd_hw64.so`
#     - `plugins/libmfx_vp8d_hw64.so`
#     - `plugins/libmfx_vp9d_hw64.so`
#
# - libvpl
#   - Implementation of the Intel oneAPI Video Processing Library (oneVPL).
#     oneVPL is the new name of Intel Media SDK.  It is the 2.x API continuation
#     of Intel Media SDK API.
#   - HandBrake has its embedded version of the oneVPL dispatcher (libvpl.so),
#     statically linked.
#     - The dispatcher supports runtime implementations from both the Media SDK
#       (`libmfxhw64.so`) and oneVPL (`libmfx-gen.so`).
#   - This library is not compiled by this script.
#
# - oneVPL GPU Runtime
#   - Provides `libmfx-gen.so` (under `/usr/lib/`), a runtime implementation
#     for latest Intel CPUs.
#   - Can be used by the Media SDK and oneVPL dispatchers.
#   - Successor of the Media SDK's runtime implementation.
#
# Some interesting links:
#   - https://trac.ffmpeg.org/wiki/Hardware/QuickSync
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Set same default compilation flags as abuild.
export CFLAGS="-pipe -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--strip-all -Wl,--as-needed"

# export CC=clang
# export CXX=clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
    echo ">>> $*"
}

HANDBRAKE_VERSION="${1:-}"
HANDBRAKE_URL="${2:-}"
HANDBRAKE_DEBUG_MODE="${3:-}"
MARCH="${4:-}"
HB_BUILD="${5:-}"

if [ -z "$HANDBRAKE_VERSION" ]; then
    log "ERROR: HandBrake version missing."
    exit 1
fi

if [ -z "$HANDBRAKE_URL" ]; then
    log "ERROR: HandBrake URL missing."
    exit 1
fi

if [ -z "$HANDBRAKE_DEBUG_MODE" ]; then
    log "ERROR: HandBrake debug mode missing."
    exit 1
fi

#
# Install required packages.
#
apt-get update && \
apt-get install -y \
    curl \
    binutils \
    git \
    make \
    cmake \
    pax \
    pkg-config \
    autoconf \
    automake \
    yasm \
    m4 \
    patch \
    coreutils \
    tar \
    liblzma-dev \
    libbz2-dev \
    file \
    python-is-python3 \
    intltool \
    diffutils \
    bash \
    nasm \
    meson \
    gettext \
    libglib2.0-dev \

apt-get install -y \
    gcc \
    build-essential \
    ninja-build \
    patch \
    libssl-dev \

# misc libraries
apt-get install -y \
    libtool \
    libtool-bin \
    libjansson-dev \
    libxml2-dev \
    libnuma-dev \
    libturbojpeg0-dev \

# media libraries
apt-get install -y \
    libsamplerate0-dev \
    libass-dev \

# media codecs
apt-get install -y \
    libogg-dev \
    libtheora-dev \
    libmp3lame-dev \
    libvorbis-dev \
    libspeex-dev \
    libvpx-dev \

# gtk
apt-get install -y \
    libgtk-3-dev \
    libdbus-glib-1-dev \
    libnotify-dev \
    libgudev-1.0-dev \
    libfontconfig-dev \
    libfreetype-dev \
    libfribidi-dev \
    libharfbuzz-dev \

# install rust, rustup, cargo-c
log "Installing rust"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
export PATH="/root/.cargo/bin:${PATH}"
cargo install -j$(nproc) cargo-c

log "Installing rust toolchain for Windows"
rustup target add x86_64-pc-windows-gnu

log "Downloading HandBrake sources..."
if echo "${HANDBRAKE_URL}" | grep -q '\.git$'; then
    # Sources from git for nightly builds.
    git clone ${HANDBRAKE_URL} /tmp/handbrake
    # HANDBRAKE_VERSION is in the format "nightly-<date>-<commit hash>".
    git -C /tmp/handbrake checkout "$(echo "${HANDBRAKE_VERSION}" | cut -d'-' -f3)"
else
    mkdir /tmp/handbrake
    curl -# -L -f ${HANDBRAKE_URL} | tar xj --strip 1 -C /tmp/handbrake
fi

#
# Compile HandBrake.
#

if [ "${HANDBRAKE_DEBUG_MODE}" = "none" ]; then
    CMAKE_BUILD_TYPE=Release
else
    CMAKE_BUILD_TYPE=Debug
    # Do not strip symbols.
    LDFLAGS=
fi

log "Patching HandBrake..."
# if xx-info is-cross; then
#     patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/cross-compile-fix.patch
# fi
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/av1_svt180_upgrade.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/enable-svt-av1-avx512.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/opus_upgrade.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/language.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/x264_x265_upgrade.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-Add-subjective-ssim-in-gui-presets.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-Allow-the-use-of-extended-CRF.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-Fix-CRF-greater-63.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-encavcodecaudio-set-opus-mapping_family-option-to-1-.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0001-libhb-refactor-Dolby-Vision-level-selection-code-def.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0001-SVT-AV1-hb-mainline-sync.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0002-libhb-convert-dolby-vision-rpus-to-t35-obu-payloads-.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0003-contrib-fix-a-crash-that-happens-when-multiple-metad.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0005-scan-always-use-UNDEF-for-Dolby-Vision-5-and-10.0-un.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0006-Fix-merge-errors.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0007-h265-Dovi-compile-error.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0008-libhb-refactor-how-extradata-is-stored-use-a-dynamic.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/dolby/0009-Dovi-compile-fix-2.patch
sed -i "0,/Git-Commit-Hash/s//${HB_BUILD}/" "$SCRIPT_DIR"/0001-Add-versioning-through-activity-window.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-Add-versioning-through-activity-window.patch

# # Create the meson cross compile config file.
# if xx-info is-cross; then
#     cat << EOF > /tmp/handbrake/contrib/cross-config.meson
# [binaries]
# pkgconfig = '$(xx-info)-pkg-config'

# [properties]
# sys_root = '$(xx-info sysroot)'
# pkg_config_libdir = '$(xx-info sysroot)/usr/lib/pkgconfig'

# [host_machine]
# system = 'linux'
# cpu_family = '$(xx-info arch)'
# cpu = '$(xx-info arch)'
# endian = 'little'
# EOF
# fi

log "Setup toolchain for windows"
wget https://github.com/bradleysepos/mingw-w64-build/releases/download/10.0.0/mingw-w64-toolchain-10.0.0-msvcrt-linux-x86_64.tar.gz
SHA=$(sha1sum mingw-w64-toolchain-10.0.0-msvcrt-linux-x86_64.tar.gz)
EXPECTED="f7250d140a72bdfdda2d4cd01d84e9a3938132b1  mingw-w64-toolchain-10.0.0-msvcrt-linux-x86_64.tar.gz"
if [ "$SHA" = "$EXPECTED" ];
then
    echo "Toolchain Verified. Extracting ..."
    mkdir /tmp/toolchains/
    tar xzf mingw-w64-toolchain-10.0.0-msvcrt-linux-x86_64.tar.gz --strip-components=1 -C /tmp/toolchains
    log "Toolchains directory"
    ls -alh /tmp/toolchains
else
    echo "Toolchain Verification FAILED. Exiting!"
    return -1
fi

# Set compiler optimizations
export CFLAGS="$CFLAGS -march=$MARCH"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"

export PATH="/tmp/toolchains/mingw-w64-x86_64/bin:${PATH}"

log "Configuring HandBrake..."
(
    CONF_FLAGS="--disable-qsv --disable-nvenc"

    # if xx-info is-cross; then
    #     CONF_FLAGS="$CONF_FLAGS --cross $(xx-info)"
    # fi

    cd /tmp/handbrake && ./configure \
        --cross=x86_64-w64-mingw32 \
        --verbose \
        --prefix=/usr \
        --build=build \
        --debug=$HANDBRAKE_DEBUG_MODE \
        --enable-fdk-aac \
        --enable-x265 \
        --enable-libdovi \
        --no-harden \
        $CONF_FLAGS \
)

log "Compiling HandBrake..."
make -C /tmp/handbrake/build -j$(nproc)

log "Fix permissions..."
chown -R runner /tmp/handbrake/build

# log "Installing HandBrake..."
# make DESTDIR=/tmp/handbrake-install -C /tmp/handbrake/build -j1 install
# make DESTDIR=/tmp/handbrake-install -C /tmp/libva install

# # Remove uneeded installed files.
# rm -rf \
#     /tmp/handbrake-install/usr/include \
#     /tmp/handbrake-install/usr/lib/*.la \
#     /tmp/handbrake-install/usr/lib/libmfx.* \
#     /tmp/handbrake-install/usr/lib/libigfxcmrt.so* \
#     /tmp/handbrake-install/usr/lib/dri/*.la \
#     /tmp/handbrake-install/usr/lib/pkgconfig \
#     /tmp/handbrake-install/usr/share/metainfo \
#     /tmp/handbrake-install/usr/share/applications \

# log "Handbrake install content:"
# find /tmp/handbrake-install
