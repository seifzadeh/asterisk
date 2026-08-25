#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/var/lib/asterisk-dev-vm"
CCACHE_DIR="${CCACHE_DIR:-/var/cache/asterisk-dev-ccache}"
JOBS="${BUILD_JOBS:-$(nproc)}"
DEPS_MARKER="${STATE_DIR}/debian13-deps-v2"

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: build.sh must run as root."
    exit 1
fi

if [[ ! -f configure.ac || ! -f Makefile.rules ]]; then
    echo "ERROR: run this script from the root of the Asterisk source tree."
    exit 1
fi

mkdir -p "${STATE_DIR}" "${CCACHE_DIR}"

if [[ ! -f "${DEPS_MARKER}" ]]; then
    echo "==> Installing Debian 13 build dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates ccache git pkg-config \
        autoconf automake libtool
    contrib/scripts/install_prereq install
    touch "${DEPS_MARKER}"
fi

export CCACHE_DIR
export CC="ccache gcc"
ccache --max-size="${CCACHE_MAX_SIZE:-10G}"

if [[ "${CLEAN_BUILD:-0}" == "1" ]]; then
    echo "==> Removing previous build output"
    make distclean 2>/dev/null || true
fi

if [[ ! -x ./configure ]]; then
    echo "==> Generating configure script"
    ./bootstrap.sh
fi

echo "==> Configuring Asterisk with default system paths"
./configure

echo "==> Preparing menuselect"
make menuselect.makeopts

echo "==> Compiling Asterisk with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Stopping the currently installed Asterisk"
systemctl stop asterisk || true

echo "==> Force-killing any remaining Asterisk processes"
pkill -9 -x asterisk 2>/dev/null || true

for attempt in 1 2 3 4 5; do
    if ! pgrep -x asterisk >/dev/null; then
        break
    fi
    sleep 1
    pkill -9 -x asterisk 2>/dev/null || true
done

if pgrep -x asterisk >/dev/null; then
    echo "ERROR: an Asterisk process is still running."
    pgrep -a -x asterisk || true
    exit 1
fi

echo "==> Uninstalling previous Asterisk binaries and modules"
make uninstall

echo "==> Installing the new build into the operating system"
make install
ldconfig

git rev-parse HEAD > /usr/lib/asterisk/BUILD_COMMIT
date --iso-8601=seconds > /usr/lib/asterisk/BUILD_TIME

echo "==> Restarting Asterisk"
systemctl restart asterisk
systemctl --no-pager --full status asterisk

echo "==> Installed version"
/usr/sbin/asterisk -V

echo "==> Build and deployment completed"
echo "Commit: $(cat /usr/lib/asterisk/BUILD_COMMIT)"
echo "Configuration preserved at: /etc/asterisk"
echo
ccache --show-stats
