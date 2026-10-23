# [EXPERIMENTAL] gbOS86 Port & Boot Notes for HP 15s (Intel 12th Gen Alder Lake Core i3-1215U)

**Posted by**: aurtxx  
**Project Repository**: [https://github.com/aurtxx/gbos86-hp-laptop-port](https://github.com/aurtxx/gbos86-hp-laptop-port)

---

Hey everyone in the gbOS community!

I wanted to share technical notes, bootloader configs, and patches from an experimental porting project bringing **gbOS86** to modern Intel 12th Gen Alder Lake laptop hardware (**HP 15s-fr5009TU**).

> [!NOTE]
> **Disclaimer**: This is an independent, community-driven experimental port and troubleshooting guide, **not** an official gbOS release. It is intended for developers, tinkerers, and enthusiasts looking to test Android-x86 desktop systems on 12th/13th Gen Intel hardware.

---

### Hardware Target & Specifications

* **Laptop**: HP 15s-fr5009TU
* **CPU**: 12th Gen Intel Core i3-1215U (6 Cores / 8 Threads, Alder Lake-U)
* **RAM**: 8 GB DDR4
* **Integrated GPU**: Intel Alder Lake-P GT1 [UHD Graphics] (PCI ID `8086:46b3`)
* **Display**: 15.6" 1920x1080 eDP Panel @ 60 Hz (scaled at 180 DPI)
* **Storage**: Booted entirely from a 64 GB USB 3.0 Pendrive (internal SSD kept completely untouched)

---

### What Works

* **Kernel Boot & CPU Handover**: Decoupled unified EFI kernel to `systemd-boot` to bypass Intel CET / Indirect Branch Tracking (IBT) kernel panics (`ibt=off`).
* **Intel Hardware Acceleration**: Native Intel `i915` GPU driver bound with SurfaceFlinger running hardware-accelerated ANGLE over Vulkan at 1080p @ 60 Hz.
* **Input Devices**: Internal keyboard and ELAN I2C touchpad functional with automated IDC low-latency touch response (`Change_Timeout=0.02`).
* **Camera & Media**: HP True Vision 720p HD webcam recognized via UVC; YouTube 1080p video playback verified in Chrome/Brave.
* **KernelSU**: KernelSU v32680 built-in with superuser access.
* **Setup Wizard Bypass**: Automatic provisioning injected on boot (`device_provisioned 1`, `user_setup_complete 1`) to bypass Google's Setup Wizard.
* **Persistent USB Storage**: Dedicated ext4 partitions (`GBOS_DATA` ~52 GB, `GBOS_META` 64 MB) verified on the USB stick with a hardened 14-gate safety verification logic.

---

### What Is Incomplete, Broken, or Suppressed

* **System OTA Updates (Disabled by Design)**: Upstream Google `update_engine` expects a 12.88 GB dynamic A/B super partition, which fails with error `0x713` on linear read-only EROFS USB installations. Automatic OTA is permanently suppressed.
* **Initial Boot Indexing Duration**: First boot on persistent ext4 takes **5 to 7 minutes** while Android indexes ~312 system apps over the shared USB bus bandwidth. (Subsequent reboots take 15–30s).
* **Audio Playback**: Intel SOF audio topology (`sof-hda-dsp`) and PCM maps generate correctly; userspace speaker routing needs verification.
* **USB Tethering / Android Linking**: USB RNDIS internet routing and cross-device linking fail out-of-the-box.
* **ChromeOS EC Logger**: `timberslide` crash-loops looking for `/dev/cros_ec` (non-fatal, can be masked).

---

### Major Technical Hurdles Solved

1. **Alder Lake IBT Kernel Panic**:
   Intel 12th Gen CPUs enforce CET. The stock unified EFI image panics immediately on KernelSU hook trampolines lacking `ENDBR64`. Solved by deploying `systemd-boot` with `options ibt=off drm.panic_screen=kmsg`.
2. **Kernel Module Lookup Mismatch**:
   `uname -r` reported `6.18.21-gbos-whl` while the extracted directory was `6.18.21-gbos-whl+`. Patched `hwdetect.sh` to probe both versions, allowing Intel i915 and SOF audio drivers to load.
3. **Setup Wizard Block on OTA Failure**:
   Added `gbos_provision` to `hook.sh` and masked `update_engine.rc` with an empty file to proceed straight to the desktop.
4. **Hardened USB Persistence**:
   Engineered a 14-gate verification function in `hook.sh` that checks sysfs USB ancestry, GPT PartUUIDs via bundled `sfdisk -d`, and major/minor device numbers to safely mount persistent ext4 partitions without touching internal NVMe drives.

---

### Source Code, Diffs & Reproduction

All patch diffs, bootloader configuration files, BusyBox validation scripts, and comprehensive hardware documentation are available in the public repository:

👉 **GitHub Repository**: [https://github.com/aurtxx/gbos86-hp-laptop-port](https://github.com/aurtxx/gbos86-hp-laptop-port)

Contributions, tests on other Alder Lake / Raptor Lake laptops, and audio routing feedback are very welcome!
