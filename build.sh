#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="${ASTERISK_DEV_PREFIX:-/opt/asterisk-dev}"
STATE_DIR="/var/lib/asterisk-dev-vm"
CCACHE_DIR="${CCACHE_DIR:-/var/cache/asterisk-dev-ccache}"
JOBS="${BUILD_JOBS:-$(nproc)}"
DEPS_MARKER="${STATE_DIR}/debian13-deps-v1"

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: build.sh must run as root."
    exit 1
fi

if [[ ! -f configure.ac || ! -f Makefile.rules ]]; then
    echo "ERROR: run this script from the root of the Asterisk source tree."
    exit 1
fi

mkdir -p "${STATE_DIR}" "${CCACHE_DIR}" "${PREFIX}"

if [[ ! -f "${DEPS_MARKER}" ]]; then
    echo "==> Installing Debian 13 build dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends         build-essential ca-certificates ccache git pkg-config         autoconf automake libtool
    contrib/scripts/install_prereq install
    touch "${DEPS_MARKER}"
fi

export CCACHE_DIR
ccache --max-size="${CCACHE_MAX_SIZE:-10G}"

if [[ "${CLEAN_BUILD:-0}" == "1" ]]; then
    echo "==> Removing previous build output"
    make distclean 2>/dev/null || true
fi

if [[ ! -x ./configure ]]; then
    echo "==> Generating configure script"
    ./bootstrap.sh
fi

echo "==> Configuring Asterisk"
CC="ccache gcc" ./configure     --prefix="${PREFIX}"     --sysconfdir="${PREFIX}/etc"     --localstatedir="${PREFIX}/var"     --with-pjproject-bundled     --with-jansson-bundled

echo "==> Preparing menuselect"
make menuselect.makeopts

echo "==> Building Asterisk with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Installing development build into ${PREFIX}"
make install

if [[ ! -f "${PREFIX}/etc/asterisk/asterisk.conf" ]]; then
    echo "==> Installing sample configuration (first build only)"
    make samples
fi

git rev-parse HEAD > "${PREFIX}/BUILD_COMMIT"
date --iso-8601=seconds > "${PREFIX}/BUILD_TIME"

echo "==> Build completed"
"${PREFIX}/sbin/asterisk" -V
echo "Commit: $(cat "${PREFIX}/BUILD_COMMIT")"
echo "Install path: ${PREFIX}"
echo
echo "To start it manually:"
echo "  ${PREFIX}/sbin/asterisk -C ${PREFIX}/etc/asterisk/asterisk.conf -cvvvvv"
echo
ccache --show-stats
