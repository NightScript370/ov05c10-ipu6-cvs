# OV05C10 webcam on Intel IPU6 laptops with a CVS chip

Gets the built-in OmniVision OV05C10 camera working on mainline/Ubuntu kernels for
Intel Arrow Lake (and likely Meteor Lake) laptops where the sensor is wired through
an Intel CVS ("Computer Vision Sensing") chip. No proprietary Intel camera HAL and no
OEM kernel needed. Apps see an ordinary webcam called **Integrated Camera**.

## Does this apply to my laptop?

Check for these ACPI devices:

```bash
ls /sys/bus/acpi/devices/ | grep -E 'OVTI05C1|INTC10E0'
```

You need both:
- `OVTI05C1`: the OV05C10 sensor.
- `INTC10E0`: the Intel CVS chip on Arrow Lake. MTL (`INTC10CF`) and LNL (`INTC10DE`) variants are also matched by the CVS driver, but untested here.

Typical symptoms without this fix:
- `dmesg` shows `intel-ipu6 ... Found supported sensor OVTI05C1:00`.
- No `i2c-OVTI05C1:00` device ever appears.
- All `/dev/video*` nodes give no picture.

**Tested on:** Dell Pro 14 Plus (PB14250), Core Ultra 5 235U, IPU6 `8086:7d19`, Ubuntu 24.04-based distro (Linux Mint 22.3), kernel 7.0 (Ubuntu HWE), Secure Boot disabled.

## Why the camera doesn't work out of the box

1. **The sensor waits on the CVS chip.** The firmware's camera entry lists the CVS device (`INTC10E0`) in its ACPI `_DEP` dependencies. No mainline driver binds that device, so the kernel never creates the sensor's I2C device. Even a sensor driver would have nothing to attach to. Intel's out-of-tree [`intel_cvs`](https://github.com/intel/vision-drivers) driver hands the sensor over to the IPU and clears the dependency.
2. **No mainline OV05C10 driver with ACPI support.** Intel's driver from [`ipu6-drivers`](https://github.com/intel/ipu6-drivers) works. Its 2888x1808 @ 900 MHz mode never produced frames on the tested machine, so this repo patches it to expose only the 2800x1576 @ 480 MHz mode (see `patches/`).
3. **The IPU6 delivers raw Bayer data.** libcamera's software ISP turns it into a normal image. Ubuntu 24.04's libcamera is too old, so the installer builds v0.7.2 into `/opt/libcamera`, with GPU-accelerated debayering. It also adds a udev rule so the desktop user can allocate the dma-buf memory the ISP needs.
4. **Most apps don't speak libcamera.** `v4l2-relayd` feeds libcamera into a `v4l2loopback` device called "Integrated Camera". It only starts the camera while an app has it open. The config also sets `v4l2sink sync=false`: the camera runs at ~26 fps while the relay stamps 30 fps, and without this the output falls to ~1 fps after a few seconds.

## Install

```bash
./install.sh
```

Then reboot. The kernel headers for your running kernel must be installed. The script:
- uses DKMS, so the modules are rebuilt automatically on kernel updates;
- with Secure Boot on, needs a DKMS signing key enrolled with MOK (DKMS on Ubuntu signs modules with it automatically).

The installer builds libcamera under `./build/`.

## Uninstall

```bash
sudo /usr/local/share/ov05c10-ipu6-cvs/uninstall.sh
```

## If a boot hangs

At the GRUB menu press `e`, append `module_blacklist=intel_cvs,ov05c10` to the line that starts with `linux`, and boot with Ctrl+X. Then run the uninstaller.

## Picture settings

`config/ov05c10.yaml` is a libcamera tuning file. It sets:
- the measured black level;
- a **generic, uncalibrated** color matrix that makes colors much less washed out than libcamera's default.

Saturation, contrast and gamma are set in `/etc/v4l2-relayd` (`VIDEOSRC=` line). After editing that line, restart the service:

```bash
sudo systemctl restart v4l2-relayd
```

The companion **Camera Settings** app provides sliders with a live preview for these.

## Known limitations

- **Output resolution:** 1280x720 at ~26 fps, scaled from the 2800x1576 sensor mode.
- **Image quality:** colors and low-light performance are below Windows. There is no calibrated tuning for this sensor.
- **Boot warning:** `intel_cvs` logs a `WARNING` from `__setup_irq` at probe on kernel 7.0. It has had no visible effect.
- **Single user:** only one program can use the real camera at a time. While another libcamera app holds it, "Integrated Camera" cannot start.
- **Not upstream:** these are out-of-tree modules, so the kernel is marked tainted.

## Contents

| Path | What it is |
| --- | --- |
| `drivers/intel-cvs/` | Intel vision-drivers (`intel_cvs`), unmodified, commit `845d6f8bdf66ff1f455901da9de5e00a53a83dce` |
| `drivers/ov05c10/` | Intel's `ov05c10.c` from ipu6-drivers commit `71bddb5158fb7f0bd244ad7aa6b2efab024531a7`, with the patch applied |
| `patches/` | The change to `ov05c10.c` as a patch |
| `config/` | libcamera tuning, udev rule, v4l2-relayd config and systemd overrides |
| `install.sh`, `uninstall.sh` | Setup and removal |

## License

- The kernel drivers are GPL-2.0 (Intel Corporation). See `LICENSE` and `drivers/intel-cvs/LICENSE.txt`.
- The scripts and configuration in this repository are also GPL-2.0-only.
- `config/ov05c10.yaml` is CC0-1.0.
- libcamera is downloaded and built at install time, under its own licenses.
