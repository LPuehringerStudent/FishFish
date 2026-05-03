#!/bin/sh
# Probe: LVM Physical Volume and Logical Volume detection

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
                label=$(timeout 3 dd if="$target" bs=1 count=8 skip=$offset 2>/dev/null || true)
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

    # List all logical volumes if lvs is available
    if command -v lvs >/dev/null 2>&1; then
        local lv_count
        lv_count=$(lvs --noheadings 2>/dev/null | wc -l | tr -d ' ')
        if [ "$lv_count" -gt 0 ] 2>/dev/null; then
            echo "  Logical Volumes:"
            lvs --noheadings -o lv_name,vg_name,lv_size 2>/dev/null | sed 's/^/    /'
            found_lvm=1
        fi
    fi

    # Also scan /dev/mapper/ for DM devices
    for dm in /dev/mapper/*; do
        [ -L "$dm" ] || continue
        case "$dm" in
            */control) continue ;;
        esac
        echo "  DM device: $dm -> $(readlink "$dm" 2>/dev/null)"
        found_lvm=1
    done

    if [ "$found_lvm" -eq 0 ]; then
        echo "  No LVM PVs or DM devices found."
    fi
    echo ""
}
