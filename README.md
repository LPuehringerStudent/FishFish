# FishFish

> **⚠️ DISCLAIMER: This tool is intended for authorized security testing, system administration, and forensics only. Only use FishFish on systems you own or have explicit written permission to test. Unauthorized access to computer systems is illegal in most jurisdictions.**

An Alpine Linux live-boot ISO remastered for automated filesystem discovery and payload injection.

> It doesn't actually install fish (yet) — I just liked the name.

## Quick Start

```bash
# Build the ISO (~30 sec)
./build.sh

# The ISO appears in output/FishFish-Alpine-x86_64.iso
# Test with QEMU before using on real hardware:
./test/run_test.sh
```

## Project Layout

| Path | Purpose |
|------|---------|
| `src/fishfish/payload.sh` | **Edit this:** runs once per injected filesystem |
| `src/fishfish/settings.txt` | **Edit this:** runtime flags (LUKS halt, log cleanup, etc.) |
| `src/fishfish/lib/` | Core discovery + injection libraries |
| `src/fishfish/main.sh` | Entry point orchestrating discovery → inject → cleanup |
| `build.sh` | Main orchestrator: assembles initramfs + ISO |
| `Alpine/` | Alpine Linux initramfs / ISO workspace |
| `test/` | QEMU test framework with ext4/vfat verification |
| `output/` | Final bootable ISOs |

## Payload Contract

`payload.sh` is executed once per successfully mounted target filesystem with these environment variables:

- `FF_MOUNTPOINT` — path where target is mounted
- `FF_DEVICE` — block device (e.g., `/dev/sda1`, `/dev/dm-0`)
- `FF_FSTYPE` — detected filesystem type
- `FF_UUID` — filesystem UUID
- `FF_LABEL` — filesystem label

Working directory is the root of the mounted filesystem.

Default MVP:
```sh
#!/bin/sh
touch "INJECTION_SUCCESS.txt"
```

## Settings

```ini
CLEAR_LOGS=true          # wipe logs before unmount
HALT_ON_LUKS=true        # stop if LUKS encryption detected
INJECT_UNMOUNTED=true    # attempt to mount unmounted partitions
LOG_LEVEL=verbose        # verbose | quiet
TARGET_FILTER=           # empty = all; else comma-separated UUIDs/labels
SKIP_NETWORK_PROBE=false
WIPE_TRACES=false        # overwrite fishfish.log with zeros on exit
PAYLOAD_TIMEOUT=30       # seconds per payload execution
```

## What Gets Discovered

- **Block devices**: All `/sys/block/*` and `/sys/class/block/*` devices
- **Partitions**: Standard partitions (`sdX1`, `nvme0n1p1`, etc.)
- **LVM**: Physical volumes → logical volumes (auto-activated if `lvm2` available)
- **MD RAID**: Arrays and signatures (auto-assembled if `mdadm` available)
- **Device-mapper**: `/dev/dm-*` targets (crypt, multipath, etc.)
- **Filesystems**: ext2/3/4, btrfs, xfs, vfat, ntfs3, exfat, f2fs
- **btrfs subvolumes**: Each subvolume mounted and injected individually
- **ZFS datasets**: Pools and datasets (if `zfs` tools available)
- **Encryption**: LUKS/dm-crypt headers (hard stop configurable)
- **System info**: Architecture, kernel, init system, SELinux/AppArmor, immutable root
- **Network**: Interfaces, routes, DNS (configurable skip)

## Architecture

- **Base**: Alpine Linux 3.23.4 x86_64 (standard ISO, kernel 6.18.22-0-lts)
- **Initramfs**: Remastered Alpine `initramfs-lts` with FishFish framework embedded at `/opt/fishfish/`
- **Hook**: Runs inside Alpine init, after package installation but before rootfs pivot — ensuring `/sys`, `/dev`, and `/proc` are fully available
- **Bootloaders**: Syslinux (BIOS) + GRUB2 (UEFI)
- **Boot modules**: `loop,squashfs,sd-mod,usb-storage quiet`

## Testing

```bash
# Create test disks (ext4 + vfat)
./test/create_disks.sh   # if available, or use manual dd + mkfs

# Run QEMU boot test (~60 sec)
./test/run_test.sh

# Verify injection markers on test disks
# Results printed automatically at end of test
```

## Requirements

- Linux build host with `cpio`, `gzip`, `xorriso`, `7z`
- ~500 MB free disk space for workspace + ISO output
- QEMU (optional, for testing)

## License

MIT
