#!/bin/sh
# Probe: LVM Physical Volume detection

ff_probe_lvm() {
    echo "--- LVM Detection ---"
    found_lvm=0
    for dev in $(ff_block_devices); do
        case "$dev" in
            */fd*|*/sr*) continue ;;
        esac
        for target in "$dev" "$dev"[0-9]* "$dev"p[0-9]*; do
            [ -b "$target" ] || continue
            for offset in 512 4096; do
                label=$(dd if="$target" bs=1 count=8 skip=$offset 2>/dev/null || true)
                if [ "$label" = "LABELONE" ]; then
                    echo "  LVM PV label found on $target (offset $offset)"
                    if command -v pvs >/dev/null 2>&1; then
                        pvs "$target" 2>/dev/null | sed 's/^/    /'
                    fi
                    found_lvm=1
                    break
                fi
            done
        done
    done
    if [ "$found_lvm" -eq 0 ]; then
        echo "  No LVM PVs found."
    fi
    echo ""
}
