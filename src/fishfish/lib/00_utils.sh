#!/bin/sh
# FishFish Utilities + Settings Parser

FF_BASE="/opt/fishfish"
FF_SETTINGS="$FF_BASE/settings.txt"
FF_PAYLOAD="$FF_BASE/payload.sh"
FF_LOG="/tmp/fishfish.log"

ff_log() {
    if [ "$FF_LOG_LEVEL" = "verbose" ]; then
        echo "[$(date '+%H:%M:%S')] $*"
    fi
}

ff_warn() {
    echo "[!] $*" >&2
}

ff_fatal() {
    echo "[FATAL] $*" >&2
    exit 1
}

ff_parse_settings() {
    [ -f "$FF_SETTINGS" ] || return
    while IFS='=' read -r key val; do
        case "$key" in
            \#*|""|*\ *) continue ;;
        esac
        val="${val%%#*}"
        val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        eval "FF_$(echo "$key" | tr '[:lower:]' '[:upper:]')='$val'"
    done < "$FF_SETTINGS"
}

ff_block_devices() {
    local found=0
    if [ -d /sys/block ]; then
        for dev in /sys/block/*; do
            name="${dev##*/}"
            case "$name" in
                loop*|ram*|zram*|fd*) continue ;;
            esac
            echo "/dev/$name"
            found=1
        done
    fi
    if [ "$found" -eq 0 ] && [ -d /sys/class/block ]; then
        for dev in /sys/class/block/*; do
            name="${dev##*/}"
            case "$name" in
                loop*|ram*|zram*|fd*) continue ;;
            esac
            echo "/dev/$name"
        done
    fi
}

ff_partitions() {
    for part in /sys/block/*/dev /sys/block/*/*/dev /sys/class/block/*/dev /sys/class/block/*/*/dev; do
        [ -f "$part" ] || continue
        dir="${part%/*}"
        name="${dir##*/}"
        case "$name" in
            loop*|ram*|zram*|fd*) continue ;;
        esac
        case "$dir" in
            /sys/block/*/*|/sys/class/block/*/*) echo "/dev/$name" ;;
        esac
    done
}

# Return all injectable targets: raw block devices + partitions + dm devices + md arrays
ff_all_targets() {
    # Raw block devices (for filesystems directly on disk, no partitions)
    ff_block_devices

    # Standard partitions
    ff_partitions

    # Device-mapper devices (LVM LVs, cryptsetup, multipath, etc.)
    for dm in /sys/block/dm-* /sys/class/block/dm-*; do
        [ -e "$dm" ] || continue
        name="${dm##*/}"
        echo "/dev/$name"
    done

    # MD RAID arrays
    for md in /dev/md[0-9]* /dev/md_*; do
        [ -b "$md" ] || continue
        echo "$md"
    done
}

ff_in_filter() {
    uuid="$1"
    label="$2"
    [ -n "$FF_TARGET_FILTER" ] || return 0
    # TARGET_FILTER=* means inject into ALL filesystems
    [ "$FF_TARGET_FILTER" = "*" ] && return 0
    case ",$FF_TARGET_FILTER," in
        *,"$uuid",*) return 0 ;;
        *,"$label",*) return 0 ;;
        *) return 1 ;;
    esac
}

# Extract a field from blkid output. Works with both util-linux and busybox blkid.
ff_blkid_field() {
    dev="$1"
    field="$2"
    val=""

    # Try util-linux style first
    val=$(blkid -s "$field" -o value "$dev" 2>/dev/null)

    # If empty or looks like full blkid output (contains = or :), parse with sed
    if [ -z "$val" ] || [ "${val#*=}" != "$val" ] || [ "${val#*:}" != "$val" ]; then
        val=$(blkid "$dev" 2>/dev/null | sed -n "s/.*${field}=\"\([^\"]*\)\".*/\1/p")
    fi

    echo "$val"
}
