# Chronological Porting History & Changelog

This document provides a forensic, boot-by-boot record of all issues encountered, diagnoses, technical fixes, and verified outcomes on the HP 15s-fr5009TU laptop.

---

## Boot 1: Initial Flash & Immediate Kernel Panic
* **Observed Outcome**: System powered on, HP splash screen displayed, then screen went black with the Caps Lock LED blinking indefinitely. No kernel messages shown on screen.
* **Forensic Diagnosis**:
  - The stock image shipped a unified kernel image (UKI) as `EFI/BOOT/BOOTX64.EFI`.
  - UEFI pstore/dmesg extraction revealed a kernel panic on the first kernel instruction:
    ```text
    Missing ENDBR: ksu_handle_init+0x0/0x10 [kernelsu]
    Kernel panic - not syncing: Fatal exception
    ```
  - **Root Cause**: Intel 12th Gen Alder Lake processors enforce Hardware Indirect Branch Tracking (IBT), a feature of Intel Control-flow Enforcement Technology (CET). The upstream KernelSU trampolines in `6.18.21-gbos-whl` lacked `ENDBR64` landing pad instructions, triggering a CPU-level fault.
* **Resolution**: The kernel command line required `ibt=off`, but the stock unified EFI binary had its command line hardcoded inside the signed binary and could not be edited.

---

## Boots 2 & 3: Bootloader Architecture Redesign
* **Observed Outcome**: Tested passing kernel parameters via UEFI Shell and alternative boot entries.
* **Resolution**:
  - Separated the unified EFI image into a modular bootloader architecture.
  - Renamed the stock kernel binary to `EFI/BOOT/KERNEL.EFI`.
  - Deployed `systemd-boot` (x86_64) as `EFI/BOOT/BOOTX64.EFI`.
  - Created `loader/entries/gbos.conf` passing `options ibt=off drm.panic_screen=kmsg`.

---

## Boot 4: CET Workaround Verification & Driver Fallback
* **Observed Outcome**: Kernel booted cleanly with `ibt=off`! Linux kernel output streamed to the display via earlyprintk. However, the system fell back to software rendering (SwiftShader), and hardware devices (touchpad, Wi-Fi) were non-functional.
* **Forensic Diagnosis**:
  - `hwdetect.sh` failed to mount kernel modules:
    ```text
    hwdetect: gbos/modules/lib/modules/6.18.21-gbos-whl missing, only the initramfs modules are available
    ```
  - `uname -r` reported `6.18.21-gbos-whl`, while the directory on the USB stick was named `6.18.21-gbos-whl+` (with a trailing plus sign).
* **Resolution**: Patched `gbos/hwdetect.sh` to check for both `$KVER` and `${KVER}+`.

---

## Boot 5: Native Intel GPU Acceleration & Setup Wizard Blocker
* **Observed Outcome**:
  - Intel UHD Alder Lake graphics driver (`i915`) bound successfully (`0000:00:02.0`, `8086:46b3`).
  - SurfaceFlinger initialized with full hardware acceleration at 1920x1080 @ 60 Hz.
  - The Android Setup Wizard appeared, but immediately blocked on:
    `"System update failed"` (`com.google.android.gms.update.OtaStatusFragment`).
* **Forensic Diagnosis**:
  - Logcat revealed `update_engine` failing with error `0x713`:
    ```text
    update_engine: Partition super size (3688890368) does not match manifest (12884901888)
    update_engine: Cannot find /dev/block/by-name/boot_a
    ```
  - The system is installed on a linear read-only 3.68 GB EROFS partition, whereas Google's OTA engine expects a dynamic 12.88 GB dual-slot A/B super partition.
  - The modal could not be dismissed via Back, Home, or Escape.

---

## Boots 6 & 7: Provisioning & OTA Suppression Development
* **Observed Outcome**: Investigated runtime and bootloader bypass mechanisms without modifying system partition images.
* **Resolution**:
  - Designed `gbos_provision` service in `gbos/hook.sh` injected into init:
    `settings put global device_provisioned 1`
    `settings put secure user_setup_complete 1`
    `settings put global ota_disable_automatic_update 1`
    `pm disable com.google.android.setupwizard`
    `pm disable com.google.android.gms/.update.SystemUpdateActivity`
    `stop update_engine`
  - Masked `/new/system/etc/init/update_engine.rc` and `update_engine_sideload.rc` by bind mounting `/tmp/empty.rc` during stage 0.

---

## Boot 8: Successful Desktop Launch (Live Session Milestone)
* **Observed Outcome**:
  - System booted straight past the Setup Wizard and launched directly into the Android desktop!
  - User accessed Google Play Services, Chrome/Brave, YouTube, Google Photos, and Gemini for over 35 minutes.
  - Camera, touchpad, keyboard, display scaling, and Intel GPU acceleration worked smoothly.
* **Limitation Identified**:
  - `/data` and `/metadata` were backed by `tmpfs` (RAM). All accounts, downloaded files, and app settings disappeared upon power off.

---

## Boot 9: Persistent USB Storage Implementation & Forensic Post-Mortem
* **Target Objective**: Transform the live USB stick into a fully installed, persistent operating system using unallocated space on the 64 GB flash drive.
* **Implementation**:
  - Created Partition 3 (`GBOS_META`, 64 MiB ext4) and Partition 4 (`GBOS_DATA`, 52.67 GiB ext4).
  - Engineered a hardened 14-gate `verify_persistent_usb()` in `gbos/hook.sh` enforcing USB ancestry validation, GPT PartUUID matching via bundled `sfdisk -d`, path canonicalization, major/minor device ID matching, and strict internal SSD exclusion (`nvme*|mmcblk*`).
  - Tested syntax and test fixtures against extracted stage-0 BusyBox v1.37.0.
* **Boot Outcome**:
  - Stage 0 successfully verified the USB drive, passed all 14 gates, and mounted `/dev/sda4` on `/new/data` (51.5 GB free) and `/dev/sda3` on `/new/metadata`.
  - Android began its initial `setFirstBoot` package scan on the empty ext4 partition, writing **1.21 GB (295,866 blocks)** to `/data`.
  - At 17:11:54, the user interrupted the boot under the impression the system was in a loop.
* **Forensic Diagnosis**:
  - The system was **not** in a boot loop. Package scanning was ~38% complete (120 of 312 packages).
  - SELinux was confirmed in Permissive mode (`permissive=1`), meaning zero actions were blocked.
  - The only crashing process was `timberslide` (ChromeOS EC logger failing on missing `/dev/cros_ec`).
  - Verified that `/data` remains safe and consistent to resume on Boot-10.
