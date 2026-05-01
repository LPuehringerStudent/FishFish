# FishFish

A TinyCore Linux live-boot ISO remastered for automated filesystem discovery and payload injection — inspired by BashBunny.

## Quick Start

```bash
# Build the ISO (first run compiles kernel, subsequent runs are ~30 sec)
./build.sh

# The ISO appears in output/FishFish-<timestamp>.iso
```

## Project Layout

| Path | Purpose |
|------|---------|
| `src/payload.sh` | **Edit this:** runs once per injected filesystem |
| `src/settings.txt` | **Edit this:** runtime flags (LUKS halt, log cleanup, etc.) |
| `src/fishfish/` | Core discovery framework (rarely edited) |
| `build.sh` | Main orchestrator: assembles initrd + ISO |
| `kernel/config/` | Kernel config fragments |
| `cache/` | Cached downloads, kernel build artifacts |
| `output/` | Final bootable ISOs |

## Payload Contract

`payload.sh` is executed once per successfully mounted target filesystem with these environment variables:

- `FF_MOUNTPOINT` — path where target is mounted
- `FF_DEVICE` — block device (e.g., `/dev/sda1`)
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

- Block device topology & partition tables
- LUKS/dm-crypt headers (hard stop configurable)
- LVM physical volumes
- Software RAID (mdadm) signatures
- Filesystem types (ext4, btrfs, xfs, vfat, ntfs3, exfat, f2fs)
- btrfs subvolumes, ZFS pool signatures
- EFI system partitions
- Init system, architecture, SELinux/AppArmor status
- Immutable/readonly root detection
- Network configuration

## Architecture

- **Kernel**: Custom Linux 6.18.2 with device-mapper, dm-crypt, md-raid, btrfs, xfs built-in.
- **Initrd**: Remastered TinyCore `core.gz` with FishFish framework + userspace tools.
- **Boot**: Hooks into `/opt/bootsync.sh` for automatic execution.

## Requirements

- Linux build host with `gcc`, `make`, `cpio`, `gzip`, `xorriso`, `7z`
- ~20 GB free disk space for first kernel build
- ~30 GB RAM recommended for parallel compilation

## License

MIT
