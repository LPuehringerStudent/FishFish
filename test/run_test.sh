#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISKS="$SCRIPT_DIR/disks"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"

ISO="$PROJECT_ROOT/output/FishFish-Alpine-x86_64.iso"
TIMEOUT_SEC="${1:-120}"

if [ ! -f "$ISO" ]; then
    echo "[!] ISO not found: $ISO"
    echo "    Run build.sh first."
    exit 1
fi

echo "========================================"
echo " FishFish Alpine QEMU Test"
echo "========================================"
echo " ISO: $ISO"
echo " Timeout: ${TIMEOUT_SEC}s"
echo ""

# Create test disks if they don't exist
if [ ! -f "$DISKS/ext4.img" ]; then
    echo "[+] Creating ext4 test disk..."
    dd if=/dev/zero of="$DISKS/ext4.img" bs=1M count=64 status=none
    mkfs.ext4 -F -L FISHTEST "$DISKS/ext4.img"
fi

if [ ! -f "$DISKS/vfat.img" ]; then
    echo "[+] Creating vfat test disk..."
    dd if=/dev/zero of="$DISKS/vfat.img" bs=1M count=64 status=none
    mkfs.vfat -n FISHTEST "$DISKS/vfat.img"
fi

echo "[+] Starting QEMU (ISO boot)..."
timeout "$TIMEOUT_SEC" qemu-system-x86_64 \
    -m 1024 \
    -kernel "$PROJECT_ROOT/Alpine/alpine_work/boot/vmlinuz-lts" \
    -initrd "$PROJECT_ROOT/Alpine/alpine_work/boot/initramfs-lts" \
    -cdrom "$ISO" \
    -drive file="$DISKS/ext4.img",format=raw,if=virtio \
    -drive file="$DISKS/vfat.img",format=raw,if=virtio \
    -append "modules=loop,squashfs,sd-mod,usb-storage,ahci,virtio-blk,virtio-pci,virtio,nvme console=ttyS0,38400" \
    -nographic \
    -no-reboot 2>&1 | tee "$RESULTS/serial.log" || true

echo ""
echo "[+] QEMU finished."
echo ""

# Check serial log for FishFish evidence
echo "=== Serial log (last 150 lines) ==="
tail -150 "$RESULTS/serial.log" 2>/dev/null || echo "No serial log"
echo ""

# Verify injection markers on test disks
echo "=== Verification ==="

# Check ext4
if debugfs -R 'ls /' "$DISKS/ext4.img" 2>/dev/null | grep -q INJECTION_SUCCESS; then
    echo "[OK] ext4: INJECTION_SUCCESS.txt found"
else
    echo "[FAIL] ext4: INJECTION_SUCCESS.txt NOT found"
fi

# Check vfat
if mdir -i "$DISKS/vfat.img" ::/ 2>/dev/null | grep -qi INJECTION; then
    echo "[OK] vfat: INJECTION_SUCCESS.txt found"
else
    echo "[FAIL] vfat: INJECTION_SUCCESS.txt NOT found"
fi

echo ""
echo "========================================"
