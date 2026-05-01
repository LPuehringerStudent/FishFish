#!/bin/sh
# Probe: MD RAID detection

ff_probe_raid() {
    echo "--- RAID Detection ---"
    found_raid=0
    for dev in $(ff_block_devices); do
        case "$dev" in
            */fd*|*/sr*) continue ;;
        esac
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue
            magic=$(dd if="$target" bs=1 count=4 skip=4096 2>/dev/null || true)
            if [ "$magic" = "MDRAID" ] || [ "$magic" = "mdra" ]; then
                echo "  MD RAID signature on $target"
                found_raid=1
            fi
        done
    done
    if [ "$found_raid" -eq 0 ]; then
        echo "  No RAID signatures found."
    fi
    echo ""
}
