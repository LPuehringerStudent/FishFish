#!/bin/sh
# Injection engine: run payload on eligible filesystems

ff_inject() {
    echo "--- Injection Phase ---"
    [ -x "$FF_PAYLOAD" ] || ff_fatal "Payload script not executable: $FF_PAYLOAD"

    local injected=0

    for dev in $(ff_block_devices); do
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue

            # Identify filesystem
            local fstype=""
            local uuid=""
            local label=""
            if command -v blkid >/dev/null 2>&1; then
                fstype=$(blkid -s TYPE -o value "$target" 2>/dev/null)
                uuid=$(blkid -s UUID -o value "$target" 2>/dev/null)
                label=$(blkid -s LABEL -o value "$target" 2>/dev/null)
            fi

            # Skip unidentifiable or excluded
            [ -n "$fstype" ] || continue
            ff_in_filter "$uuid" "$label" || continue

            # Skip swap, EFI if mounted as EFI
            [ "$fstype" = "swap" ] && continue

            echo "  Target: $target ($fstype, UUID=$uuid, LABEL=$label)"

            # Mount
            local mnt=""
            mnt=$(ff_mount_target "$target" "$fstype")
            if [ -z "$mnt" ]; then
                if [ "$FF_INJECT_UNMOUNTED" != "true" ]; then
                    echo "    -> Skipped (unmountable)"
                    continue
                fi
                echo "    -> Mount failed, skipping"
                continue
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
                injected=$((injected + 1))
            else
                echo "    -> Payload failed (rc=$rc)"
            fi
        done
    done

    echo ""
    echo "[+] Injected into $injected filesystem(s)."
    echo ""

    ff_unmount_all
}
