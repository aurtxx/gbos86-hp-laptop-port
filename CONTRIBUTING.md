# Contributing to gbOS86 HP Laptop Port

Thank you for your interest in contributing to the experimental gbOS86 laptop port project!

---

## 1. Scope & Goals

This repository is dedicated to technical documentation, reproducible patches, and bootloader configurations for running gbOS86 on modern x86 laptop hardware.

We welcome:
* Test reports and logs from other Intel 12th/13th Gen laptops (Alder Lake / Raptor Lake).
* ALSA / SOF audio routing fixes for internal laptop speakers and microphones.
* Network routing fixes for USB tethering (RNDIS).
* Init script optimizations and clean daemon masking.

---

## 2. Reporting Issues & Submitting Test Logs

When opening an issue or reporting hardware compatibility:
1. **Specify Your Exact Laptop Model**:
   Include manufacturer, model number, CPU model, and GPU PCI ID.
2. **Attach Sanitized Diagnostic Logs**:
   The port automatically generates diagnostic logs in `gbos/logs/boot-N/` on your USB stick:
   - `hw.txt` (CPU, memory, PCI devices)
   - `hwdetect.txt` (loaded modules, modalias matches)
   - `stage0-dmesg.txt` (stage-0 early kernel boot trace)
   - `audio_config.generated.xml` (ALSA/SOF PCM topology)
3. **Redact Sensitive Information**:
   Never include Wi-Fi passwords, Google account credentials, or private personal data in bug reports.

---

## 3. Patch & Code Guidelines

If submitting a pull request:
1. **POSIX / BusyBox Shell Compatibility**:
   - `hook.sh`, `hwdetect.sh`, and stage-0 scripts execute under `BusyBox sh` in initramfs.
   - Do **not** use Bashisms (such as `[[ ... ]]`, process substitution `<(...)`, or non-standard arrays).
   - Validate all shell scripts with:
     ```bash
     busybox sh -n path/to/script.sh
     ```
2. **Strict Disk Safety**:
   - Never write code that assumes hardcoded disk nodes (`/dev/sda`, `/dev/nvme0n1`).
   - Any storage modification must enforce positive USB parent verification and audited PartUUIDs.
   - Never introduce automated disk formatting commands into the normal boot path.
3. **No Proprietary Binaries**:
   - Do not submit compiled Google OS images, proprietary APEX packages, or multi-gigabyte disk dumps.
   - Submit unified diffs (`.patch`) or configuration files.
