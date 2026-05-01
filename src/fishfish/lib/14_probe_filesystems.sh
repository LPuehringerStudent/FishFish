#!/bin/sh
# Probe: Filesystem types, btrfs subvolumes, zfs pools

ff_probe_filesystems() {
    echo "--- Filesystem Detection ---"
    for dev in $(ff_block_devices); do
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue
            # Use blkid if available
            if command -v blkid >/dev/null 2>&1; then
                id=$(blkid -s TYPE -s UUID -s LABEL "$target" 2>/dev/null)
                [ -n "$id" ] && echo "  $target: $id"
            fi

            # btrfs signature check at offset 65536 (0x10000)
            btrfs_magic=$(dd if="$target" bs=1 count=8 skip=65600 2>/dev/null)
            if [ "$btrfs_magic" = "_BHRfS_M" ]; then
                echo "  $target: btrfs filesystem detected"
                if command -v btrfs >/dev/null 2>&1; then
                    btrfs filesystem show "$target" 2>/dev/null | sed 's/^/    /'
                    btrfs subvolume list "$target" 2>/dev/null | head -5 | sed 's/^/    /'
                fi
            fi

            # ZFS label check: "zpool" label at offset 0 or 262144 (256K)
            zfs_magic=$(dd if="$target" bs=1 count=4 2>/dev/null)
            if [ "$zfs_magic" = "\x0c\xb1\x07\x00" ] || [ "$zfs_magic" = "\x00\x07\xb1\x0c" ]; then
                echo "  $target: ZFS pool detected"
            fi
        done
    done
    echo ""
}
