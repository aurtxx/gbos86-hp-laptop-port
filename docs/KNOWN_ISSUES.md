# Known Issues, Limitations, and Workarounds

This document tracks all confirmed issues, partial behaviors, and architectural limitations in the experimental gbOS86 HP Laptop Port.

---

## 1. Confirmed Issues & Workarounds

### Issue 1: Initial First-Boot Indexing Duration on USB Flash Media
* **Severity**: Low (Behavioral / Ergonomic)
* **Symptom**: On the very first boot after formatting the persistent ext4 `/data` partition, the boot animation plays continuously for **5 to 7 minutes**, leading users to believe the machine is stuck in a boot loop.
* **Root Cause**:
  Android's `PackageManagerService` must execute `setFirstBoot: true`. It scans, parses manifests, extracts native libraries, and verifies signatures for **312 system packages**. Because reading the EROFS compressed system images and writing ext4 directories share the same physical USB 2.0/3.0 bus (limited to ~15 MB/s random I/O), writing ~1.2 GB of small files takes several minutes.
* **Workaround**: Allow the initial boot to complete undisturbed. Once `packages.xml` is generated, all subsequent reboots load the desktop in **15 to 30 seconds**.

---

### Issue 2: ChromeOS `timberslide` Daemon Crash Loop
* **Severity**: Low (Log noise / Minor CPU overhead)
* **Symptom**: `logcat` and `kmsg` show `timberslide` crashing and restarting repeatedly:
  ```text
  timberslide: cros_ec: A fatal error occurred: failed to open EC device: cros_ec: No such file or directory (os error 2)
  init: process with updatable components 'timberslide' exited 4 times before boot completed
  flags_health_check: ServerConfigurableFlagsReset updatable crashing detected, resetting flags.
  ```
* **Root Cause**:
  `timberslide` is Google's ChromeOS Embedded Controller log streamer. It expects a hardware ChromeOS EC at `/dev/cros_ec`, which does not exist on standard PC laptops.
* **Workaround**:
  Add `/new/system/etc/init/timberslide.rc` to the masked rc loop in `gbos/hook.sh` (binding `/tmp/empty.rc` over it).

---

### Issue 3: Google Automatic System OTA Failure (0x713)
* **Severity**: Medium (Architectural Trade-off)
* **Symptom**: The stock Android Setup Wizard stops on an unskippable "System update failed" page.
* **Root Cause**:
  Google's `update_engine` requires a dynamic 12.88 GB super partition with dual A/B slots (`boot_a`, `boot_b`). gbOS86 runs from a linear read-only 3.68 GB EROFS partition booting via `systemd-boot`. The update engine fails partition verification.
* **Workaround**:
  Automatic OTA is permanently suppressed via `hook.sh` (`ota_disable_automatic_update 1`, masking `update_engine.rc`, and provisioning flags). Security and OS updates must be performed by manual image re-flashes.

---

### Issue 4: USB Tethering / RNDIS Network Routing
* **Severity**: Medium (Functional)
* **Symptom**: Plugging in a mobile smartphone with USB Tethering enabled fails to provide internet connectivity to the laptop.
* **Root Cause**: Android's network routing daemon (`netd`) does not automatically configure an upstream routing gateway for secondary USB RNDIS interfaces when Wi-Fi is managed by Android desktop.
* **Proposed Next Steps**: Inspect `ip route` and `iptables` under root shell to script an automatic gateway fallback.

---

### Issue 5: Android Cross-Device Linking
* **Severity**: Low (Feature)
* **Symptom**: Attempting to pair an Android smartphone via Cross-Device Services or Phone Link disconnects or fails to establish a peer-to-peer session.
* **Status**: Untested / Experimental.

---

### Issue 6: Secure Boot Must Remain Disabled
* **Severity**: Medium (Security Posture)
* **Symptom**: Enabling Secure Boot in BIOS causes UEFI to reject `BOOTX64.EFI` or `KERNEL.EFI`.
* **Root Cause**: The custom kernel is modified with KernelSU and is not signed by Microsoft's 3rd Party UEFI Certificate Authority.
* **Workaround**: Secure Boot must remain disabled in the laptop's BIOS Setup (F10).
