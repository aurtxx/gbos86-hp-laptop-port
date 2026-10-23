#!/bin/sh
# Standalone POSIX verification logic for persistent USB storage in gbOS86
# Validated under BusyBox v1.37.0 sh

verify_persistent_usb() {
  [ -z "$DEV" ] && { log "hook: SAFETY ABORT: DEV is empty"; return 1; }

  # 1. Canonicalize boot partition and determine parent disk
  DEV_CANON=$(readlink -f "$DEV" 2>/dev/null)
  [ -z "$DEV_CANON" ] || [ ! -b "$DEV_CANON" ] && { log "hook: SAFETY ABORT: DEV ($DEV) not a valid block device"; return 1; }

  DEV_SYSFS=$(readlink -f "/sys/class/block/${DEV_CANON##*/}/.." 2>/dev/null)
  [ -z "$DEV_SYSFS" ] || [ ! -d "$DEV_SYSFS" ] && { log "hook: SAFETY ABORT: failed to resolve sysfs parent for $DEV_CANON"; return 1; }
  STICKDISK=$(basename "$DEV_SYSFS")

  # 2. Strict exclusion of internal storage types
  case "$STICKDISK" in
    nvme*|mmcblk*) log "hook: SAFETY ABORT: parent disk $STICKDISK is internal storage"; return 1 ;;
  esac

  # 3. Robust USB bus verification by walking ancestor device subsystems
  IS_USB=0
  _anc="$DEV_SYSFS"
  while [ -n "$_anc" ] && [ "$_anc" != "/" ] && [ "$_anc" != "/sys" ] && [ "$_anc" != "/sys/devices" ]; do
    if [ -e "$_anc/subsystem" ]; then
      _sub=$(basename "$(readlink -f "$_anc/subsystem" 2>/dev/null)")
      [ "$_sub" = "usb" ] && { IS_USB=1; break; }
    fi
    _anc=$(dirname "$_anc")
  done
  [ "$IS_USB" != 1 ] && { log "hook: SAFETY ABORT: parent disk $STICKDISK is not on the USB bus ($DEV_SYSFS)"; return 1; }

  # 4. Resolve P3 and P4 by audited GPT PartUUIDs
  # P3 (GBOS_META): 30715566-bd33-4e69-8d7e-070776e2d0a6
  # P4 (GBOS_DATA): 19954bef-db10-4d1b-8404-17d5cb7ec97c
  P3=""
  P4=""
  [ -b "/dev/disk/by-partuuid/30715566-bd33-4e69-8d7e-070776e2d0a6" ] && P3="/dev/disk/by-partuuid/30715566-bd33-4e69-8d7e-070776e2d0a6"
  [ -b "/dev/disk/by-partuuid/19954bef-db10-4d1b-8404-17d5cb7ec97c" ] && P4="/dev/disk/by-partuuid/19954bef-db10-4d1b-8404-17d5cb7ec97c"

  # Fallback: Parse GPT table via bundled util-linux sfdisk with clean argument quoting
  if [ -z "$P3" ] || [ -z "$P4" ]; then
    SFDISK_BIN="$G/installer/bin/sfdisk"
    MUSL_LD="$G/installer/lib/ld-musl-x86_64.so.1"
    MUSL_LIB="$G/installer/lib"
    if [ -x "$SFDISK_BIN" ] && [ -x "$MUSL_LD" ]; then
      SFDUMP=$("$MUSL_LD" --library-path "$MUSL_LIB" "$SFDISK_BIN" -d "/dev/$STICKDISK" 2>/dev/null)
      [ -z "$P3" ] && P3=$(echo "$SFDUMP" | grep -i 'uuid=30715566-bd33-4e69-8d7e-070776e2d0a6' | awk '{print $1}')
      [ -z "$P4" ] && P4=$(echo "$SFDUMP" | grep -i 'uuid=19954bef-db10-4d1b-8404-17d5cb7ec97c' | awk '{print $1}')
    fi
  fi
  [ -z "$P3" ] || [ -z "$P4" ] && { log "hook: SAFETY ABORT: could not resolve P3 and P4 by audited PartUUID on $STICKDISK"; return 1; }

  # 5. Canonicalize partition paths and verify block devices exist
  P3_CANON=$(readlink -f "$P3" 2>/dev/null)
  P4_CANON=$(readlink -f "$P4" 2>/dev/null)
  [ -z "$P3_CANON" ] || [ ! -b "$P3_CANON" ] || [ -z "$P4_CANON" ] || [ ! -b "$P4_CANON" ] && { log "hook: SAFETY ABORT: partition nodes not valid block devices"; return 1; }

  # 6. Prove boot volume, P3, and P4 belong to the EXACT same physical parent disk
  P3_SYSFS=$(readlink -f "/sys/class/block/${P3_CANON##*/}/.." 2>/dev/null)
  P4_SYSFS=$(readlink -f "/sys/class/block/${P4_CANON##*/}/.." 2>/dev/null)
  [ "$P3_SYSFS" != "$DEV_SYSFS" ] || [ "$P4_SYSFS" != "$DEV_SYSFS" ] && { log "hook: SAFETY ABORT: physical parent disk mismatch"; return 1; }

  # 7. Verify sector-size ranges (P3 ~64MB = ~131072 sectors; P4 ~52.67GB = ~110456832 sectors)
  P3_SZ=$(cat "/sys/class/block/${P3_CANON##*/}/size" 2>/dev/null || echo 0)
  P4_SZ=$(cat "/sys/class/block/${P4_CANON##*/}/size" 2>/dev/null || echo 0)
  [ "$P3_SZ" -lt 120000 ] || [ "$P3_SZ" -gt 150000 ] && { log "hook: SAFETY ABORT: P3 size $P3_SZ out of range"; return 1; }
  [ "$P4_SZ" -lt 100000000 ] || [ "$P4_SZ" -gt 125000000 ] && { log "hook: SAFETY ABORT: P4 size $P4_SZ out of range"; return 1; }

  # 8. Cross-verify filesystem UUIDs and labels using findfs
  # Audited UUIDs: P3=8e5d9e62-3a24-46fd-8d96-4077c38fae44, P4=8fb16737-a46a-442c-af5c-3ef60d77d655
  # Audited Labels: P3=GBOS_META, P4=GBOS_DATA
  P3_UUID_NODE=$(readlink -f "$(findfs UUID=8e5d9e62-3a24-46fd-8d96-4077c38fae44 2>/dev/null)" 2>/dev/null)
  P4_UUID_NODE=$(readlink -f "$(findfs UUID=8fb16737-a46a-442c-af5c-3ef60d77d655 2>/dev/null)" 2>/dev/null)
  P3_LBL_NODE=$(readlink -f "$(findfs LABEL=GBOS_META 2>/dev/null)" 2>/dev/null)
  P4_LBL_NODE=$(readlink -f "$(findfs LABEL=GBOS_DATA 2>/dev/null)" 2>/dev/null)
  [ "$P3_CANON" != "$P3_UUID_NODE" ] || [ "$P3_CANON" != "$P3_LBL_NODE" ] && { log "hook: SAFETY ABORT: P3 UUID/label mismatch"; return 1; }
  [ "$P4_CANON" != "$P4_UUID_NODE" ] || [ "$P4_CANON" != "$P4_LBL_NODE" ] && { log "hook: SAFETY ABORT: P4 UUID/label mismatch"; return 1; }

  # 9. Compare major/minor device numbers between PartUUID node and findfs node
  P3_DEVNUM=$(cat "/sys/class/block/${P3_CANON##*/}/dev" 2>/dev/null)
  P4_DEVNUM=$(cat "/sys/class/block/${P4_CANON##*/}/dev" 2>/dev/null)
  [ -z "$P3_DEVNUM" ] || [ "$P3_DEVNUM" != "$(cat "/sys/class/block/${P3_UUID_NODE##*/}/dev" 2>/dev/null)" ] && { log "hook: SAFETY ABORT: P3 devnum mismatch"; return 1; }
  [ -z "$P4_DEVNUM" ] || [ "$P4_DEVNUM" != "$(cat "/sys/class/block/${P4_UUID_NODE##*/}/dev" 2>/dev/null)" ] && { log "hook: SAFETY ABORT: P4 devnum mismatch"; return 1; }

  # 10. All checks passed: Safely wire stage0 persistent mount
  log "hook: verified persistent USB storage on $STICKDISK: meta=$P3_CANON data=$P4_CANON"
  FROM=nvme
  return 0
}
