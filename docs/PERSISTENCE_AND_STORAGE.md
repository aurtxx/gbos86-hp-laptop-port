# Persistent Storage Design & Safety Hardening

This document explains the architecture, security mechanisms, and verification procedures for persistent storage on the gbOS86 USB installation.

---

## 1. Storage Architecture Overview

In stock gbOS86 live boots, Android's `/data` and `/metadata` directories are mounted as `tmpfs` (RAM-backed filesystems). Consequently, all installed applications, user configurations, and accounts are lost on power-off.

To convert gbOS86 into a fully persistent operating system running entirely from the 64 GB USB pendrive, unallocated flash space was partitioned into two dedicated ext4 filesystems:

```text
[Disk 1: 64 GB USB Pendrive (Generic Flash Disk, Serial 634453C7)]
|-- Partition 1 (256 MiB FAT32):  EFI System (systemd-boot + KERNEL.EFI)
|-- Partition 2 (6.00 GiB FAT32): GBOS (system images, super.img, hook.sh, gbos.cfg)
|-- Partition 3 (64 MiB ext4):    GBOS_META (Android metadata, PartUUID 30715566-...)
`-- Partition 4 (52.67 GiB ext4): GBOS_DATA (Android persistent /data, PartUUID 19954bef-...)
```

---

## 2. Stage-0 Control Flow & `FROM=nvme` Variable Semantics

In `stage0_init.sh` (lines 185–206), the persistence mounting logic is gated by the variable `$FROM`:

```bash
# Sourced from hook.sh
DATA=; META=
if [ $FROM = nvme ]; then
  DATA=$(findfs LABEL=GBOS_DATA 2>/dev/null); META=$(findfs LABEL=GBOS_META 2>/dev/null)
fi

if [ -n "$DATA" ] && [ -n "$META" ]; then
  e2fsck_p $META; e2fsck_p $DATA
  mount -t ext4 -o noatime,nosuid,nodev $META /new/metadata
  mount -t ext4 -o noatime,nosuid,nodev $DATA /new/data
else
  mount -t tmpfs -o mode=0771 tmpfs /new/data
  mount -t tmpfs tmpfs /new/metadata
  log "data/metadata: tmpfs (not persistent)"
fi
```

### Forensic Proof on Variable Meaning:
* Despite the name `FROM=nvme`, **this variable does NOT access NVMe hardware**.
* In `stage0_init.sh`, it is used strictly as a **boolean flag**.
* If `$FROM == "nvme"`, stage 0 executes `findfs LABEL=GBOS_DATA` and mounts ext4.
* If `$FROM != "nvme"`, stage 0 safely defaults to `tmpfs` (RAM live mode).

---

## 3. The 14-Gate Hardened Verification Function (`verify_persistent_usb`)

To ensure that gbOS86 **NEVER** mounts or targets internal NVMe/SATA SSDs, the verification logic in `gbos/hook.sh` enforces 14 independent safety checks before setting `FROM=nvme`:

```mermaid
flowchart TD
    A["hook.sh: verify_persistent_usb()"] --> G1["Gate 1: Assert DEV is non-empty"]
    G1 --> G2["Gate 2: Canonicalize DEV with readlink -f"]
    G2 --> G3["Gate 3: Resolve sysfs parent via /sys/class/block/.../.."]
    G3 --> G4["Gate 4: Reject internal storage types (nvme*, mmcblk*)"]
    G4 --> G5["Gate 5: Walk ancestor subsystems; assert subsystem == 'usb'"]
    G5 --> G6["Gate 6: Resolve P3 & P4 by audited GPT PartUUIDs (sfdisk -d quoted)"]
    G6 --> G7["Gate 7: Canonicalize P3 & P4 partition device nodes"]
    G7 --> G8["Gate 8: Prove P3, P4, and DEV belong to IDENTICAL parent sysfs directory"]
    G8 --> G9["Gate 9: Enforce sector bounds (P3: 120k-150k sectors)"]
    G9 --> G10["Gate 10: Enforce sector bounds (P4: 100M-125M sectors)"]
    G10 --> G11["Gate 11: Cross-verify P3 filesystem UUID and LABEL against findfs"]
    G11 --> G12["Gate 12: Cross-verify P4 filesystem UUID and LABEL against findfs"]
    G12 --> G13["Gate 13: Compare major/minor devnum (/sys/class/block/.../dev) for P3"]
    G13 --> G14["Gate 14: Compare major/minor devnum (/sys/class/block/.../dev) for P4"]
    G14 -- "ALL PASS" --> S["Set FROM=nvme (Return 0)"]
    G1 -- "Fail" --> F["Return 1 -> Fall back safely to tmpfs"]
    G2 -- "Fail" --> F
    G3 -- "Fail" --> F
    G4 -- "Fail" --> F
    G5 -- "Fail" --> F
    G6 -- "Fail" --> F
    G7 -- "Fail" --> F
    G8 -- "Fail" --> F
    G9 -- "Fail" --> F
    G10 -- "Fail" --> F
    G11 -- "Fail" --> F
    G12 -- "Fail" --> F
    G13 -- "Fail" --> F
    G14 -- "Fail" --> F
```

---

## 4. Test Verification Under Initramfs BusyBox `sh`

The exact `verify_persistent_usb()` implementation was tested against all failure modes using the real initramfs binary (`BusyBox v1.37.0`):

1. **Test 1 (Happy Path)**: USB parent, matching PartUUIDs, valid ext4 UUIDs -> **PASS (`FROM=nvme`)**
2. **Test 2 (Internal NVMe)**: Parent disk `nvme0n1` -> **PASS (Aborted to `tmpfs`)**
3. **Test 3 (Non-USB SATA Bus)**: Subsystem `ata` -> **PASS (Aborted to `tmpfs`)**
4. **Test 4 (PartUUID Mismatch)**: Mismatched partition GUID -> **PASS (Aborted to `tmpfs`)**
5. **Test 5 (Foreign Parent Mismatch)**: P4 on separate disk -> **PASS (Aborted to `tmpfs`)**
6. **Test 6 (Sector Bounds Out of Range)**: Unexpected partition size -> **PASS (Aborted to `tmpfs`)**
7. **Test 7 (Filesystem UUID Mismatch)**: Filesystem UUID altered -> **PASS (Aborted to `tmpfs`)**

---

## 5. Zero Formatting in Boot Path

Early prototype drafts included formatting calls (`mke2fs`) if persistent partitions were unformatted. To prevent any risk of data loss or accidental re-formatting:
* **All `mke2fs` commands were 100% removed from `hook.sh`**.
* Both partitions must be pre-formatted. If verification fails, the system logs `SAFETY ABORT` and safely defaults to non-persistent `tmpfs`.
