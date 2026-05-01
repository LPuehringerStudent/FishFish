#!/bin/sh
# FishFish QEMU Test Runner
# Usage: ./test/run_test.sh [basic|luks|all] [timeout_seconds]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISKS="$SCRIPT_DIR/disks"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"

SCENARIO="${1:-basic}"
TIMEOUT_SEC="${2:-60}"

# Find latest build artifacts
KERNEL="$PROJECT_ROOT/build/iso_root/boot/vmlinuz"
INITRD="$PROJECT_ROOT/build/iso_root/boot/core.gz"

if [ ! -f "$KERNEL" ] || [ ! -f "$INITRD" ]; then
    echo "[!] Kernel or initrd not found. Run ./build.sh first."
    exit 1
fi

if [ ! -f "$DISKS/ext4.img" ] || [ ! -f "$DISKS/vfat.img" ]; then
    echo "[!] Test disks missing. Run ./test/create_disks.sh first."
    exit 1
fi

echo "========================================"
echo " FishFish Test Runner"
echo "========================================"
echo "Scenario: $SCENARIO"
echo "Timeout: ${TIMEOUT_SEC}s"
echo ""

# Clean previous results
rm -f "$RESULTS"/*

# Assemble QEMU drive arguments
DRIVES=""
DRIVES="$DRIVES -drive file=$DISKS/ext4.img,format=raw,if=virtio"
DRIVES="$DRIVES -drive file=$DISKS/vfat.img,format=raw,if=virtio"

if [ "$SCENARIO" = "luks" ] || [ "$SCENARIO" = "all" ]; then
    if [ ! -f "$DISKS/luks.img" ]; then
        echo "[!] LUKS disk missing. Run ./test/create_disks.sh first."
        exit 1
    fi
    DRIVES="$DRIVES -drive file=$DISKS/luks.img,format=raw,if=virtio"
fi

# --- Boot QEMU ---
echo "[+] Booting QEMU (direct kernel mode)..."
timeout "$TIMEOUT_SEC" qemu-system-x86_64 \
    -m 512 \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    $DRIVES \
    -append "loglevel=3 console=ttyS0,38400" \
    -display none \
    -no-reboot \
    -serial file:"$RESULTS/serial.log" \
    > "$RESULTS/qemu_stdout.log" 2>&1 || true

echo "[+] QEMU finished."
echo ""

# --- Verify results ---
echo "=== Verification ==="
echo ""

PASS=0
FAIL=0

# Check ext4
if debugfs -R 'stat /INJECTION_SUCCESS.txt' "$DISKS/ext4.img" 2>/dev/null | grep -q 'Inode:'; then
    echo "  [PASS] ext4    : INJECTION_SUCCESS.txt found"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] ext4    : INJECTION_SUCCESS.txt NOT found"
    FAIL=$((FAIL + 1))
fi

# Check vfat
if mcopy -i "$DISKS/vfat.img" ::/INJECTION_SUCCESS.txt "$RESULTS/vfat_injection.txt" 2>/dev/null; then
    echo "  [PASS] vfat    : INJECTION_SUCCESS.txt found"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] vfat    : INJECTION_SUCCESS.txt NOT found"
    FAIL=$((FAIL + 1))
fi

# LUKS-specific checks
if [ "$SCENARIO" = "luks" ] || [ "$SCENARIO" = "all" ]; then
    # With HALT_ON_LUKS=true, injection should NOT happen on any disk
    # because the script exits on LUKS detection
    if [ "$FAIL" -eq 0 ]; then
        echo "  [FAIL] luks    : Injection succeeded despite LUKS presence (HALT_ON_LUKS expected)"
        FAIL=$((FAIL + 1))
    else
        echo "  [PASS] luks    : Injection halted as expected (no files on ext4/vfat)"
        PASS=$((PASS + 1))
    fi
    # Verify LUKS disk was not modified
    if debugfs -R 'stat /INJECTION_SUCCESS.txt' "$DISKS/luks.img" 2>/dev/null | grep -q 'Inode:'; then
        echo "  [FAIL] luks    : LUKS disk was incorrectly modified"
        FAIL=$((FAIL + 1))
    else
        echo "  [PASS] luks    : LUKS disk untouched"
        PASS=$((PASS + 1))
    fi
fi

# Check serial log for boot evidence
if grep -q 'Booting.*Core' "$RESULTS/serial.log" 2>/dev/null; then
    echo "  [PASS] boot    : System reached Core boot stage"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] boot    : No evidence of successful boot in serial log"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
echo "Results saved to: $RESULTS/"
echo "  - serial.log      : Full serial console capture"
echo "  - qemu_stdout.log : QEMU process output"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
