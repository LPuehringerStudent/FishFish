#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$PROJECT_ROOT/Alpine/alpine_work"
CONFIGS_DIR="$PROJECT_ROOT/Alpine/configs"
OUTPUT_DIR="$PROJECT_ROOT/output"
ISO_NAME="${1:-$OUTPUT_DIR/FishFish-Alpine-x86_64.iso}"

echo "========================================"
echo " FishFish Alpine ISO Builder"
echo "========================================"
echo ""

mkdir -p "$OUTPUT_DIR"

# Copy tracked bootloader configs into workspace
if [ -d "$CONFIGS_DIR" ]; then
    echo "[+] Copying bootloader configs..."
    cp "$CONFIGS_DIR/syslinux.cfg" "$WORK_DIR/boot/syslinux/syslinux.cfg"
    cp "$CONFIGS_DIR/grub.cfg"     "$WORK_DIR/boot/grub/grub.cfg"
fi

cd "$WORK_DIR"

# Boot images for isohybrid
BOOT_IMG1="[BOOT]/1-Boot-NoEmul.img"
BOOT_IMG2="[BOOT]/2-Boot-NoEmul.img"

if [ ! -f "$BOOT_IMG1" ] || [ ! -f "$BOOT_IMG2" ]; then
    echo "[!] Boot images not found"
    echo "    Ensure Alpine/alpine_work/ contains the extracted Alpine ISO contents."
    exit 1
fi

echo "[+] Building ISO: $ISO_NAME"
xorrisofs -o "$ISO_NAME" \
    -V "FishFish-Alpine" \
    -A "FishFish/Alpine" \
    -J -joliet-long -R -D \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -b boot/syslinux/isolinux.bin \
    -c boot/syslinux/boot.cat \
    -isohybrid-mbr "$BOOT_IMG1" \
    -partition_cyl_align on \
    -partition_offset 0 \
    -partition_hd_cyl 64 \
    -partition_sec_hd 32 \
    --mbr-force-bootable \
    -iso_mbr_part_type 0x00 \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    .

echo ""
echo "[+] ISO built successfully: $ISO_NAME"
ls -lh "$ISO_NAME"
echo ""
echo "========================================"
