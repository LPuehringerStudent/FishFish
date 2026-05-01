#!/bin/sh
# Probe: Network configuration

ff_probe_network() {
    echo "--- Network Configuration ---"
    if command -v ip >/dev/null 2>&1; then
        echo "  Interfaces:"
        ip -brief addr 2>/dev/null | sed 's/^/    /'
    elif command -v ifconfig >/dev/null 2>&1; then
        echo "  Interfaces:"
        ifconfig -a 2>/dev/null | grep -E '^[a-z]' | sed 's/^/    /'
    fi

    echo "  Routes:"
    if command -v ip >/dev/null 2>&1; then
        ip route 2>/dev/null | sed 's/^/    /'
    fi

    echo "  DNS:"
    if [ -f /etc/resolv.conf ]; then
        grep nameserver /etc/resolv.conf 2>/dev/null | sed 's/^/    /'
    fi

    echo "  Hostname: $(cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || echo 'unknown')"
    echo ""
}
