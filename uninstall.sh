#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Removes everything install.sh set up. Run with sudo, then reboot.
if [ "$(id -u)" -ne 0 ]; then
	echo "Run with sudo." >&2
	exit 1
fi
systemctl disable --now v4l2-relayd 2>/dev/null
apt-get remove -y v4l2-relayd
rm -rf /etc/v4l2-relayd /etc/modprobe.d/zz-ov05c10-camera.conf /etc/systemd/system/v4l2-relayd.service.d
dkms remove ov05c10-ipu6/1.0 --all
rm -rf /usr/src/ov05c10-ipu6-1.0
dkms remove vision-driver/1.0.0 --all
rm -rf /usr/src/vision-driver-1.0.0
rm -f /etc/udev/rules.d/70-dma-heap-uaccess.rules /etc/ld.so.conf.d/libcamera-opt.conf
rm -rf /opt/libcamera
ldconfig
systemctl daemon-reload
rm -rf /usr/local/share/ov05c10-ipu6-cvs
echo "Camera setup removed. Reboot to finish."
