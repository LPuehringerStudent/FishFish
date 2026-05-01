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
        # strip comments and whitespace
        val="${val%%#*}"
        val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        eval "FF_$(echo "$key" | tr '[:lower:]' '[:upper:]')='$val'"
    done < "$FF_SETTINGS"
}

ff_block_devices() {
    # List real block devices (not partitions, not loops, not zram)
    for dev in /sys/block/*; do
        name="${dev##*/}"
        case "$name" in
            loop*|ram*|zram*|fd*) continue ;;
        esac
        echo "/dev/$name"
    done
}

ff_partitions() {
    # List all partition block devices
    for part in /sys/block/*/dev /sys/block/*/*/dev; do
        [ -f "$part" ] || continue
        dir="${part%/*}"
        name="${dir##*/}"
        case "$name" in
            loop*|ram*|zram*|fd*) continue ;;
        esac
        # skip whole disks (no slash in path after /sys/block/)
        case "$dir" in
            /sys/block/*/*) echo "/dev/$name" ;;
        esac
    done
}

ff_in_filter() {
    local uuid="$1" label="$2"
    [ -n "$FF_TARGET_FILTER" ] || return 0
    case ",$FF_TARGET_FILTER," in
        *,"$uuid",*) return 0 ;;
        *,"$label",*) return 0 ;;
        *) return 1 ;;
    esac
}
