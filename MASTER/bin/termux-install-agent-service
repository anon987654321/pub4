#!/data/data/com.termux/files/usr/bin/sh
set -eu

ROOT=${MASTER_ROOT:-$HOME/pub4/MASTER}
SERVICE=$PREFIX/var/service/master-agent
WAKE_SERVICE=$PREFIX/var/service/master-wake
RUN=$SERVICE/run
WAKE_RUN=$WAKE_SERVICE/run
BOOT=$HOME/.termux/boot/start-master-services

command -v sv-enable >/dev/null 2>&1 || {
  echo 'device-agent0: termux-services missing — pkg install termux-services'
  exit 1
}
test -d "$ROOT" || {
  echo "device-agent0: MASTER checkout missing: $ROOT"
  exit 1
}

mkdir -p "$SERVICE"
cat > "$RUN" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
set -eu
cd "$ROOT"
exec bundle exec ruby bin/device-agent
EOF
chmod 700 "$RUN"

mkdir -p "$WAKE_SERVICE"
cat > "$WAKE_RUN" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
set -eu
cd "$ROOT"
exec bundle exec ruby bin/device-wake
EOF
chmod 700 "$WAKE_RUN"

if command -v sv-enable >/dev/null 2>&1; then
  sv-enable master-agent
  sv-enable master-wake
fi

mkdir -p "$(dirname "$BOOT")"
cat > "$BOOT" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
set -eu
termux-wake-lock
export SVDIR=\$PREFIX/var/service
export LOGDIR=\$PREFIX/var/log
source \$PREFIX/etc/profile.d/start-services.sh
EOF
chmod 700 "$BOOT"

echo 'device-agent0: installed master-agent service'
echo 'device-agent0: logs: $PREFIX/var/log/sv/master-agent/current'
echo 'device-agent0: wake logs: $PREFIX/var/log/sv/master-wake/current'
echo 'device-agent0: wake is OFF until /wake on is explicitly enabled'
echo 'device-agent0: boot hook: $BOOT'
echo 'device-agent0: stop with sv down master-agent; disable with sv-disable master-agent'
