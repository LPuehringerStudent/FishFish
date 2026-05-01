#!/bin/sh
# FishFish Build Orchestrator
# Usage: ./build.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$PROJECT_ROOT/cache"
BUILD="$PROJECT_ROOT/build"
OUTPUT="$PROJECT_ROOT/output"
SRC="$PROJECT_ROOT/src"
KERNEL_CACHE="$CACHE/kernel"
INITRD_BASE="$CACHE/initrd_base"
TCZ_MERGED="$CACHE/tcz_merged"
ISO_EXTRACT="$CACHE/iso_extract"

mkdir -p "$BUILD/initrd_work" "$BUILD/iso_root" "$OUTPUT"

echo "========================================"
echo " FishFish ISO Builder"
echo "========================================"
echo ""

# --- Phase 1: Kernel ---
KERNEL_BZIMAGE="$KERNEL_CACHE/linux-6.18.2/arch/x86/boot/bzImage"
KERNEL_MODULES="$KERNEL_CACHE/linux-6.18.2/modules_install"

if [ ! -f "$KERNEL_BZIMAGE" ]; then
    echo "[!] Kernel not built yet. Please build it first:"
    echo "    cd cache/kernel/linux-6.18.2 && make -j\$(nproc) bzImage modules"
    echo "    Then re-run this script."
    exit 1
fi

echo "[+] Using kernel: $KERNEL_BZIMAGE"

# --- Phase 2: Assemble initrd ---
echo "[+] Assembling initrd..."

# Copy base initrd
rm -rf "$BUILD/initrd_work"
cp -a "$INITRD_BASE" "$BUILD/initrd_work"

# Optional: install essential kernel modules (not all — keeps initrd small)
KVER="$(make -s -C "$KERNEL_CACHE/linux-6.18.2" kernelrelease 2>/dev/null || echo '6.18.2-fishfish')"
MODULES_DIR="$BUILD/initrd_work/lib/modules/$KVER"
mkdir -p "$MODULES_DIR"
if [ ! -d "$KERNEL_MODULES/lib/modules/$KVER" ]; then
    echo "[+] Installing kernel modules..."
    make -C "$KERNEL_CACHE/linux-6.18.2" modules_install INSTALL_MOD_PATH="$KERNEL_CACHE/linux-6.18.2/modules_install" >/dev/null 2>&1
fi
if [ -d "$KERNEL_MODULES/lib/modules/$KVER" ]; then
    # Only copy essential modules to keep initrd small
    # Everything critical (DM, CRYPT, RAID, BTRFS, XFS, ext4, vfat, ntfs3) is built-in (=y)
    # We only need block device and network drivers as modules
    echo "[+] Copying essential modules only..."
    for moddir in kernel/drivers/block kernel/drivers/nvme kernel/drivers/scsi kernel/drivers/ata kernel/drivers/net kernel/drivers/virtio kernel/drivers/usb/storage kernel/fs; do
        if [ -d "$KERNEL_MODULES/lib/modules/$KVER/$moddir" ]; then
            mkdir -p "$MODULES_DIR/$moddir"
            cp -a "$KERNEL_MODULES/lib/modules/$KVER/$moddir"/* "$MODULES_DIR/$moddir/" 2>/dev/null || true
        fi
    done
    # Copy modules.dep and other metadata
    cp -a "$KERNEL_MODULES/lib/modules/$KVER"/modules.* "$MODULES_DIR/" 2>/dev/null || true
fi

# Merge .tcz tools into initrd
cp -a "$TCZ_MERGED"/* "$BUILD/initrd_work/" 2>/dev/null || true

# Update library paths: ensure /usr/local/lib is in ld path
mkdir -p "$BUILD/initrd_work/etc"
if [ -f "$BUILD/initrd_work/etc/ld.so.conf" ]; then
    if ! grep -q '/usr/local/lib' "$BUILD/initrd_work/etc/ld.so.conf"; then
        echo '/usr/local/lib' >> "$BUILD/initrd_work/etc/ld.so.conf"
    fi
else
    echo '/usr/local/lib' > "$BUILD/initrd_work/etc/ld.so.conf"
fi

# Install FishFish framework
mkdir -p "$BUILD/initrd_work/opt/fishfish/lib"
mkdir -p "$BUILD/initrd_work/opt/fishfish/hooks"
cp -a "$SRC/fishfish/lib"/* "$BUILD/initrd_work/opt/fishfish/lib/"
cp -a "$SRC/fishfish/hooks"/* "$BUILD/initrd_work/opt/fishfish/hooks/"
cp -a "$SRC/fishfish/main.sh" "$BUILD/initrd_work/opt/fishfish/main.sh"
cp "$SRC/payload.sh" "$BUILD/initrd_work/opt/fishfish/payload.sh"
cp "$SRC/settings.txt" "$BUILD/initrd_work/opt/fishfish/settings.txt"
chmod +x "$BUILD/initrd_work/opt/fishfish/main.sh"
chmod +x "$BUILD/initrd_work/opt/fishfish/payload.sh"

# Hook into bootlocal.sh (runs later, after udev settles)
BOOTLOCAL="$BUILD/initrd_work/opt/bootlocal.sh"
if ! grep -q 'fishfish/main.sh' "$BOOTLOCAL"; then
    echo '' >> "$BOOTLOCAL"
    echo '# FishFish auto-run' >> "$BOOTLOCAL"
    echo '# Ensure virtio block devices are available' >> "$BOOTLOCAL"
    echo 'modprobe virtio_pci 2>/dev/null || true' >> "$BOOTLOCAL"
    echo 'modprobe virtio_blk 2>/dev/null || true' >> "$BOOTLOCAL"
    echo 'for i in 1 2 3 4 5 6 7 8 9 10; do' >> "$BOOTLOCAL"
    echo '    [ -e /dev/vda ] || [ -e /dev/sda ] || [ -e /dev/nvme0 ] && break' >> "$BOOTLOCAL"
    echo '    sleep 1' >> "$BOOTLOCAL"
    echo 'done' >> "$BOOTLOCAL"
    echo 'sleep 1' >> "$BOOTLOCAL"
    echo '/opt/fishfish/main.sh >> /tmp/fishfish.log 2>&1' >> "$BOOTLOCAL"
    echo 'sync' >> "$BOOTLOCAL"
    echo 'poweroff -f' >> "$BOOTLOCAL"
fi

# Ensure payload timeout utility exists (busybox timeout)
if ! command -v timeout >/dev/null 2>&1; then
    # Some busybox builds have it as applet
    ln -sf /bin/busybox "$BUILD/initrd_work/usr/bin/timeout" 2>/dev/null || true
fi

# Set library path for tcz binaries in bootlocal.sh (so FishFish can find .tcz libraries)
if ! grep -q 'LD_LIBRARY_PATH' "$BOOTLOCAL"; then
    echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> "$BOOTLOCAL"
fi

# Ensure serial console device exists (for output redirection)
[ -e "$BUILD/initrd_work/dev/ttyS0" ] || fakeroot mknod "$BUILD/initrd_work/dev/ttyS0" c 4 64

# --- Phase 3: Assemble ISO ---
echo "[+] Assembling ISO root..."

# Copy ISO base
rm -rf "$BUILD/iso_root"
mkdir -p "$BUILD/iso_root/boot"
rsync -a "$ISO_EXTRACT/" "$BUILD/iso_root/" --exclude='[BOOT]' 2>/dev/null || cp -a "$ISO_EXTRACT"/* "$BUILD/iso_root/" 2>/dev/null || true

# Repack core.gz with root ownership
echo "[+] Repacking core.gz..."
cd "$BUILD/initrd_work"
fakeroot sh -c 'find . | cpio -o -H newc 2>/dev/null | gzip -9' > "$BUILD/iso_root/boot/core.gz"

# Replace kernel
cp "$KERNEL_BZIMAGE" "$BUILD/iso_root/boot/vmlinuz"

# Ensure isolinux files exist
if [ ! -f "$BUILD/iso_root/boot/isolinux/isolinux.bin" ]; then
    ff_fatal "ISOLINUX files missing in ISO root"
fi

# Build ISO
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ISO_NAME="FishFish-${TIMESTAMP}.iso"

cd "$BUILD/iso_root"
xorriso -as mkisofs \
    -V 'FishFish' \
    -J -R \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o "$OUTPUT/$ISO_NAME" \
    . 2>&1 | tail -5

echo ""
echo "[+] Build complete: $OUTPUT/$ISO_NAME"
echo "[+] Size: $(du -h "$OUTPUT/$ISO_NAME" | cut -f1)"
