#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
typeset -r PORT=11006

echo "==> [deploy] OpenBSD rc.d + Falcon service"
cd "$APP_DIR"

cat > /tmp/brgen_rc << 'RCSH'
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://0.0.0.0:11006"
daemon_user="brgen"
daemon_execdir="/home/brgen/app"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*brgen.*falcon"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCSH

doas install -m 555 /tmp/brgen_rc /etc/rc.d/brgen
doas rcctl enable brgen

echo "==> [deploy] run migrations"
doas -u brgen sh -c "cd ${APP_DIR} && RAILS_ENV=production bundle exec rails db:migrate"

echo "==> [deploy] start service"
doas rcctl start brgen

echo "==> [deploy] done. brgen serving on port ${PORT}"
