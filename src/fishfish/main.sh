#!/bin/sh
# FishFish Main Orchestrator

FF_BASE="/opt/fishfish"
FF_LOG="/tmp/fishfish.log"

# Redirect all output to log and console
exec > >(tee "$FF_LOG" /dev/console) 2>&1

echo "========================================"
echo " FishFish Boot-time Discovery + Inject"
echo "========================================"
echo ""

# Source libraries
for lib in "$FF_BASE"/lib/*.sh; do
    [ -f "$lib" ] && . "$lib"
done

# Parse settings
ff_parse_settings

echo "[+] Settings loaded."
echo ""

# --- Discovery Phase ---
ff_probe_block
ff_probe_encryption
ff_probe_lvm
ff_probe_raid
ff_probe_filesystems
ff_probe_system
[ "$FF_SKIP_NETWORK_PROBE" = "true" ] || ff_probe_network

echo ""
echo "[+] Discovery complete."
echo ""

# --- Pre-inject hook ---
if [ -x "$FF_BASE/hooks/pre-inject.sh" ]; then
    echo "[+] Running pre-inject hook..."
    "$FF_BASE/hooks/pre-inject.sh"
fi

# --- Injection Phase ---
ff_inject

# --- Cleanup Phase ---
ff_cleanup

echo ""
echo "[+] FishFish finished."
