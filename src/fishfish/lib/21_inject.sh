#!/bin/sh
# Injection engine: run payload on eligible filesystems
# Handles: standard partitions, LVM LVs, MD RAID, btrfs subvolumes, ZFS datasets

# Try to activate LVM volumes if tools are available
ff_activate_lvm() {
    if command -v vgscan >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
        echo "  Activating LVM volumes..."
        vgscan --mknodes >/dev/null 2>&1 || true
        vgchange -ay >/dev/null 2>&1 || true
    fi
}

# Try to assemble MD RAID arrays if tools are available
ff_activate_raid() {
    if command -v mdadm >/dev/null 2>&1; then
        echo "  Assembling MD RAID arrays..."
        mdadm --assemble --scan >/dev/null 2>&1 || true
    fi
}

# Inject into a single target device/partition
ff_inject_target() {
    target="$1"
    [ -b "$target" ] || return

    # Identify filesystem
    local fstype=""
    local uuid=""
    local label=""
    if command -v blkid >/dev/null 2>&1; then
        local blkid_out=""
        if command -v timeout >/dev/null 2>&1; then
            blkid_out=$(timeout -k 5 10 blkid "$target" 2>/dev/null)
        else
            blkid_out=$(blkid "$target" 2>/dev/null)
        fi
        fstype=$(echo "$blkid_out" | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
        uuid=$(echo "$blkid_out" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
        label=$(echo "$blkid_out" | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
    fi

    # Skip unidentifiable or excluded
    [ -n "$fstype" ] || return
    ff_in_filter "$uuid" "$label" || return

    # Skip swap
    [ "$fstype" = "swap" ] && return

    echo "  Target: $target ($fstype, UUID=$uuid, LABEL=$label)"

    # Mount
    local mnt=""
    mnt=$(ff_mount_target "$target" "$fstype")
    if [ -z "$mnt" ]; then
        echo "    -> Mount failed, skipping"
        return
    fi

    # Run payload
    echo "    -> Mounted at $mnt, running payload..."
    (
        export FF_MOUNTPOINT="$mnt"
        export FF_DEVICE="$target"
        export FF_FSTYPE="$fstype"
        export FF_UUID="$uuid"
        export FF_LABEL="$label"
        cd "$mnt" || exit 1
        timeout "${FF_PAYLOAD_TIMEOUT:-30}" "$FF_PAYLOAD"
    )
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "    -> Payload OK"
        _injected_count=$((_injected_count + 1))
    else
        echo "    -> Payload failed (rc=$rc)"
    fi
}

# btrfs subvolume injection pass
ff_inject_btrfs() {
    command -v btrfs >/dev/null 2>&1 || return
    echo "  Scanning for btrfs subvolumes..."

    for target in $(ff_all_targets); do
        [ -b "$target" ] || continue
        local fstype=""
        fstype=$(blkid "$target" 2>/dev/null | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
        [ "$fstype" = "btrfs" ] || continue

        local mnt=""
        mnt=$(ff_mount_target "$target" "btrfs")
        [ -n "$mnt" ] || continue

        # Get the default subvolume ID first
        local default_id=""
        default_id=$(btrfs subvolume get-default "$mnt" 2>/dev/null | awk '{print $2}')

        # List all subvolumes and inject into each
        btrfs subvolume list "$mnt" 2>/dev/null | while read -r line; do
            local subvol_path=""
            subvol_path=$(echo "$line" | sed 's/.* path //')
            [ -n "$subvol_path" ] || continue

            local subvol_mnt="/tmp/ff_btrfs_${target##*/}_$(echo "$subvol_path" | tr '/' '_')"
            mkdir -p "$subvol_mnt"
            if mount -t btrfs -o rw,subvol="$subvol_path" "$target" "$subvol_mnt" 2>/dev/null; then
                echo "$subvol_mnt" >> "$FF_MOUNT_LIST"
                echo "    -> btrfs subvolume: $subvol_path"
                (
                    export FF_MOUNTPOINT="$subvol_mnt"
                    export FF_DEVICE="$target"
                    export FF_FSTYPE="btrfs"
                    export FF_UUID=""
                    export FF_LABEL=""
                    cd "$subvol_mnt" || exit 1
                    timeout "${FF_PAYLOAD_TIMEOUT:-30}" "$FF_PAYLOAD"
                )
                local rc=$?
                if [ "$rc" -eq 0 ]; then
                    echo "    -> Payload OK"
                    _injected_count=$((_injected_count + 1))
                else
                    echo "    -> Payload failed (rc=$rc)"
                fi
            else
                rmdir "$subvol_mnt" 2>/dev/null || true
            fi
        done
    done
}

# ZFS dataset injection pass
ff_inject_zfs() {
    command -v zfs >/dev/null 2>&1 || return
    echo "  Scanning for ZFS datasets..."

    zfs list -H -o name,mountpoint 2>/dev/null | while IFS='	' read -r ds mountpoint; do
        [ -n "$ds" ] || continue
        # Skip datasets that are already mounted or have no mountpoint
        [ "$mountpoint" = "none" ] || [ "$mountpoint" = "legacy" ] && continue

        local zmnt="/tmp/ff_zfs_${ds##*/}"
        mkdir -p "$zmnt"
        if mount -t zfs -o rw "$ds" "$zmnt" 2>/dev/null; then
            echo "$zmnt" >> "$FF_MOUNT_LIST"
            echo "    -> ZFS dataset: $ds"
            (
                export FF_MOUNTPOINT="$zmnt"
                export FF_DEVICE="$ds"
                export FF_FSTYPE="zfs"
                export FF_UUID=""
                export FF_LABEL=""
                cd "$zmnt" || exit 1
                timeout "${FF_PAYLOAD_TIMEOUT:-30}" "$FF_PAYLOAD"
            )
            local rc=$?
            if [ "$rc" -eq 0 ]; then
                echo "    -> Payload OK"
                _injected_count=$((_injected_count + 1))
            else
                echo "    -> Payload failed (rc=$rc)"
            fi
        else
            rmdir "$zmnt" 2>/dev/null || true
        fi
    done
}

ff_inject() {
    echo "--- Injection Phase ---"
    [ -x "$FF_PAYLOAD" ] || ff_fatal "Payload script not executable: $FF_PAYLOAD"

    # Loud warning when injecting into ALL filesystems
    if [ -z "$FF_TARGET_FILTER" ] || [ "$FF_TARGET_FILTER" = "*" ]; then
        echo "[!] WARNING: No TARGET_FILTER set. Injecting into ALL detected filesystems."
        echo "    Attach only target disks or set TARGET_FILTER to limit scope."
    fi

    # Detect boot device to avoid self-injection
    local boot_dev=""
    if [ -r /proc/mounts ]; then
        boot_dev=$(awk '$2 == "/media/cdrom" || $2 == "/media/usb" {print $1}' /proc/mounts 2>/dev/null | head -1)
    fi

    # Activate complex storage before scanning
    ff_activate_lvm
    ff_activate_raid

    local _injected_count=0

    # --- Pass 1: Standard partitions, DM devices, MD arrays ---
    for target in $(ff_all_targets); do
        [ -b "$target" ] || continue

        # Skip boot device and its partitions
        if [ -n "$boot_dev" ]; then
            case "$target" in
                "$boot_dev"*) echo "  Skipping boot device: $target"; continue ;;
            esac
        fi

        ff_inject_target "$target"
    done

    # --- Pass 2: btrfs subvolumes ---
    ff_inject_btrfs

    # --- Pass 3: ZFS datasets ---
    ff_inject_zfs

    echo ""
    echo "[+] Injected into $_injected_count filesystem(s)."
    echo ""

    ff_unmount_all
}
