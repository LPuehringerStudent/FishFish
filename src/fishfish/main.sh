#!/bin/sh
# FishFish Main Orchestrator

FF_BASE="/opt/fishfish"

# Source libraries
for lib in "$FF_BASE"/lib/*.sh; do
    [ -f "$lib" ] && . "$lib"
done

# Parse settings
ff_parse_settings

# --- Discovery Phase ---
echo "========================================"
echo " FishFish Boot-time Discovery + Inject"
echo "========================================"
echo ""

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

# --- Encryption halt check ---
if [ "$FF_LUKS_FOUND" = "1" ] && [ "$FF_HALT_ON_LUKS" = "true" ]; then
    echo "[!] HALT: LUKS encryption detected. Aborting injection."
    echo ""
    ff_cleanup
    echo "[+] FishFish finished (halted)."
    exit 0
fi

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
