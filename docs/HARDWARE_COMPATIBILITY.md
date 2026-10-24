# Hardware Compatibility Matrix: HP 15s-fr5009TU

This document provides a detailed breakdown of the hardware components on the **HP 15s-fr5009TU** laptop and their verified operating status under gbOS86 (Linux kernel 6.18.21-gbos-whl).

---

## 1. System Overview

| Specification | Hardware Details | Identification |
| :--- | :--- | :--- |
| **Model** | HP Laptop 15s-fr5009TU | System SKU / DMI: `HP Laptop 15s-fr5xxx` |
| **Processor** | Intel Core i3-1215U (12th Gen Alder Lake-U) | 6 Cores (2P + 4E) / 8 Threads, Base 1.20 GHz, Boost up to 4.40 GHz |
| **CPU Architecture** | x86_64 with AVX2, AVX-VNNI, SHA-NI, CET (IBT) | CPUID: `model name: 12th Gen Intel(R) Core(TM) i3-1215U` |
| **System Memory** | 8 GB DDR4-3200 MHz SDRAM | Kernel MemTotal: `7,718,984 kB` |
| **Internal SSD** | 512 GB PCIe NVMe M.2 SSD | `WD PC SN740 SDDPNQD-512G-2006` (Kept isolated & untouched) |
| **Port Storage** | 64 GB USB 3.0 / 2.0 Flash Drive | `Generic Flash Disk`, VID:PID `058F:6387`, Serial `634453C7` |

---

## 2. Component Compatibility Status

| Component | Hardware Identifier | Driver / Subsystem | Status | Technical Evidence & Notes |
| :--- | :--- | :--- | :---: | :--- |
| **CPU Handover** | Intel Core i3-1215U | Linux Kernel EFI handover | **Working** | Required `ibt=off` boot parameter due to KernelSU trampoline missing ENDBR64 instructions. |
| **Integrated GPU** | Intel Alder Lake-P GT1 UHD Graphics | `i915` kernel module (`0000:00:02.0`, `8086:46b3`) | **Working** | Full hardware acceleration verified in SurfaceFlinger. ANGLE running on native Vulkan Intel driver. |
| **Display Panel** | 15.6" 1920x1080 eDP IPS Panel | DRM / KMS (Intel i915) | **Working** | Native resolution at 60 Hz. Configured with `DENSITY=180` in `gbos.cfg` for proportional UI scaling. |
| **Touchpad** | ELAN0718:00 I2C Touchpad | `i2c_hid` / `hid_multitouch` (`04f3:30fd`) | **Working** | Automated IDC file generated (`Change_Timeout=0.02`) to fix Android touch flick latency. |
| **Keyboard** | Internal Laptop Keyboard | `atkbd` / Intel HID event filter | **Working** | Standard keyboard input responsive in terminal and UI. |
| **Wi-Fi** | Realtek RTL8821CE / Intel Wi-Fi | `rtw88_8821ce` / `iwlwifi` | **Partially Working** | Successfully scanned and connected to wireless networks in Boot-8 live session. Some firmware paths require manual packaging. |
| **Bluetooth** | Realtek / Intel Bluetooth USB adapter | `btusb` (`usb:0bda:b00a`) | **Working** | Controller initialized, detected devices in proximity. |
| **Webcam** | HP True Vision 720p HD Camera | `uvcvideo` (USB Video Class) | **Working** | Verified functional during live camera testing in Boot-8. |
| **Speakers & Audio Out** | Intel Alder Lake Smart Sound (SOF) | `snd_sof_pci_intel_tgl` (`0000:00:1f.3`, `8086:51c8`) | **Needs Verification** | ALSA SOF topology card `sof-hda-dsp` loaded and `audio_config.generated.xml` generated. Audio HAL mapped; userspace playback requires verification. |
| **Microphone** | Integrated Digital Microphone Array | `snd_sof_pci_intel_tgl` (dmic=6) | **Needs Verification** | SOF dmic detected; recording requires end-to-end app verification. |
| **USB Type-A / C Ports** | Intel Alder Lake xHCI Controller | `xhci_hcd` (`0000:00:14.0`, `8086:51ed`) | **Working** | Operates USB storage, peripherals, external mice/keyboards without drops. |
| **USB Ethernet / Tethering** | RNDIS / CDC-Ethernet over USB | Android netd / rndis | **Not Working** | USB tethering from host smartphone failed to acquire IP routing out-of-the-box. |
| **Android Device Linking** | Cross-device services / Nearby Share | Google Play Services / Bluetooth | **Not Working** | Disconnection errors when attempting to pair with another Android phone. |
| **Automatic System OTA** | Google update_engine | `com.google.android.gms.update` | **Not Working (By Design)** | Upstream OTA requires a 12.88 GB super partition and A/B slots. Permanently suppressed to prevent boot-blocking errors. |
| **Persistent Storage** | 64 GB USB Pendrive (ext4) | `verify_persistent_usb()` in `hook.sh` | **Experimental** | Ext4 partitions mounted (`GBOS_DATA`, `GBOS_META`). First boot package compilation verified. End-to-end reboot test pending. |

---

## 3. Hardware Component Detail Cards

### 3.1 Intel Alder Lake-P Integrated Graphics (`8086:46b3`)
* **PCI ID**: `0000:00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-UP3 GT1 [UHD Graphics] [8086:46b3] (rev 0c)`
* **Configuration**: `LOAD_I915=1`, `GPU_SOFTWARE=auto`
* **Log Evidence**:
  ```text
  [    3.642109] i915 0000:00:02.0: [drm] Found Alderlake-P
  [    3.644512] i915 0000:00:02.0: [drm] GuC firmware i915/adlp_guc_70.bin version 70.36.0
  [    3.647890] i915 0000:00:02.0: [drm] HuC firmware i915/adlp_huc_7.9.3.bin version 7.9.3
  [   36.238400] hook: software rendering: off (auto; Intel GPU driver i915 bound)
  ```

### 3.2 Intel Alder Lake Smart Sound Audio (`8086:51c8`)
* **PCI ID**: `0000:00:1f.3 Multimedia audio controller [0401]: Intel Corporation Alder Lake PCH-P High Definition Audio Controller [8086:51c8] (rev 01)`
* **Kernel Driver**: `snd_sof_pci_intel_tgl`
* **Card Identity**: `card id sofhdadsp, name sof-hda-dsp`
* **PCM Routing**:
  - Analog Playback: `0`
  - Analog Capture: `0`
  - Digital Mic (DMIC): `6`
  - HDMI Outputs: `3, 4, 5`
  - Headphone Jack: `'sof-hda-dsp Headphone'`
  - Mic Jack: `'sof-hda-dsp Mic'`
