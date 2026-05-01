#!/bin/sh
# FishFish Test Disk Creator
# Generates raw filesystem images for QEMU testing

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISKS="$SCRIPT_DIR/disks"
mkdir -p "$DISKS"

echo "[+] Creating test disks in $DISKS"

# --- ext4 disk ---
if [ ! -f "$DISKS/ext4.img" ]; then
    echo "  -> ext4.img (50 MB)"
    qemu-img create -f raw "$DISKS/ext4.img" 50M >/dev/null
    mkfs.ext4 -F -q "$DISKS/ext4.img"
else
    echo "  -> ext4.img already exists, skipping"
fi

# --- vfat disk ---
if [ ! -f "$DISKS/vfat.img" ]; then
    echo "  -> vfat.img (30 MB)"
    qemu-img create -f raw "$DISKS/vfat.img" 30M >/dev/null
    mkfs.vfat -F 32 "$DISKS/vfat.img" >/dev/null
else
    echo "  -> vfat.img already exists, skipping"
fi

# --- LUKS-encrypted disk ---
if [ ! -f "$DISKS/luks.img" ]; then
    echo "  -> luks.img (30 MB, encrypted)"
    qemu-img create -f raw "$DISKS/luks.img" 30M >/dev/null
    # Create LUKS container without needing a loop device
    # cryptsetup luksFormat works on regular files
    echo "testpass" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "$DISKS/luks.img" -
else
    echo "  -> luks.img already exists, skipping"
fi

echo "[+] Done."
echo ""
echo "Disks:"
ls -lh "$DISKS"/
