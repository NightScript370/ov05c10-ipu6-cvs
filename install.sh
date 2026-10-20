#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Sets up the OV05C10 camera behind an Intel CVS chip on IPU6 laptops:
#   1. build dependencies (apt)
#   2. libcamera with the software ISP, built from source into /opt/libcamera
#   3. dma-buf access for the desktop user (udev rule)
#   4. intel_cvs + patched ov05c10 kernel modules via DKMS
#   5. v4l2-relayd: an on-demand "Integrated Camera" virtual webcam for all apps
#
# Run as your normal user; it asks for sudo when needed.
# Undo with: sudo /usr/local/share/ov05c10-ipu6-cvs/uninstall.sh
set -eu

LIBCAMERA_VERSION=v0.7.2
LIBCAMERA_URL=https://git.libcamera.org/libcamera/libcamera.git
PREFIX=/opt/libcamera
SHARE=/usr/local/share/ov05c10-ipu6-cvs
here="$(cd "$(dirname "$0")" && pwd)"
kver="$(uname -r)"

if [ "$(id -u)" -eq 0 ]; then
	echo "Run this as your normal user, not root (it uses sudo itself)." >&2
	exit 1
fi
if [ ! -d "/lib/modules/$kver/build" ]; then
	echo "Kernel headers for $kver are missing (install linux-headers-$kver)." >&2
	exit 1
fi

cat <<EOF
This installs out-of-tree kernel modules (intel_cvs, ov05c10), builds libcamera
$LIBCAMERA_VERSION into $PREFIX and sets up the v4l2-relayd virtual webcam.

If a later boot ever hangs, add  module_blacklist=intel_cvs,ov05c10  to the
kernel command line from the GRUB menu (press 'e'), then run the uninstaller.

EOF
printf 'Continue? [y/N] '
read -r answer
case "$answer" in [yY]*) ;; *) echo "Cancelled."; exit 0 ;; esac

echo "== 1/5 Installing build dependencies"
sudo apt-get install -y git meson ninja-build pkg-config cmake python3-yaml python3-ply python3-jinja2 \
	libyaml-dev libgnutls28-dev libudev-dev libevent-dev libdw-dev libunwind-dev libtiff-dev \
	libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libegl-dev libgles-dev \
	gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
	v4l-utils v4l2loopback-utils dkms build-essential

echo "== 2/5 Building libcamera $LIBCAMERA_VERSION"
src="$here/build/libcamera"
if [ ! -d "$src/.git" ]; then
	git clone --depth 1 --branch "$LIBCAMERA_VERSION" "$LIBCAMERA_URL" "$src"
fi
if [ ! -f "$src/build/build.ninja" ]; then
	meson setup "$src/build" "$src" --prefix="$PREFIX" --buildtype=release \
		-Dpipelines=simple -Dipas=simple -Dgstreamer=enabled -Dv4l2=enabled \
		-Dcam=enabled -Dqcam=disabled -Dlc-compliance=disabled -Dtest=false \
		-Ddocumentation=disabled -Dpycamera=disabled
fi
ninja -C "$src/build"

sudo sh -s "$here" "$src" "$kver" "$SHARE" <<'ROOT'
set -eu
here="$1"; src="$2"; kver="$3"; share="$4"

echo "== 3/5 Installing libcamera and dma-buf access"
ninja -C "$src/build" install >/dev/null
install -m 644 "$here/config/libcamera-opt.conf" /etc/ld.so.conf.d/libcamera-opt.conf
ldconfig
install -m 644 "$here/config/ov05c10.yaml" /opt/libcamera/share/libcamera/ipa/simple/ov05c10.yaml
install -m 644 "$here/config/70-dma-heap-uaccess.rules" /etc/udev/rules.d/70-dma-heap-uaccess.rules
udevadm control --reload
udevadm trigger --action=change --subsystem-match=dma_heap --subsystem-match=misc || true

echo "== 4/5 Installing kernel modules with DKMS"
rm -rf /usr/src/vision-driver-1.0.0
mkdir -p /usr/src/vision-driver-1.0.0
cp -r "$here/drivers/intel-cvs/Makefile" "$here/drivers/intel-cvs/dkms.conf" \
	"$here/drivers/intel-cvs/drivers" "$here/drivers/intel-cvs/include" /usr/src/vision-driver-1.0.0/
dkms remove vision-driver/1.0.0 --all >/dev/null 2>&1 || true
dkms install vision-driver/1.0.0 -k "$kver"

rm -rf /usr/src/ov05c10-ipu6-1.0
mkdir -p /usr/src/ov05c10-ipu6-1.0
cp "$here/drivers/ov05c10/ov05c10.c" "$here/drivers/ov05c10/Makefile" "$here/drivers/ov05c10/dkms.conf" \
	/usr/src/ov05c10-ipu6-1.0/
dkms remove ov05c10-ipu6/1.0 --all >/dev/null 2>&1 || true
dkms install ov05c10-ipu6/1.0 -k "$kver"

echo "== 5/5 Setting up the virtual webcam (v4l2-relayd)"
apt-get install -y v4l2-relayd >/dev/null
install -m 644 "$here/config/v4l2-relayd" /etc/v4l2-relayd
install -m 644 "$here/config/zz-ov05c10-camera.conf" /etc/modprobe.d/zz-ov05c10-camera.conf
install -d /etc/systemd/system/v4l2-relayd.service.d
install -m 644 "$here/config/v4l2-relayd.service.d/"*.conf /etc/systemd/system/v4l2-relayd.service.d/

install -d "$share"
install -m 755 "$here/uninstall.sh" "$share/uninstall.sh"

systemctl stop v4l2-relayd 2>/dev/null || true
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback
systemctl daemon-reload
systemctl enable v4l2-relayd
systemctl restart v4l2-relayd
ROOT

cat <<EOF

Done. Reboot so the camera modules load at startup; apps will then see a
webcam called "Integrated Camera".
Uninstall: sudo $SHARE/uninstall.sh
EOF
