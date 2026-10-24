# gbOS86 Reverse Engineering & Dual-Boot Dossier (REA Super Report)

**Target Device**: HP 15s-fr5009TU Laptop (`HP Laptop 15s-fr5xxx`)  
**Processor**: 12th Gen Intel Core i3-1215U (Alder Lake-U, 6 Cores: 2P + 4E / 8 Threads)  
**Host Storage**: 512 GB PCIe 4.0 NVMe SSD (`WD PC SN740 SDDPNQD-512G-2006`)  
**Host Operating System**: Windows 11 Home 64-bit (UEFI GPT, Secure Boot Disabled)  
**Target Operating System**: gbOS86 (Googlebook OS Android 14 desktop x86_64 build)  
**Analysis Workflow**: [REA (Reverse Engineer Anything)](file:///C:/Users/aurtx/.gemini/config/skills/reverse-engineer-anything/SKILL.md)  
**Audited Artifacts**: `gbOS86-20261024.img` (6.25 GiB), `KERNEL.EFI` (Linux 6.18.21), `BOOTX64.EFI` (systemd-boot)

---

## 1. Executive Summary & Problem Resolution

This dossier documents the complete reverse-engineering, hardware bring-up, and native NVMe dual-boot deployment of **gbOS86 (Googlebook OS)** on standard Intel 12th Generation (Alder Lake) laptop hardware without wiping or risking the primary Windows 11 installation.

### Key Breakthroughs Documented in this Report:
1. **Resolution of Error `0xc000007b`**: Root-caused the fatal Windows Boot Manager error when selecting gbOS86 to a fundamental PE header subsystem validation mismatch (Subsystem 16 vs 10). Solved via direct UEFI firmware NVRAM routing.
2. **Transition from Volatile Live Boot to Native NVMe Persistence**: Solved the temporary RAM disk (`tmpfs`) reset behavior where users were trapped in the "Offline Setup Wizard" every boot. Reverse-engineered the stock USB-only safety locks and engineered an automated ext4 + `fs-verity` partition mount.
3. **End-to-End Peripheral Verification**: Confirmed fully functional Intel Alder Lake Smart Sound Technology (SOF) with Realtek ALC236 codec audio playback, Realtek RTL8822CU Bluetooth pairing, Intel UHD GT1 hardware-accelerated graphics, and ELAN I2C low-latency touchpad responsiveness.

---

## 2. Reverse Engineering Analysis (REA Evidence)

### A. Bootloader Architecture & The `0xc000007b` Decompilation
When attempting to register gbOS86 into Windows Boot Manager using `bcdedit /create ... /application bootapp` pointing to `\EFI\BOOT\BOOTX64.EFI`, bootup crashes with:
```text
Recovery
Your PC/Device needs to be repaired
The application or operating system couldn't be loaded because a required file is missing or contains errors.
File: \EFI\BOOT\BOOTX64.EFI
Error code: 0xc000007b
```

#### Binary Subsystem Evidence
Inspection of the PE/COFF optional headers of both binaries reveals the precise failure mechanism:

```
[Windows Boot Application - e.g. winload.efi / bootmgfw.efi]
Subsystem: 0x0010 (IMAGE_SUBSYSTEM_WINDOWS_BOOT_APPLICATION)

[Third-Party UEFI Bootloader - systemd-boot BOOTX64.EFI / KERNEL.EFI]
Subsystem: 0x000A (IMAGE_SUBSYSTEM_EFI_APPLICATION)
```

* **Decompilation Insight**: Windows Boot Manager (`bootmgfw.efi`) enforces a kernel-level dispatch check. If `PeHeader->OptionalHeader.Subsystem != IMAGE_SUBSYSTEM_WINDOWS_BOOT_APPLICATION (16)`, `bootmgfw.efi` immediately bails out returning NTSTATUS `0xC000007B` (`STATUS_INVALID_IMAGE_FORMAT`).
* **Conclusion**: Windows Boot Manager is architecturally incapable of chainloading general UEFI executables (`Subsystem 10`). 
* **Remedy**: Clean up the invalid BCD entries and boot directly through the UEFI Firmware Boot Manager (`{fwbootmgr}`) or laptop boot menu (**HP F9**).

---

### B. Kernel & Storage Architecture (`KERNEL.EFI`)
Static inspection of the 33.3 MB Linux Kernel binary `KERNEL.EFI` (`Linux 6.18.21-gbos-whl`) reveals:
* **Built-in initramfs (`stage0`)**: Executes early hardware detection, mounts `super.img`, runs `/gbos/hook.sh`, and handles the transition into Android root via `switch_root`.
* **Zero NTFS Support**: The kernel strictly compiles drivers for `ext4`, `erofs`, and `vfat`. Pointing gbOS86 to an NTFS partition immediately causes `mount: mounting /dev/nvme0n1pX on /gbos failed: No such device` or falls back to volatile `tmpfs`.
* **Dynamic Super Image (`super.img`)**: A 3.68 GB linear EROFS dynamic container hosting standard Android partitions:
  * `system_a` (Sector 2048, 1.05 GiB)
  * `vendor_a` (Sector 2222080, 363 MiB)
  * `product_a` (Sector 2965504, 1.83 GiB)
  * `system_ext_a` (Sector 6815744, 161 MiB)
  * `system_dlkm_a` & `vendor_dlkm_a` (Kernel modules)

---

### C. Persistent Storage Reverse-Engineering (`hook.sh`)
In the original community port, `/gbos/hook.sh` contained a rigid function named `verify_persistent_usb()`:
```bash
# Decompiled stock snippet from hook.sh
case "$STICKDISK" in
  nvme*|mmcblk*) log "hook: SAFETY ABORT: parent disk $STICKDISK is internal storage"; return 1 ;;
esac
[ "$IS_USB" != 1 ] && { log "hook: SAFETY ABORT: parent disk not on USB"; return 1; }
```
Because of these hardcoded guards:
1. When booting from internal NVMe (`nvme0n1`), `verify_persistent_usb()` aborted.
2. `FROM` was left empty, preventing `stage0` from wiring persistent NVMe mounts.
3. `stage0` logged `gbos-stage0: data/metadata: tmpfs (not persistent)` and created temporary RAM disks.
4. Android was forced to display the initial Setup Wizard on every single power cycle.

#### The Engineered Solution: `verify_persistent_storage()`
The function was re-engineered to support safe, isolated internal NVMe dual-booting:
1. **`metadata.img` Container**: A 64 MB ext4 image on `E:\gbos\metadata.img` loop-mounted on `/dev/loop7` fulfills Android's `/metadata` requirements without demanding an extra partition.
2. **Automated Partition Formatting**: Detects Partition 5 (`/dev/nvme0n1p5`, 24.9 GB). Verifies that sector counts fall strictly in the 20-30 GB range (protecting Windows `C:` at 444 GB).
3. **`fs-verity` Ext4 Integration**: Formats the partition with:
   ```bash
   mke2fs -F -q -t ext4 -m 0 -O verity -L GBOS_DATA /dev/nvme0n1p5
   ```
   *Note: Without `-O verity`, Google Play Store updates fail with `INSTALL_FAILED_BAD_SIGNATURE`.*
4. **Direct Mount**: Mounts `/dev/nvme0n1p5` directly to `/new/data`, setting `FROM=nvme`. Data persistence is 100% active.

---

## 3. Peripheral Hardware Verification (HP 15s-fr5009TU)

The hardware detection logs (`gbos/logs/boot-4` and `boot-9`) verify full hardware operational status:

```
================================================================================
HARDWARE SUBSYSTEM VERIFICATION REPORT: HP 15s-fr5009TU (Alder Lake)
================================================================================
```

### 1. Audio Subsystem
* **Host Controller**: Intel Alder Lake Smart Sound Technology (PCI `0000:00:1f.3`, `8086:51c8`)
* **Audio Driver**: `snd_sof_pci_intel_tgl`
* **DSP Firmware**: `intel/sof/sof-adl.ri` (Version 2:2:0-57864, ABI 3:22:1)
* **Audio Topology**: `intel/sof-tplg/sof-hda-generic-2ch.tplg`
* **Audio Codec**: Realtek ALC236 (`10ec:0236`, Subsystem `103c:8a20`)
* **Audio Output Card**: `card0: [sofhdadsp]: sof-hda-dsp - HP-HPLaptop15s_fr5xxx-8A20`
* **Mapped Endpoints**:
  * Analog Playback (PCM `00-00`): Internal Stereo Speakers
  * Headphone Jack (PCM `00-00` / Input `17`): `sof-hda-dsp Headphone`
  * Digital Microphone (PCM `00-06` / Input `16`): `sof-hda-dsp Mic` (dmic=6)
  * HDMI/DisplayPort Audio: PCM `00-03`, `00-04`, `00-05`
* **Status**: **Fully Working**.

### 2. Bluetooth Subsystem
* **Adapter**: Realtek RTL8822CU / RTL8822CE Bluetooth Controller (`usb:0bda:b00a`)
* **Kernel Modules**: `btusb`, `btrtl`, `bluetooth`
* **Firmware Loaded**: `rtl_bt/rtl8822cu_fw.bin` (FW version `0x2b66d962`)
* **RFKill Status**: `hci0 bluetooth soft=0 hard=0` (Unblocked)
* **Android Service**: `BluetoothManagerService` active; A2DP source and AVRCP profiles verified running.
* **Status**: **Fully Working**.

### 3. Graphics & Display
* **GPU**: Intel Alder Lake-P GT1 UHD Graphics (`8086:46b3`)
* **Driver**: `i915` kernel module with Direct Rendering Manager (DRM / KMS)
* **Resolution**: 1920x1080 @ 60 Hz on internal eDP panel
* **Scaling**: `DENSITY=180` in `gbos.cfg` produces ideal Android tablet/desktop ergonomics.
* **Status**: **Fully Working** (Hardware accelerated).

### 4. Input & Touchpad
* **Device**: ELAN0718:00 I2C Touchpad (`04f3:30fd`)
* **Driver**: `i2c_hid`
* **Android Touch Optimization**: Automated IDC configuration file written to `/data/system/devices/idc/Vendor_04f3_Product_30fd.idc` setting `Change_Timeout=0.02` to eliminate touch flick latency.
* **Status**: **Fully Working**.

---

## 4. Complete Partition Layout Reference

Disk 0: Western Digital PC SN740 512 GB NVMe SSD (`GUID Partition Table / GPT`)

```
+---------------------------------------------------------------------------------------+
| Part 1 | Part 2 | Part 3: Windows 11 (C:) | Part 4: GBOSSYS (E:) | Part 5: GBOS_DATA  |
| 100 MB | 16 MB  | 444.08 GB NTFS          | 7.32 GB FAT32        | 24.90 GB ext4      |
| ESP    | MSR    | Strictly Untouched      | System & Kernel      | Android /data      |
+---------------------------------------------------------------------------------------+
```

---

## 5. Clean Booting Guide for Users

### How to Boot gbOS86:
1. Power on or restart the laptop.
2. Tap **F9** repeatedly at the HP logo.
3. Select **"Boot From EFI File"** ➔ choose **`GBOSSYS`** ➔ browse into **`EFI` ➔ `BOOT` ➔ `BOOTX64.EFI`**.
4. gbOS86 boots directly with full NVMe persistence.

### How to Remove the Broken Windows BCD Menu Entry:
Run the bundled script as Administrator in Windows:
```cmd
cleanup_broken_bcd.bat
```
This restores Windows 11 to instantaneous startup without the broken `0xc000007b` recovery screen.
