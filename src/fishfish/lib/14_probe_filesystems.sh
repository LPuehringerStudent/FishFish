#!/bin/sh
# Probe: Filesystem types, btrfs subvolumes, zfs pools

ff_probe_filesystems() {
    echo "--- Filesystem Detection ---"
    for target in $(ff_all_targets); do
        [ -b "$target" ] || continue
        # Use blkid if available; strip leading device path to avoid double prefix
        if command -v blkid >/dev/null 2>&1; then
            id=$(blkid -s TYPE -s UUID -s LABEL "$target" 2>/dev/null)
            id=$(echo "$id" | sed 's/^[^:]*: *//')
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

        # xfs signature: "XFSB" at offset 0
        xfs_magic=$(dd if="$target" bs=1 count=4 2>/dev/null)
        if [ "$xfs_magic" = "XFSB" ]; then
            echo "  $target: xfs filesystem detected"
        fi

        # f2fs signature at offset 1024: 0xF2F51020 (little-endian)
        f2fs_magic=$(dd if="$target" bs=1 count=4 skip=1024 2>/dev/null)
        expected_f2fs=$(printf '%b' '\020\040\365\362')
        if [ "$f2fs_magic" = "$expected_f2fs" ]; then
            echo "  $target: f2fs filesystem detected"
        fi

        # ZFS label check: pool label at offset 0 (0x0CB10700 LE / 0x0007B10C BE)
        zfs_magic=$(dd if="$target" bs=1 count=4 2>/dev/null)
        expected_zfs_le=$(printf '%b' '\014\261\007\000')
        expected_zfs_be=$(printf '%b' '\000\007\261\014')
        if [ "$zfs_magic" = "$expected_zfs_le" ] || [ "$zfs_magic" = "$expected_zfs_be" ]; then
            echo "  $target: ZFS pool detected"
        fi
    done
    echo ""
}
