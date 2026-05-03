#!/bin/sh
# Mount engine: safely mount partitions for injection

FF_MOUNT_LIST="/tmp/ff_mounts.list"

ff_mount_target() {
    dev="$1"
    fstype="$2"
    mnt="/tmp/ff_mnt_${dev##*/}"
    mkdir -p "$mnt"

    [ "$fstype" = "swap" ] && return 1

    # Already mounted? Reuse the mountpoint
    if mount | grep -q "^$dev on "; then
        mnt=$(mount | grep "^$dev on " | awk '{print $3}' | head -1)
        echo "$mnt"
        return 0
    fi

    # Try explicit filesystem type first
    if mount -t "$fstype" -o rw "$dev" "$mnt" 2>/dev/null; then
        echo "$mnt" >> "$FF_MOUNT_LIST"
        echo "$mnt"
        return 0
    fi

    # Filesystem-specific fallbacks for drivers with special requirements
    case "$fstype" in
        ntfs)
            # Modern ntfs3 driver (Linux 5.15+)
            if mount -t ntfs3 -o rw "$dev" "$mnt" 2>/dev/null; then
                echo "$mnt" >> "$FF_MOUNT_LIST"
                echo "$mnt"
                return 0
            fi
            # Legacy ntfs-3g FUSE driver
            if command -v ntfs-3g >/dev/null 2>&1; then
                if ntfs-3g -o rw "$dev" "$mnt" 2>/dev/null; then
                    echo "$mnt" >> "$FF_MOUNT_LIST"
                    echo "$mnt"
                    return 0
                fi
            fi
            ;;
        exfat)
            if mount -t exfat -o rw "$dev" "$mnt" 2>/dev/null; then
                echo "$mnt" >> "$FF_MOUNT_LIST"
                echo "$mnt"
                return 0
            fi
            ;;
        xfs)
            if mount -t xfs -o rw "$dev" "$mnt" 2>/dev/null; then
                echo "$mnt" >> "$FF_MOUNT_LIST"
                echo "$mnt"
                return 0
            fi
            ;;
        f2fs)
            if mount -t f2fs -o rw "$dev" "$mnt" 2>/dev/null; then
                echo "$mnt" >> "$FF_MOUNT_LIST"
                echo "$mnt"
                return 0
            fi
            ;;
        btrfs)
            if mount -t btrfs -o rw "$dev" "$mnt" 2>/dev/null; then
                echo "$mnt" >> "$FF_MOUNT_LIST"
                echo "$mnt"
                return 0
            fi
            ;;
    esac

    # Last resort: auto-detect
    if mount -o rw "$dev" "$mnt" 2>/dev/null; then
        echo "$mnt" >> "$FF_MOUNT_LIST"
        echo "$mnt"
        return 0
    fi

    rmdir "$mnt" 2>/dev/null || true
    return 1
}

ff_unmount_all() {
    [ -f "$FF_MOUNT_LIST" ] || return
    while IFS= read -r mnt; do
        [ -n "$mnt" ] || continue
        if umount -l "$mnt" 2>/dev/null; then
            echo "  Unmounted $mnt"
        else
            echo "  Lazy unmount failed for $mnt, trying sync..."
            sync
        fi
        rmdir "$mnt" 2>/dev/null || true
    done < "$FF_MOUNT_LIST"
    rm -f "$FF_MOUNT_LIST"
}
