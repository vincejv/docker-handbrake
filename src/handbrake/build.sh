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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
    echo ">>> $*"
}

HANDBRAKE_VERSION="${1:-}"
HANDBRAKE_URL="${2:-}"
HANDBRAKE_DEBUG_MODE="${3:-}"
MARCH="${4:-}"
HB_BUILD="${5:-}"
X264_URL="https://github.com/HandBrake/HandBrake-contribs/releases/download/contribs/x264-snapshot-20240314-3186.tar.gz"
LIBVA_URL="${6:-}"
INTEL_VAAPI_DRIVER_URL="${7:-}"
GMMLIB_URL="${8:-}"
INTEL_MEDIA_DRIVER_URL="${9:-}"
INTEL_MEDIA_SDK_URL="${10:-}"
INTEL_ONEVPL_GPU_RUNTIME_URL="${11:-}"

#
# Compiler optimizations for toolchain build
#
export CFLAGS="-O3 -pipe -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-O3 -Wl,--strip-all -Wl,--as-needed"

export CC=clang-18
export CXX=clang++-18

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

if [ -z "$X264_URL" ]; then
   log "ERROR: x264 URL missing."
   exit 1
fi

if [ -z "$LIBVA_URL" ]; then
    log "ERROR: libva URL missing."
    exit 1
fi

if [ -z "$INTEL_VAAPI_DRIVER_URL" ]; then
    log "ERROR: Intel VAAPI driver URL missing."
    exit 1
fi

if [ -z "$GMMLIB_URL" ]; then
    log "ERROR: gmmlib URL missing."
    exit 1
fi

if [ -z "$INTEL_MEDIA_DRIVER_URL" ]; then
    log "ERROR: Intel Media driver URL missing."
    exit 1
fi

if [ -z "$INTEL_MEDIA_SDK_URL" ]; then
    log "ERROR: Intel Media SDK URL missing."
    exit 1
fi

if [ -z "$INTEL_ONEVPL_GPU_RUNTIME_URL" ]; then
    log "ERROR: Intel OneVPL GPU Runtime URL missing."
    exit 1
fi

#
# Install required packages.
#
apt-get update && \
apt-get install -y \
    curl \
    wget \
    lsb-release \
    software-properties-common \
    gnupg \
    binutils \
    git \
    make \
    cmake \
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
    xz-utils \

apt-get install -y \
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
    libdrm-dev \

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
    libgtk-4-dev \
    libdbus-glib-1-dev \
    libnotify-dev \
    libgudev-1.0-dev \
    libfontconfig-dev \
    libfreetype-dev \
    libfribidi-dev \
    libharfbuzz-dev \
    libx11-xcb-dev \
    libxcb-dri3-dev \

# download install clang and llvm
log "Installing clang and llvm"
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
./llvm.sh 18

# install rust, rustup, cargo-c
log "Installing rust"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
export PATH="/root/.cargo/bin:${PATH}"
cargo install -j$(nproc) cargo-c

#
# Download sources.
#

log "Downloading x264 sources..."
mkdir /tmp/x264
curl -# -L -f ${X264_URL} | tar xz --strip 1 -C /tmp/x264

log "Downloading libva sources..."
mkdir /tmp/libva
curl -# -L -f ${LIBVA_URL} | tar xj --strip 1 -C /tmp/libva

log "Downloading Intel VAAPI driver sources..."
mkdir /tmp/intel-vaapi-driver
curl -# -L -f ${INTEL_VAAPI_DRIVER_URL} | tar xj --strip 1 -C /tmp/intel-vaapi-driver

log "Downloading gmmlib sources..."
mkdir /tmp/gmmlib
curl -# -L -f ${GMMLIB_URL} | tar xz --strip 1 -C /tmp/gmmlib

log "Downloading Intel Media driver sources..."
mkdir /tmp/intel-media-driver
curl -# -L -f ${INTEL_MEDIA_DRIVER_URL} | tar xz --strip 1 -C /tmp/intel-media-driver

log "Downloading Intel Media SDK sources..."
mkdir /tmp/MediaSDK
curl -# -L -f ${INTEL_MEDIA_SDK_URL} | tar xz --strip 1 -C /tmp/MediaSDK

log "Downloading Intel OneVPL GPU Runtime sources..."
mkdir /tmp/oneVPL-intel-gpu
curl -# -L -f ${INTEL_ONEVPL_GPU_RUNTIME_URL} | tar xz --strip 1 -C /tmp/oneVPL-intel-gpu

log "Downloading opus sources..."
mkdir /tmp/opus
curl -# -L -f https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz | tar xz --strip 1 -C /tmp/opus

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

#
# Set compiler optimization on build
#
export CFLAGS="$CFLAGS -march=$MARCH -fno-stack-protector -U_FORTIFY_SOURCE -flto"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"

log "Configuring opus..."
cd /tmp/opus && ./configure --verbose --disable-hardening 

log "Compiling opus..."
make -C /tmp/opus -j$(nproc)

log "Installing opus..."
make -C /tmp/opus install

log "Configuring x264..."
if [ "${HANDBRAKE_DEBUG_MODE}" = "none" ]; then
   X264_CMAKE_OPTS=--enable-strip
else
   X264_CMAKE_OPTS=--enable-debug
fi
(
   cd /tmp/x264 && ./configure \
       --prefix=/usr \
       --enable-shared \
       --disable-static \
       --enable-pic \
       --disable-cli \
       --enable-lto  \
       --enable-strip \
       $X264_CMAKE_OPTS \
)

log "Compiling x264..."
make -C /tmp/x264 -j$(nproc)

log "Installing x264..."
make -C /tmp/x264 install

log "Configuring libva..."
(
    cd /tmp/libva && ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --enable-x11 \
        --disable-glx \
        --disable-wayland \
        --disable-static \
        --enable-shared \
)

log "Compiling libva..."
make -C /tmp/libva -j$(nproc)

log "Installing libva..."
make -C /tmp/libva install
make DESTDIR=/tmp/handbrake-install -C /tmp/libva install

log "Configuring Intel VAAPI driver..."
(
    cd /tmp/intel-vaapi-driver && ./configure
)

log "Compiling Intel VAAPI driver..."
make -C /tmp/intel-vaapi-driver -j$(nproc)

log "Installing Intel VAAPI driver..."
make DESTDIR=/tmp/handbrake-install -C /tmp/intel-vaapi-driver install

log "Patching Intel Media Driver..."
patch -d /tmp/intel-media-driver -p1 < "$SCRIPT_DIR"/intel-media-driver-compile-fix.patch
rm -rf /tmp/intel-media-driver/media_driver/*/ult

log "Configuring Intel Media driver..."
(
    mkdir /tmp/intel-media-driver/build && \
    cd /tmp/intel-media-driver/build && cmake \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -Wno-dev \
        -DBUILD_TYPE=Release \
        -DINSTALL_DRIVER_SYSCONF=OFF \
        -DMEDIA_RUN_TEST_SUITE=OFF \
        -DSKIP_GMM_CHECK=ON \
        ../
)

log "Compiling Intel Media driver..."
make -C /tmp/intel-media-driver/build  -j$(nproc)

log "Installing Intel Media driver..."
make DESTDIR=/tmp/handbrake-install -C /tmp/intel-media-driver/build install

if [ "${HANDBRAKE_DEBUG_MODE}" = "none" ]; then
    INTEL_MEDIA_SDK_BUILD_TYPE=RELEASE
else \
    INTEL_MEDIA_SDK_BUILD_TYPE=DEBUG
fi

log "Patching Intel Media SDK..."
patch -d /tmp/MediaSDK -p1 < "$SCRIPT_DIR"/intel-media-sdk-debug-no-assert.patch
patch -d /tmp/MediaSDK -p1 < "$SCRIPT_DIR"/intel-media-sdk-compile-fix.patch

log "Configuring Intel Media SDK..."
(
    mkdir /tmp/MediaSDK/build && \
    cd /tmp/MediaSDK/build && cmake \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=$INTEL_MEDIA_SDK_BUILD_TYPE \
        -DENABLE_OPENCL=OFF \
        -DENABLE_X11_DRI3=OFF \
        -DENABLE_WAYLAND=OFF \
        -DBUILD_DISPATCHER=ON \
        -DENABLE_ITT=OFF \
        -DENABLE_TEXTLOG=OFF \
        -DENABLE_STAT=OFF \
        -DBUILD_SAMPLES=OFF \
        ../
)

log "Compiling Intel Media SDK..."
make -C /tmp/MediaSDK/build -j$(nproc)

log "Installing Intel Media SDK..."
make DESTDIR=/tmp/handbrake-install -C /tmp/MediaSDK/build install

log "Configuring Intel oneVPL GPU Runtime..."
(
    mkdir /tmp/oneVPL-intel-gpu/build && \
    cd /tmp/oneVPL-intel-gpu/build && cmake \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        ../
)

log "Compiling Intel oneVPL GPU Runtime..."
make -C /tmp/oneVPL-intel-gpu/build -j$(nproc)

log "Installing Intel oneVPL GPU Runtime..."
make DESTDIR=/tmp/handbrake-install -C /tmp/oneVPL-intel-gpu/build install

log "Patching HandBrake..."
# if xx-info is-cross; then
#     patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/cross-compile-fix.patch
# fi
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/maximized-window.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/svt-av1-psy.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0002-SVT-AV1-version-string-modification.patch
sed -i "0,/Git-Commit-Hash/s//${HB_BUILD}/" "$SCRIPT_DIR"/0001-Add-versioning-through-activity-window.patch
patch -d /tmp/handbrake -p1 < "$SCRIPT_DIR"/0001-Add-versioning-through-activity-window.patch

# Create the meson cross compile config file.
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

log "Configuring HandBrake..."
(
    CONF_FLAGS="--enable-qsv"

    # if xx-info is-cross; then
    #     CONF_FLAGS="$CONF_FLAGS --cross $(xx-info)"
    # fi

    cd /tmp/handbrake && ./configure \
        --verbose \
        --prefix=/usr \
        --build=build \
        --debug=$HANDBRAKE_DEBUG_MODE \
        --enable-fdk-aac \
        --enable-x265 \
        --enable-libdovi \
        --no-harden \
        --lto=on \
        $CONF_FLAGS \
)

log "Compiling HandBrake..."
make -C /tmp/handbrake/build -j$(nproc)

log "Installing HandBrake..."
make DESTDIR=/tmp/handbrake-install -C /tmp/handbrake/build -j1 install
make DESTDIR=/tmp/handbrake-install -C /tmp/libva install

# Remove uneeded installed files.
rm -rf \
    /tmp/handbrake-install/usr/include \
    /tmp/handbrake-install/usr/lib/*.la \
    /tmp/handbrake-install/usr/lib/libmfx.* \
    /tmp/handbrake-install/usr/lib/libigfxcmrt.so* \
    /tmp/handbrake-install/usr/lib/dri/*.la \
    /tmp/handbrake-install/usr/lib/pkgconfig \
    /tmp/handbrake-install/usr/share/metainfo \
    /tmp/handbrake-install/usr/share/applications \

log "Handbrake install content:"
find /tmp/handbrake-install
