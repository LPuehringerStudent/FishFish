#!/bin/sh
# Probe: LUKS / encryption detection

ff_probe_encryption() {
    echo "--- Encryption Detection ---"
    found_enc=0
    for dev in $(ff_block_devices); do
        case "$dev" in
            */fd*|*/sr*) continue ;;
        esac
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue
            magic=$(dd if="$target" bs=1 count=6 2>/dev/null || true)
            if [ "$magic" = "LUKS%BA%BE" ] || [ "$magic" = "LUKS??" ]; then
                echo "  LUKS detected on $target"
                found_enc=1
            fi
        done
    done
    if [ "$found_enc" -eq 0 ]; then
        echo "  No LUKS headers found."
    fi
    echo ""
}
