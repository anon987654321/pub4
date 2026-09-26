#!/usr/bin/env zsh
# OpenBSD vm23 deploy — executable entrypoint. Operational functions live in OPENBSD/lib/operator_*.zsh.
# Routine (on vm23): cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh
# Installs OPENBSD/{etc,usr,var} onto /, validates pf/relayd, restarts services.
# Rare: --first-install | --stage-1 (DNS wipe) | --stage-2 (full app bootstrap)
# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)
#
# IDEMPOTENCY NOTES (CC14):
# - Safe to re-run: bootstrap_rails_app (cp tree, bundle install, db:prepare), sync_openbsd_configs
#   (backs up /etc first), relayd/pf template installs when configs already match, rcctl enable/start.
# - DESTRUCTIVE on re-run: stage_1 deletes /var/nsd/etc/* and /var/nsd/zones/master/* before
#   regenerating signed zones. Never re-run stage_1 on a live authoritative server without backup.
# - State tracking: STATE_FILE=/var/db/openbsd_setup.state — is_step_completed/mark_step_completed
#   helpers exist for future --resume support; certificate-renewal cron must stay append-idempotent.
# - Data preserved: Rails SQLite under /home/<app>/app/storage, ~/priv, acme certs in /etc/ssl when
#   stage_1 is skipped. Re-running stage_2 does not drop databases.
# - Post-deploy verification: ruby /home/dev/pub4/OPENBSD/gates/health_check.rb
# Engine-ize: bootstrap_rails now relies on bundle install for pub4-shared path gem (Gemfiles declare it);
# legacy sh shared/install_* deprecated in scripts + WIRING. No copy sprawl.

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex
zmodload zsh/datetime

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}
REPO_ROOT=${SCRIPT_DIR:h}
CONFIG_ROOT=${REPO_ROOT}/OPENBSD

for helper in operator_core operator_config operator_apply operator_stage1 operator_apps operator_stage2; do
  source "${CONFIG_ROOT}/lib/${helper}.zsh"
done

deploy_live() {
  sync_openbsd_apply "${CONFIG_ROOT}"
}

main() {
  if [[ ${1:-} = --help || ${1:-} = -h ]]; then
    usage
    exit 0
  fi

  case ${1:-} in
    --sync-configs|--sync|sync)
      deploy_live
      ;;
    --first-install)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "first_install rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      stage_2
      ;;
    --stage-1|--stage1)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "stage_1 rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      ;;
    --stage-2|--stage2)
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_2
      ;;
    "")
      deploy_live
      ;;
    *)
      log ERROR "unknown flag: $1"
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"

