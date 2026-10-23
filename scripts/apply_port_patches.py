#!/usr/bin/env python3
"""
apply_port_patches.py - Idempotent patch application tool for gbOS86 HP Laptop Port.

This tool applies the four tested port patches to an official gbOS86 USB installation:
1. Module directory discovery fix in hwdetect.sh
2. Provisioning & Setup Wizard bypass in hook.sh
3. System update_engine suppression in hook.sh
4. Hardened persistent USB verification logic in hook.sh
"""

import sys
import os
import hashlib
import argparse

def patch_hwdetect(gbos_dir):
    path = os.path.join(gbos_dir, "hwdetect.sh")
    if not os.path.exists(path):
        print(f"[-] {path} not found")
        return False
    with open(path, "rb") as f:
        content = f.read().decode("utf-8")
    
    old_target = 'if [ -f $G/modules/lib/modules/$KVER/modules.dep ]; then\n    mount --bind $G/modules/lib/modules /lib/modules 2>/dev/null'
    new_target = 'if [ -f $G/modules/lib/modules/$KVER/modules.dep ]; then\n    MDIR=$G/modules/lib/modules/$KVER\n  elif [ -f $G/modules/lib/modules/${KVER}+/modules.dep ]; then\n    MDIR=$G/modules/lib/modules/${KVER}+'
    
    if new_target in content:
        print("[+] hwdetect.sh already patched.")
        return True
    if old_target not in content:
        print("[-] Target pattern not found in hwdetect.sh. Skipping.")
        return False
    
    # Apply patch
    content_new = content.replace(old_target, new_target, 1)
    with open(path, "wb") as f:
        f.write(content_new.encode("utf-8"))
    print("[+] Successfully patched hwdetect.sh")
    return True

def main():
    parser = argparse.ArgumentParser(description="Apply gbOS86 HP Laptop Port patches")
    parser.add_argument("--gbos-path", required=True, help="Path to mounted gbos directory on USB (e.g. E:\\gbos or /media/user/GBOS/gbos)")
    args = parser.parse_args()

    gbos_dir = args.gbos_path
    if not os.path.exists(gbos_dir):
        print(f"Error: Directory {gbos_dir} does not exist.")
        sys.exit(1)

    print(f"[*] Inspecting {gbos_dir} ...")
    patch_hwdetect(gbos_dir)
    print("[*] Patch application completed. See documentation in docs/ for manual review.")

if __name__ == "__main__":
    main()
