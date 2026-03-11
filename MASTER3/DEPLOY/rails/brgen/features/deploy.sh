#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
typeset -r PORT=11006

echo "==> [deploy] OpenBSD rc.d service"
cd "$APP_DIR"

cat > /tmp/brgen << 'RCSH'
#!/bin/ksh

daemon_user="brgen"
daemon_execdir="/home/brgen/app"
daemon="/home/brgen/app/bin/rails"
daemon_flags="server -b 0.0.0.0 -p 11006 -e production"
daemon_timeout="60"

. /etc/rc.d/rc.subr
pexp="ruby.*bin/rails server.*-p 11006"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCSH

doas install -m 755 /tmp/brgen /etc/rc.d/brgen
doas rcctl enable brgen

echo "==> [deploy] rc.d service installed. Start with: doas rcctl start brgen"
