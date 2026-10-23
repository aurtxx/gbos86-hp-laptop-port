# Security Model, Limitations, and Threat Considerations

This document outlines the security posture, trade-offs, and operating constraints of the gbOS86 laptop port.

---

## 1. Security Architecture Summary

| Security Feature | Upstream Android (Stock) | gbOS86 HP Laptop Port | Implication |
| :--- | :--- | :--- | :--- |
| **SELinux Mode** | Enforcing (`enforcing=1`) | **Permissive (`permissive=1`)** | Policy violations are logged to `kmsg`, but access is **allowed**. App sandboxing is relaxed. |
| **Root Access** | Restricted / Locked Bootloader | **KernelSU Built-in** | Kernel-level root granting daemon (`ksud`) active. User can grant root to apps. |
| **System Updates** | Automatic A/B OTA from Google | **Permanently Suppressed** | Automatic system security updates disabled; manual image updates required. |
| **UEFI Secure Boot** | Enforced with Microsoft Keys | **Disabled in BIOS** | Custom kernel and trampolines not signed by Microsoft 3rd Party CA. |
| **Disk Encryption** | File-Based Encryption (fscrypt) | **Unencrypted ext4** | ext4 created without encryption feature so vold mounts without Trusty VM keymint. |
| **Host SSD Isolation** | N/A | **Enforced by 14-Gate Verification** | Internal NVMe SSD is strictly isolated; zero writes performed to host partitions. |

---

## 2. In-Depth Analysis of Key Security Trade-offs

### 2.1 SELinux in Permissive Mode
* **Current State**: The kernel command line enforces `androidboot.selinux=permissive gbos_permissive`.
* **Behavior**:
  - The kernel security module audits security decisions and logs `avc: denied ... permissive=1` into `dmesg`/`kmsg`.
  - However, the kernel **never denies** the requested system call.
* **Risk Profile**:
  - Without an enforcing SELinux policy, rogue applications or vulnerabilities can access cross-application files, execute binaries outside their sandbox, or interact with kernel devices.
  - **Mitigation / Best Practice**: Do not use this experimental operating system for highly sensitive personal banking, enterprise credentials, or untrusted APK testing.

### 2.2 System OTA Suppression & Security Patching
* **Current State**:
  - `update_engine.rc` is masked with `/tmp/empty.rc`.
  - `gbos_provision` sets `ota_disable_automatic_update 1` and disables `SystemUpdateService`.
* **Reason**:
  - The upstream OTA engine expects a dual-slot A/B dynamic super partition (12.88 GB). On this USB installation, gbOS86 uses a linear 3.68 GB EROFS partition, causing OTA verification to fail with error `0x713` and block the Setup Wizard.
* **Risk Profile**:
  - The OS will not receive automatic monthly Android security bulletins from Google.
  - **Mitigation**: Future operating system and security updates must be applied manually by updating the partition image files.

### 2.3 KernelSU Integration
* **Current State**:
  - KernelSU v32680 is compiled directly into the kernel binary (`6.18.21-gbos-whl`).
  - Kernel hooks intercept system calls in the kernel space.
* **Risk Profile**:
  - KernelSU provides superuser access managed by the KernelSU manager app.
  - While safer than traditional system-modifying root solutions (as system partitions remain read-only EROFS), granting root to untrusted apps gives complete hardware control.

---

## 3. Host Storage Safety & Data Isolation

* **Threat**: A rogue script or incorrect partition command overwriting the host laptop's internal Windows installation (`WD PC SN740` 512 GB NVMe SSD).
* **Defensive Controls Enforced**:
  1. **Subsystem Verification**: `verify_persistent_usb()` traverses sysfs parent directories asserting that `subsystem == usb`. Internal PCIe/NVMe storage controllers (`pci ... /bus/pci`) are rejected immediately.
  2. **Device Blacklisting**: Shell logic explicitly excludes `nvme*` and `mmcblk*`.
  3. **Zero Formatting in Boot Path**: No `mke2fs` or format commands are present in `hook.sh`.
  4. **Strict Partition UUID Locking**: Partitions are resolved by audited GPT PartUUIDs, not by volatile device node names (`/dev/sda` or `/dev/sdb`).
