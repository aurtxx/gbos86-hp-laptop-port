---
name: gbos86-alderlake-dualboot
description: Dual-boot, reverse engineer, and configure Googlebook OS (gbOS86 / Android-x86) alongside Windows 11 on Intel 12th/13th Gen Alder Lake laptops (e.g. HP 15s-fr5009TU), resolving 0xc000007b UEFI boot issues, SOF audio, Realtek ALC236, Bluetooth, and automated persistent NVMe ext4 storage.
metadata:
  author: aurtxx
  version: "1.0.0"
  target_laptop: "HP 15s-fr5009TU (Intel Core i3-1215U Alder Lake)"
---

# gbOS86 Alder Lake Dual-Boot & REA Guide

This skill provides complete reverse-engineering findings, deployment recipes, bootloader troubleshooting, and driver configurations for running **Googlebook OS (gbOS86 / Android-x86)** on standard Intel 12th/13th Gen (Alder Lake) laptops alongside Windows 11.

---

## 1. Core Architecture & Reverse Engineering Insights

### A. The 0xc000007b Windows Boot Manager Trap
When users try adding gbOS86 to the standard Windows Boot Manager using `bcdedit` (`/application bootapp` or `/application osloader` pointing to `\EFI\BOOT\BOOTX64.EFI`), Windows Boot Manager (`bootmgfw.efi`) crashes with:
```
Status: 0xc000007b (STATUS_INVALID_IMAGE_FORMAT)
File: \EFI\BOOT\BOOTX64.EFI
```
* **Root Cause**: `bootmgfw.efi` strictly validates the PE subsystem of binaries it launches. Microsoft Windows Boot Applications use PE Subsystem `16` (`IMAGE_SUBSYSTEM_WINDOWS_BOOT_APPLICATION`) and Microsoft certificates. Third-party UEFI loaders (systemd-boot, GRUB, Linux EFI stub) use standard PE Subsystem `10` (`IMAGE_SUBSYSTEM_EFI_APPLICATION`). When `bootmgfw.efi` validates the PE header and sees Subsystem `10`, it throws `STATUS_INVALID_IMAGE_FORMAT`.
* **Fix**: **Do not chainload third-party EFI loaders from BCD**. Boot via native UEFI firmware:
  1. Use the laptop's UEFI boot device menu (**F9** on HP laptops, **F12** on Dell/Lenovo).
  2. Select **"Boot From EFI File"** ➔ `GBOSSYS` (Drive `E:`) ➔ `EFI/BOOT/BOOTX64.EFI`.
  3. Alternatively, register a native NVRAM firmware entry (`{fwbootmgr}`) using EasyUEFI or motherboard BIOS options.

### B. Linux Kernel Filesystem Compatibility
* Binary analysis of `KERNEL.EFI` (`6.18.21-gbos-whl`) proves the kernel has **zero NTFS support** (supports `ext4`, `erofs`, and `vfat`).
* **System Partition (`GBOSSYS`)**: Must be formatted as **FAT32**.
* **Persistent Data Partition (`GBOS_DATA`)**: Requires **`ext4` with fs-verity** (`-O verity -m 0`). Without `verity`, Android runtime and Google Play Store fail app installations with `INSTALL_FAILED_BAD_SIGNATURE`.

---

## 2. Partition Architecture on Internal NVMe Disk

| Partition # | Typical Letter | File System | Label | Role |
| :---: | :---: | :---: | :---: | :--- |
| **Partition 1** | *(Hidden)* | FAT32 (100 MB) | `ESP` | Windows UEFI Bootloader (`bootmgfw.efi`) |
| **Partition 3** | **C:** | NTFS (400+ GB) | `Windows` | Windows 11 OS (**Strictly preserved, never touched**) |
| **Partition 4** | **E:** | FAT32 (7.32 GB) | `GBOSSYS` | gbOS86 System Payload (`super.img`, `\EFI\BOOT\`) |
| **Partition 5** | **F:** | ext4 (24.9 GB) | `GBOS_DATA` | Persistent Android User Data (`/data`) |

---

## 3. Hardware Peripheral Verification Matrix (HP 15s-fr5009TU)

| Subsystem | Hardware Spec | Driver / Firmware | Status | Configuration Notes |
| :--- | :--- | :--- | :---: | :--- |
| **CPU Handover** | Intel i3-1215U (6C/8T) | Linux 6.18.21 | **Working** | Requires `ibt=off` in `gbos.conf` (KernelSU lacks CET ENDBR64). |
| **GPU / Video** | Intel Alder Lake-P GT1 | `i915` (KMS) | **Working** | SurfaceFlinger HW acceleration; `DENSITY=180` in `gbos.cfg`. |
| **Audio DSP** | Intel Alder Lake SOF | `snd_sof_pci_intel_tgl` | **Working** | Firmware `intel/sof/sof-adl.ri`, topology `sof-hda-generic-2ch.tplg`. |
| **Audio Codec** | Realtek ALC236 | `snd_hda_codec_alc269` | **Working** | Fixup matched for SSID `103c:8a20`. Headphone jack (`0x21`) and Mic (`0x19`). |
| **Bluetooth** | Realtek RTL8822CU | `btusb` + `btrtl` | **Working** | Firmware `rtl_bt/rtl8822cu_fw.bin`. Android Bluetooth stack fully operational. |
| **Touchpad** | ELAN0718:00 I2C | `i2c_hid` (`04f3:30fd`) | **Working** | Custom IDC file (`Change_Timeout=0.02`) auto-generated in `hook.sh`. |
| **Wi-Fi** | Realtek / MediaTek | `rtw88` / `mt7921` | **Working** | `wlan0` detected and unblocked via `rfkill`. |

---

## 4. Automated NVMe Persistence Recipe (`hook.sh`)

In stock gbOS86, `hook.sh` contains a strict USB-only ancestry check that aborts on internal NVMe disks and forces `tmpfs` (live mode). To enable permanent NVMe dual-boot persistence:

1. **Deploy Metadata Image on `GBOSSYS` (`E:\`)**:
   Create a 64 MB ext4 file `metadata.img` to provide `/metadata` without repartitioning:
   ```bash
   dd if=/dev/zero of=/mnt/e/gbos/metadata.img bs=1M count=64
   mke2fs -F -q -t ext4 -L GBOS_META /mnt/e/gbos/metadata.img
   ```

2. **Update `verify_persistent_storage()` in `hook.sh`**:
   ```bash
   verify_persistent_storage() {
     [ -z "$DEV" ] && return 1

     # Attach metadata container
     if [ -f "$G/metadata.img" ]; then
       losetup /dev/loop7 "$G/metadata.img" 2>/dev/null
       P3_CANON="/dev/loop7"
     fi

     # Detect or initialize GBOS_DATA partition
     DATA_NODE=$(findfs LABEL=GBOS_DATA 2>/dev/null)
     if [ -z "$DATA_NODE" ] && [ -b "/dev/nvme0n1p5" ]; then
       SZ=$(cat /sys/class/block/nvme0n1p5/size 2>/dev/null || echo 0)
       # Verify size is ~24.9 GB (40M-65M sectors) to protect C:
       if [ "$SZ" -gt 40000000 ] && [ "$SZ" -lt 65000000 ]; then
         "$G/installer/lib/ld-musl-x86_64.so.1" --library-path "$G/installer/lib" \
           "$G/installer/bin/mke2fs" -F -q -t ext4 -m 0 -O verity -L GBOS_DATA /dev/nvme0n1p5
         DATA_NODE="/dev/nvme0n1p5"
       fi
     fi

     if [ -n "$DATA_NODE" ] && [ -b "$DATA_NODE" ]; then
       P4_CANON=$(readlink -f "$DATA_NODE" 2>/dev/null)
       [ -z "$P3_CANON" ] && P3_CANON="/dev/loop7"
       mkdir -p /new/data /new/metadata
       mount -t ext4 -o noatime,nodiratime "$P4_CANON" /new/data 2>/dev/null
       mount -t ext4 -o noatime,nodiratime "$P3_CANON" /new/metadata 2>/dev/null
       FROM=nvme
       return 0
     fi
     return 1
   }
   verify_persistent_storage || log "hook: persistent storage disabled; falling back to tmpfs"
   ```

---

## 5. Deployment Step-by-Step

### Step 1: Shrink Windows & Allocate Partitions
In Windows Disk Management (`diskmgmt.msc`):
1. Shrink `C:` to free ~33 GB of unallocated space.
2. Create Simple Volume `E:` (7.32 GB FAT32, Label: `GBOSSYS`).
3. Create Simple Volume `F:` (24.9 GB, Label: `GBOS_DATA`).

### Step 2: Stage Files to `E:\`
Extract gbOS86 payload into `E:\`:
* `E:\EFI\BOOT\BOOTX64.EFI`
* `E:\EFI\BOOT\KERNEL.EFI`
* `E:\loader\entries\gbos.conf` (must include `options ibt=off drm.panic_screen=kmsg`)
* `E:\gbos\super.img`
* `E:\gbos\hook.sh` (patched with `verify_persistent_storage`)
* `E:\gbos\metadata.img`

### Step 3: Boot via HP UEFI Menu
1. Restart laptop and tap **F9** repeatedly.
2. Select **"Boot From EFI File"** ➔ `GBOSSYS` ➔ `EFI/BOOT/BOOTX64.EFI`.
3. System boots directly into gbOS86 desktop with persistent user storage active.
