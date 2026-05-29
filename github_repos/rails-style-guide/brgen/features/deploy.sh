#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
APP_DIR="/home/brgen/app"
PORT=11006
RC_NAME="brgen"
RC_FILE="/etc/rc.d/${RC_NAME}"
TMP_RC="$(mktemp -t "${RC_NAME}.rc.XXXXXX")"

#--- Helpers -----------------------------------------------------------------
err() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -f "${TMP_RC}"
}
trap cleanup EXIT INT TERM

#--- Preconditions -----------------------------------------------------------
[ -d "${APP_DIR}" ] || err "application directory ${APP_DIR} does not exist"
command -v doas >/dev/null 2>&1 || err "'doas' not found – required for privileged actions"

#--- Build rc.d script --------------------------------------------------------
cat > "${TMP_RC}" <<'EOF'
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://0.0.0.0:${PORT}"
daemon_user="brgen"
daemon_execdir="${APP_DIR}"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*brgen.*falcon"
rc_bg=YES
rc_reload=NO
rc_cmd "$1"
EOF

#--- Install rc.d script ------------------------------------------------------
doas install -m 555 "${TMP_RC}" "${RC_FILE}"
doas rcctl enable "${RC_NAME}"

#--- Run database migrations --------------------------------------------------
doas -u brgen sh -c "cd '${APP_DIR}' && RAILS_ENV=production bundle exec rails db:migrate"

#--- Start service ------------------------------------------------------------
doas rcctl start "${RC_NAME}"

printf '==> %s serving on port %s\n' "${RC_NAME}" "${PORT}"
