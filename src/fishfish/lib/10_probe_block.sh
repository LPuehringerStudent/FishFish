#!/bin/sh
# Probe: Block device topology and partition tables

ff_probe_block() {
    echo "--- Block Device Topology ---"
    for dev in $(ff_block_devices); do
        echo ""
        echo "Device: $dev"
        if [ -r "$dev" ]; then
            size_bytes=$(cat "/sys/block/${dev##*/}/size" 2>/dev/null)
            size_mb=$((size_bytes * 512 / 1024 / 1024))
            echo "  Size: ${size_mb} MiB"
            if command -v fdisk >/dev/null 2>&1; then
                fdisk -l "$dev" 2>/dev/null | grep -E 'Disklabel type|Disk identifier' | sed 's/^/  /'
            fi
            if command -v parted >/dev/null 2>&1; then
                parted -s "$dev" print 2>/dev/null | head -10 | sed 's/^/  /'
            fi
            for p in /sys/block/${dev##*/}/*/dev; do
                [ -f "$p" ] || continue
                pdir="${p%/*}"
                pname="${pdir##*/}"
                psize=$(cat "$pdir/size" 2>/dev/null)
                psize_mb=$((psize * 512 / 1024 / 1024))
                echo "  Partition: /dev/$pname (${psize_mb} MiB)"
            done
        else
            echo "  (not readable)"
        fi
    done
    echo ""
}
