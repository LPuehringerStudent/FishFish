#!/bin/sh
# Cleanup: unmount, log cleanup, optional trace wiping

ff_cleanup() {
    echo "--- Cleanup Phase ---"

    ff_unmount_all

    if [ "$FF_CLEAR_LOGS" = "true" ]; then
        echo "  Clearing system logs..."
        for d in /var/log /tmp /var/tmp; do
            [ -d "$d" ] && rm -rf "$d"/* 2>/dev/null || true
        done
    fi

    if [ "$FF_WIPE_TRACES" = "true" ]; then
        echo "  Wiping FishFish traces..."
        if [ -f "$FF_LOG" ]; then
            dd if=/dev/zero of="$FF_LOG" bs=1M count=1 2>/dev/null || true
            rm -f "$FF_LOG"
        fi
        rm -f /root/.ash_history /root/.bash_history 2>/dev/null || true
        rm -f /home/*/.ash_history /home/*/.bash_history 2>/dev/null || true
    fi

    echo "  Done."
    echo ""
}
