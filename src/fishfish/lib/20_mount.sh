#!/bin/sh
# Mount engine: safely mount partitions for injection

FF_MOUNT_LIST="/tmp/ff_mounts.list"

ff_mount_target() {
    dev="$1"
    fstype="$2"
    mnt="/tmp/ff_mnt_${dev##*/}"
    mkdir -p "$mnt"

    [ "$fstype" = "swap" ] && return 1

    if mount | grep -q "^$dev on "; then
        mnt=$(mount | grep "^$dev on " | awk '{print $3}' | head -1)
        echo "$mnt"
        return 0
    fi

    if mount -t "$fstype" -o rw "$dev" "$mnt" 2>/dev/null; then
        echo "$mnt" >> "$FF_MOUNT_LIST"
        echo "$mnt"
        return 0
    fi

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
