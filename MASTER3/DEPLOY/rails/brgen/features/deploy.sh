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
daemon="/usr/local/bin/falcon"
daemon_flags="serve -b tcp://127.0.0.1:11006"
daemon_timeout="60"

. /etc/rc.d/rc.subr
pexp="falcon serve.*11006"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCSH

doas install -m 755 /tmp/brgen /etc/rc.d/brgen
doas rcctl enable brgen

echo "==> [deploy] rc.d service installed. Start with: doas rcctl start brgen"
