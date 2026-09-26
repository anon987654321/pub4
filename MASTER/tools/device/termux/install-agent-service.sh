#!/data/data/com.termux/files/usr/bin/sh
set -eu

ROOT=${MASTER_ROOT:-$HOME/pub4/MASTER}
SERVICE=$PREFIX/var/service/master-agent
RUN=$SERVICE/run
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

if command -v sv-enable >/dev/null 2>&1; then
  sv-enable master-agent
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
echo 'device-agent0: boot hook: $BOOT'
echo 'device-agent0: stop with sv down master-agent; disable with sv-disable master-agent'
