#!/bin/sh
# Probe: init system, architecture, SELinux/AppArmor, immutable root

ff_probe_system() {
    echo "--- System Metadata ---"
    echo "  Architecture: $(uname -m)"
    echo "  Kernel: $(uname -r)"

    # Init system
    if [ -L /sbin/init ]; then
        init_target=$(readlink /sbin/init 2>/dev/null)
        echo "  Init system: $init_target"
    else
        if [ -f /sbin/init ]; then
            # Could be sysvinit, runit, etc.
            echo "  Init system: /sbininit (traditional)"
        fi
    fi
    if [ -d /run/systemd/system ]; then
        echo "  Init system: systemd"
    fi

    # SELinux
    if [ -d /sys/fs/selinux ] && [ -f /sys/fs/selinux/enforce ]; then
        enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null)
        [ "$enforce" = "1" ] && echo "  SELinux: Enforcing" || echo "  SELinux: Permissive/Disabled"
    else
        echo "  SELinux: Not present"
    fi

    # AppArmor
    if [ -d /sys/kernel/security/apparmor ]; then
        aa_profile=$(cat /sys/kernel/security/apparmor/profiles 2>/dev/null | head -1)
        [ -n "$aa_profile" ] && echo "  AppArmor: Active ($aa_profile ...)" || echo "  AppArmor: Present but no profiles"
    else
        echo "  AppArmor: Not present"
    fi

    # Immutable / readonly root
    if command -v lsattr >/dev/null 2>&1; then
        attr=$(lsattr -d / 2>/dev/null | awk '{print $1}')
        case "$attr" in
            *i*) echo "  Root FS: Immutable flag (i) set" ;;
            *)   echo "  Root FS: No immutable flag" ;;
        esac
    fi
    if [ -f /proc/mounts ]; then
        root_opts=$(awk '$2 == "/" {print $4}' /proc/mounts)
        case "$root_opts" in
            *ro*) echo "  Root FS: Mounted read-only" ;;
            *)    echo "  Root FS: Mounted read-write" ;;
        esac
    fi

    # EFI System Partition detection
    for part in $(ff_partitions); do
        type=$(blkid -s TYPE -o value "$part" 2>/dev/null)
        [ "$type" = "vfat" ] || continue
        # Check for EFI directory
        tmpmnt="/tmp/ff_efi_$$"
        mkdir -p "$tmpmnt"
        if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
            if [ -d "$tmpmnt/EFI" ]; then
                echo "  EFI System Partition: $part"
            fi
            umount "$tmpmnt" 2>/dev/null || true
        fi
        rmdir "$tmpmnt" 2>/dev/null || true
    done

    echo ""
}
