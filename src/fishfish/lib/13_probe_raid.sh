#!/bin/sh
# Probe: MD RAID detection

ff_probe_raid() {
    echo "--- RAID Detection ---"
    found_raid=0

    # Scan raw devices for MD signatures
    for dev in $(ff_block_devices); do
        case "$dev" in
            */fd*|*/sr*) continue ;;
        esac
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue
            magic=$(timeout 3 dd if="$target" bs=1 count=4 skip=4096 2>/dev/null || true)
            if [ "$magic" = "MDRAID" ] || [ "$magic" = "mdra" ]; then
                echo "  MD RAID signature on $target"
                found_raid=1
            fi
        done
    done

    # Scan assembled MD arrays
    for md in /dev/md[0-9]* /dev/md_*; do
        [ -b "$md" ] || continue
        echo "  MD array: $md"
        if command -v mdadm >/dev/null 2>&1; then
            mdadm --detail "$md" 2>/dev/null | grep -E 'Raid Level|Array Size|State' | sed 's/^/    /'
        fi
        found_raid=1
    done

    # Also scan /sys/block/md*
    for md in /sys/block/md* /sys/class/block/md*; do
        [ -e "$md" ] || continue
        name="${md##*/}"
        echo "  MD array (sysfs): /dev/$name"
        found_raid=1
    done

    if [ "$found_raid" -eq 0 ]; then
        echo "  No RAID signatures or arrays found."
    fi
    echo ""
}
