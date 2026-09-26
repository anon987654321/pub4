usage() {
  print -r -- "OpenBSD vm23 deploy (OPERATOR.sh). Config trees: etc/ usr/ var/ → /.
Usage:
  cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh

Default: install configs, validate pf/relayd, restart services.

Rare:
  doas zsh OPERATOR.sh --first-install
  doas zsh OPERATOR.sh --stage-1        # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh OPERATOR.sh --stage-2

--sync-configs is an alias for the default.

Env:
  RUN_PRODUCTION_SEEDS=1   run db:seed during app bootstrap (default 0: never seed production)
  I_UNDERSTAND_DNS_WIPE=1  required by --stage-1"
}

# Helpers inlined for ONE_SOURCE. Pure Zsh: log, backup_directory, install_*, sync_openbsd_configs.
log() {
  typeset level=$1; shift
  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/openbsd_setup.log >&2
}
log_info()  { log INFO "$@" }
log_error() { log ERROR "$@" }

transaction_log() {
  typeset operation=$1 target=$2 op_status=$3 metadata=${4:-}
  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$operation] $target | Status: $op_status | $metadata" \
    >> /var/log/openbsd_transactions.log
}

cleanup() {
  typeset exit_code=$?
  for tmpfile in "${TMPFILES[@]}"; do
    [[ -n $tmpfile && -f $tmpfile ]] && rm -f "$tmpfile"
  done
  return $exit_code
}

error_handler() {
  typeset exit_code=$1 line_num=$2
  log ERROR "Script failed with exit code $exit_code at line $line_num"
  cleanup
  exit $exit_code
}

backup_directory() {
  typeset target_dir=$1 backup_name=${2:-${1:t}}
  typeset backup_dir=/var/backups/openbsd_setup
  typeset backup_file="$backup_dir/${backup_name}-${EPOCHSECONDS}.tar.gz"
  [[ ! -d $backup_dir ]] && mkdir -p "$backup_dir"
  [[ ! -d $target_dir ]] && { log WARN "Directory $target_dir does not exist, skipping backup"; return 0 }
  log INFO "Backing up $target_dir to $backup_file"
  transaction_log "BACKUP" "$target_dir" "START"
  if tar -czf "$backup_file" -C "${target_dir:h}" "${target_dir:t}" 2>/dev/null; then
    transaction_log "BACKUP" "$target_dir" "SUCCESS" "$backup_file"
    typeset -a _bfiles; _bfiles=("$backup_dir"/${backup_name}-*.tar.gz(N))
    (( ${#_bfiles} > 10 )) && {
      typeset -a _sorted; _sorted=("$backup_dir"/${backup_name}-*.tar.gz(NOm))
      for _f in "${_sorted[@]:10}"; do rm -f "$_f"; done
    }
    echo "$backup_file"
    return 0
  else
    transaction_log "BACKUP" "$target_dir" "FAILURE"
    log ERROR "Backup failed for $target_dir"
    return 1
  fi
}

install_template() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat > \"$dst\" <<INSTALL_TEMPLATE_EOF
$content
INSTALL_TEMPLATE_EOF"
}

append_template() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat >> \"$dst\" <<APPEND_TEMPLATE_EOF
$content
APPEND_TEMPLATE_EOF"
}

install_static() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing file: $src"; exit 1 }
  cp "$src" "$dst"
}

install_tracked_crontab() {
  typeset tracked=${SCRIPT_DIR}/etc/crontab.vm23
  [[ -f $tracked ]] || return 0

  # /tmp/root_crontab.$$ was a PID-predictable name in a world-writable directory
  # that root wrote and then fed straight to crontab(1) — the same shape as the
  # doas.conf staging file in validate_doas.ksh, and with root's crontab as the
  # payload. A root-owned 0700 directory has no symlink for root to follow.
  typeset cron_dir=/var/db/pub4
  mkdir -p $cron_dir && chmod 700 $cron_dir
  typeset root_cron
  root_cron=$(mktemp "${cron_dir}/root_crontab.XXXXXXXXXX") || return 1
  TMPFILES+=($root_cron)
  crontab -l 2>/dev/null > $root_cron || :

  # The PATH assignment gets its own pass, because the merge loop below cannot
  # carry it: it skips anything with fewer than six fields, and `PATH=...` is one.
  # That is how the single most load-bearing line in crontab.vm23 would have been
  # tracked in the repo and never installed. Rewritten rather than appended so a
  # stale PATH on the box is corrected rather than shadowed — cron takes the last
  # assignment, but a reader takes the first.
  typeset cron_path
  cron_path=$(grep -m1 '^PATH=' $tracked) || cron_path=''
  if [[ -n $cron_path ]]; then
    typeset merged
    merged=$(mktemp "${cron_dir}/root_crontab.XXXXXXXXXX") || return 1
    TMPFILES+=($merged)
    { print -r -- "$cron_path"; grep -v '^PATH=' $root_cron } > $merged || return 1
    mv $merged $root_cron || return 1
    log INFO "installed root cron: $cron_path"
  fi

  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    typeset -a fields=(${=line})
    [[ ${#fields[@]} -lt 6 ]] && continue
    typeset cmdpath=$fields[6]
    typeset tag=${cmdpath:t}
    grep -q "$tag" $root_cron 2>/dev/null && continue
    # Refusing to schedule a command that is not on the box is right: cron would
    # mail root once per tick forever. Refusing silently is not. A tracked job
    # then exists in etc/crontab.vm23, is absent from the crontab, and reads as
    # complete from both ends — nothing is missing from the file you are looking
    # at. uptime-check.sh sat in crontab.vm23 and in usr/local/bin/ from
    # 2026-08-12 until 2026-08-18 and had never been scheduled, because the run
    # that installs the wrapper at stage 1 had not happened and every earlier
    # install_tracked_crontab call passed over the line without a word.
    if [[ $cmdpath == /* && ! -x $cmdpath ]]; then
      log WARN "tracked cron job not installed: $cmdpath is missing or not executable"
      continue
    fi

    print -r -- "$line" >> $root_cron
    log INFO "installed root cron: $tag"
  done < $tracked

  crontab $root_cron || { log ERROR "Crontab update failed"; return 1 }
  return 0
}

is_step_completed()  { [[ -f "${STATE_FILE}.steps" ]] && [[ $(<"${STATE_FILE}.steps") == *"$1"* ]] }
mark_step_completed() { print -r -- "$1" >> "${STATE_FILE}.steps" }

# Install exact config trees from repo onto /. Run separately or before --sync-configs:
#   doas cp -R etc usr var /
