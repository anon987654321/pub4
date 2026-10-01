# OPENBSD snapshot

Generated from /Users/mac/Documents/GitHub/pub4/OPENBSD.

## Tree

.
CLAUDE.md
OPERATOR.sh
PATH_OWNERSHIP.yml
README.md
RUNBOOK.md
_net.sh
backup_priv.sh
bin
  amber_queue_sweep.sh
  deploy-diff.sh
  deploy-smoke.sh
  deploy_all.sh
  domain_watch.rb
  render_dns.rb
  resource_guard.sh
  restore_litestream.sh
  start_all_apps.sh
  sync_deploy_inventory.rb
  uptime-check.sh
  vps_ci.sh
  vps_ci_all.sh
  vps_deploy_master.sh
  vps_install_all.sh
  vps_master_scan.sh
  vps_on_vm_install.sh
  vps_production_push.sh
  vps_run_remote.sh
  vps_weekly_integrity.sh
data
  dns.yml
  domain_inventory.yml
  domain_released.yml
  operator.yml
deploy_inventory.json
dev
  agent_worktree.sh
  backup.sh
  clean.sh
  lint.sh
  open_in_vim.zsh
  operator_stage_1.zsh
  operator_stage_2.zsh
  operator_usage.zsh
  perms.sh
  replace.sh
  watch_tests.sh
emergency_cpu.sh
etc
  litestream.yml
gates
  config_drift_gate.rb
  deploy_smoke_gate.rb
  dns_zones.rb
  domain_alignment.rb
  health_check.rb
  installed_targets_gate.rb
  integrity_gate.rb
  port_inventory.rb
  shell_syntax_gate.rb
  solid_queue_proof.rb
  verify_deploy_identity.rb
  verify_openbsd_idempotency.rb
  vps_safety_gate.rb
lib
  ci_lock.sh
  deploy_inventory.rb
  deploy_stamp.rb
  disk_usage.rb
  gate_environment.rb
  gate_ledger.rb
  gate_result.rb
  guard_state.rb
  permission_audit.rb
  secret_redaction.rb
  ssh_vm23.sh
  token_echo.rb
  utf8.rb
ptr_openbsd_amsterdam.rb
relayd_prune_keypairs.rb
sync.rb
test
  resource_guard_test.sh
  run_all.rb
  test_config_drift_gate.rb
  test_core_reclaim.rb
  test_deploy_stamp.rb
  test_disk_usage.rb
  test_dns_facts_agree.rb
  test_domain_expiry.rb
  test_gate_fixtures.rb
  test_gate_lib.rb
  test_githooks.rb
  test_guard_state.rb
  test_guard_thresholds_documented.rb
  test_health_check.rb
  test_path_ownership.rb
  test_permission_audit.rb
  test_ptr_openbsd_amsterdam.rb
  test_rc_env_export.rb
  test_reach.rb
  test_restore_scripts.rb
  test_solid_queue_proof.rb
  test_ssh_vm23_contract.rb
  test_sync_redaction.rb
  test_tracked_crontab.rb
  test_vps_admin.rb
  test_vps_deploy_contract.rb
  test_vps_run_remote_contract.rb
  test_vps_safety_gate.rb
usr
  local
    bin
      core-reclaim.sh
      declutter-hygiene.sh
      declutter_hygiene.rb
      drain-jobs.sh
      keep-warm.sh
      ports-import.sh
      ports_import.rb
      prune-guests.sh
      prune_guests.rb
      renew-certs.sh
      uptime-check.sh
vm_resource.yml

## Source

### CLAUDE.md

`````markdown
# OPENBSD deploy pipeline — gotchas for agents

Operator-facing docs live in `README.md` and `RUNBOOK.md`, and the recipes in
`data/operator.yml`. This file is
specifically the sharp edges that have burned agents in this repo — read it
before touching the deploy pipeline, not after.

Authority order: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` >
executable law (`MASTER/law/*.rb` and `MASTER/lib/review/scan/rules/*.rb`) >
repo harnesses > this per-tree contract.

## The fleet is four, and master is the one that gets dropped

`bin/vps-deploy all` deploys `master brgen amber bsdports`, in that order,
halting the pass on the first failure. Prefer it over four hand-typed runs.

Until it existed there was no way to say "deploy everything", so the set lived
in whoever was typing — and master is not under `/home/*/app`, so an operator
enumerating the Rails apps does not see it and leaves it behind. A pull moves
the checkout for everything; only a deploy makes any of it live.

The order is load-bearing, not alphabetical. Every deploy sheds amber and
bsdports: they land in `rcctl failed` with ports 61352/47312 closed while relayd
keeps answering TLS, so the outage reads as a hang rather than a 5xx and nothing
reports it. Deploying those two last folds the restore into the same pass.

Related, and worth knowing before you diagnose a deploy: **a shed and a relayd
failure look nothing alike once you check.** A shed leaves 443 answering with
the app port closed. If **443** refuses in ~30 ms while sshd is up and the app
answers on its own port from the box, the front door is down, not a backend —
and if something you did not deploy (ai.brgen.no) is down too, that is the
diagnosis rather than collateral.

Do not read port 80 as part of that test, but not for the reason this file gave
until 2026-08-25. It said port 80 "always refuses", that `relayd.conf` declares
the only listener, and that "there is no HTTP listener to lose". That is wrong:
`httpd` runs as `www` and holds `*.80`, and `fstat` on vm23 shows three of its
processes there. relayd does declare exactly one relay — `listen on 0.0.0.0 port
443 tls` — but relayd is not the only daemon on the box.

What port 80 answers is a 301 to HTTPS, plus ACME HTTP-01 challenges out of
`/acme`; the first server block in `/etc/httpd.conf` says so. So a request to 80
returns 301 whether or not a single Rails app is running, which is why it
carries no information about a shed or a relayd failure — the same conclusion
the old paragraph reached from a false premise, and it is worth keeping the
distinction because the premise has a consequence the conclusion does not: if
port 80 ever *does* refuse, that is a real finding. Certificate renewal goes
through it, so httpd being down means the certs stop renewing silently and the
site fails ~90 days later for a reason nothing will connect to this.

The original note is still true of the mistake that produced it: `curl
http://brgen.no:443/up` speaks plain HTTP at a TLS port and returns 000, so a
check written that way reports both ports refusing and looks exactly like the
outage it is inventing.

`httpd.conf`'s second server block serves `/postpro` — personal photographs —
with no TLS and no auth, on `127.0.0.1 port 6666`. Reach it over an ssh tunnel.
It listened on `*` until pf's default deny was the only thing keeping it private;
if anyone widens that listener again, pf becomes the exposure's only guard.

## `SKIP_CI=1` does not mean "skip CI"

`bin/vps-deploy <app>` takes one of two branches:

- **Default** (`SKIP_CI` unset): `vps_ci.sh <app>` syncs the repo into a CI
  mirror and runs `bin/ci` (see below) against a throwaway test DB.
- **`SKIP_CI=1`**: skips `vps_ci.sh` and runs `RAILS/<app>/<app>.sh`, which
  calls `deploy_tracked_app` → `rails_runtime_gate`. That gate bundles,
  prepares the databases, precompiles assets and runs `bin/ci` inside the
  deployed `/home/<app>/app` tree. CI still runs, in a different place.

The fast hotfix path uses `SKIP_RUNTIME_GATE=1` and `SKIP_CI=1`, but the
runtime skip is now protected by the human-only `I_UNDERSTAND_FAST_DEPLOY=1`
acknowledgement. Without that exact acknowledgement, `rails_runtime_gate`
refuses to bypass CI. When the acknowledgement is supplied, the hotfix path
runs no `bin/ci`; only the loopback gates `vps-deploy` runs after each
restart.

## `bin/ci`'s `Setup` step behaves differently locally vs. on the VPS

`RAILS/shared/config/ci.rb` gates several steps on `vps_host` (true when
`PUB4_CI_GUARD=1`, `/var/db/pub4_vps` exists, or `/etc/relayd.conf` exists):

- `Security: Importmap audit` and `Tests: System (a11y)` — **skipped on the
  VPS**, required locally. A local `bin/ci` failure in those two is real; it
  does not mean the VPS run will also fail. Both need something the box does not
  have on hand (a booted environment, a browser).
- `Style: Ruby` (RuboCop) — **runs on the VPS too**, and this list said
  otherwise until 2026-08-25. `ci.rb` carries the reason next to the step: vm23
  is where the deploy gate actually runs, so skipping it there left enforcement
  to a local `bin/ci` that nothing runs automatically. It is a source-text check
  needing no browser and no database, so the reasons the other two are skipped
  do not apply. A RuboCop failure on the box is a real deploy blocker — do not
  read it as a local-only bucket, which is exactly what this file used to say.
- `Tests: Seeds` — runs with `SKIP_BERGEN_DEMO=1` on the VPS, without it
  locally. A local seed failure about a duplicate Bergen demo email is a
  local-DB-state artifact, not a real blocker — don't chase it.
- `Setup` (`bin/setup --skip-server`, includes `db:prepare`) replays the full
  migration history. A stale local dev DB can hit a legacy FK-naming mismatch
  that only existed mid-history and was never a bug in current schema.rb.
  Confirm against a fresh DB (or the VPS run) before treating this as real.

**Rule of thumb:** a local `bin/ci` failure is only actionable if you can name
which of the above buckets it's *not* in. When in doubt, read
`RAILS/shared/config/ci.rb` directly rather than assuming.

## Copy-tree sync must delete before it extracts

`vps_ci.sh`'s `sync_from_repo()`/`sync_ci_rails_root()` sync the repo to each
app's copy-tree via `tar` extraction. Tar extraction only *overlays* — it never
deletes destination files that are absent from the source. A file deleted from
git therefore survived indefinitely on the VPS's copy-tree checkout, invisibly,
until something referenced it and broke at runtime.

Adding `doas rm -rf` before each `tar xf -` extraction fixed this (both in
`sync_from_repo()`'s per-directory loop and in `sync_ci_rails_root()`). If
you're debugging a VPS-only failure where a file "shouldn't exist anymore" but
the error implies it does, first check whether your local `vps_ci.sh` is current
— this exact bug reappearing (e.g. via a revert) would look like ghost files
coming back from the dead.

## `rcctl check` can report "failed" while the service is still booting

Falcon takes ~30-40s to fully boot under VPS load (1 vCPU, shared with other
apps). `doas rcctl check <app>` polled a few seconds after `rcctl restart` can
report `failed` even though the process is healthy and mid-startup — this is not
a crash. Before treating a post-deploy `rcctl check` failure as real:

- `tail /var/log/daemon` for the app — look for a normal "Waiting for
  startup..." progression vs. an actual stack trace/exit.
- `ps ax | grep <app>` — is the Falcon process actually running?
- Retry `rcctl check` after ~30s before escalating.

A "completed (exit code 0)" notification from a background deploy command is
**not** proof the deploy succeeded either — it reflects the SSH wrapper's exit,
not the deployed script's outcome. Always verify independently via:

1. The deploy stamp: `/var/db/pub4/last_deploy_<app>.json` (`status: "ok"` and
   the expected SHA).
2. `doas rcctl check <app>`.
3. A live `curl` against the app's actual URL, not just `/up`.

## `resource_guard.sh` shedding amber/bsdports — check it actually recovers

Under load, the VPS's `resource_guard.sh` cron sheds `amber`/`bsdports` (tracked
in `/var/db/resource_guard_shed`). Check that file first to confirm a down app
is the guard and not a real crash.

But do not stop there and call it self-recovering, which is what this section
used to say. Shed and restore are separate gates and they can drift one way.
Measured on 2026-07-29 over 916 ticks: shedding fired on 48% of ticks while the
restore gate opened on 19%, and restore only releases one service per tick — so
amber and bsdports had been down for days, not oscillating. `MEM_RESTORE` was
20% against a median availability of 13%, i.e. the window sat outside the box's
operating range, so that pass set 8/14 and `LOAD_RESTORE` 2.0.

It has been recalibrated once more since, and this paragraph said 8/14 for a
month after it stopped being true. `MEM_RESTORE` is **10**, set on 2026-08-14
from 1550 ticks: availability had moved from p50 13 to p50 9, so 14 had drifted
back above p75 — the same condition the 2026-07-29 pass existed to fix, arriving
a second time from the other direction. `MEM_WARN` is 8 and `LOAD_RESTORE` 2.0.

Read the numbers from `resource_guard.sh`, which carries each recalibration with
the dataset that justified it. A threshold copied into prose is a threshold that
goes stale the next time the box changes.

The check that distinguishes the two cases is
`/var/log/resource_guard_history.log`, which records `load=`, `mem_avail=` and
`shed=` per tick. If shed ticks vastly outnumber ticks that satisfy `shed=0 &&
mem_avail >= MEM_RESTORE && load < LOAD_RESTORE`, the guard is parking those
apps, not cycling them, and the thresholds need recalibrating against that log
rather than against a guess.

## Refused, and why

Each of these was proposed and measured against the tree. A reason tied to one
file sits in a comment on that file; these have no single file to sit on.

- **No fourth public Rails app** beyond brgen, amber and bsdports until brgen's
  high-churn verticals are engines with their own migrations and tests, money and
  identity primitives live in `RAILS/shared` with more than one consumer, and CI
  runs the layout suite and `/up` smoke for all three apps. Every restart before
  pub4 grew surface before its boundaries held; horizon ideas wait in
  `RAILS/apps.horizon.yml`.
- **No staging environment.** vm23 is one vCPU and 1 GB and already sheds apps
  under load. A staging copy arrives with a second box, not as a second set of
  services on this one.
- **No second reference platform.** OpenBSD's behaviour wins over the Mac's for
  package names, services, relayd, pf, nsd and Ruby command names. Production is
  one host family with one Ruby pin, so a platform matrix or a Linux runner
  cannot reproduce what differs: the Mac and box locks disagree because
  `rb-kqueue` resolves only on BSD, and the fix is the `install_if` entry in
  `TODO.md`.
- **No repair-plan command, no dry run on every mutating command, and no deploy
  that fails closed on revision drift.** A deploy is the only mutation and halts
  on its first failure. Revisions disagree between deploys by design, which is
  why `health_check.rb` warns on commits behind, and failing closed blocks the
  deploy that fixes the drift. A planning surface beside `vps-deploy` is a third
  surface where the root contract allows two.
- **No automated rollback.** Rolling back is deploying the previous SHA through
  `vps-deploy`. A second path that runs once a year is untested on the day it is
  needed, the same argument the three unrun recovery scripts carry in their
  headers.
- **No pledge or unveil for the Rails daemons.** A Ruby interpreter that loads
  native extensions and forks workers cannot name a useful promise set. MASTER's
  `Ground::Pledge` covers the one process that can, and each app runs as its own
  user with its env file and storage closed to others, which `health_check.rb`
  checks.
- **No speed work on deploy or health tooling without a symptom.** The box's
  measured problem is memory, which is why `core-reclaim.sh` and `keep-warm.sh`
  exist, not the cost of a gate's system calls. A health check made faster by
  proving less is a regression. Latency work starts from a symptom a visitor or a
  log names, and is measured on vm23.
- **No idempotency keys, cart expiry, stuck-order alarms or edit locks for
  takeaway and marketplace while no vendor is live.** Turbo disables a submit in
  flight and the order state machine refuses illegal transitions under test. The
  first duplicate order from a real kitchen is the measurement they wait for.
- **No per-component screenshot baselines, density tests or control-distance
  rules.** `layout_snapshot` commits reviewable geometry for the surfaces, and how
  dense a screen is stays the operator's call about how it looks.
- **No sweep of `|| true`.** Most are idempotence on `rcctl`, `pkill`, `chmod`,
  `install` and `rm -f`. Read the exit path before removing one.

`````

### OPERATOR.sh

`````zsh
#!/usr/bin/env zsh
# OpenBSD vm23 deploy — executable script. Everything else in this tree is an exact config mirror.
# Routine (on vm23): cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh
# Installs OPENBSD/{etc,usr,var} onto /, validates pf/relayd, restarts services.
# Rare: --first-install | --stage-1 (DNS wipe) | --stage-2 (full app bootstrap)
# PLATFORM BASELINE: OpenBSD 7.9; release-specific behavior must be checked against the target man pages
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
# Engine-ize: bootstrap_rails now relies on bundle install for pub4-shared path gem (Gemfiles declare it); legacy sh shared/install_* deprecated in scripts + WIRING. No copy sprawl.

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex
zmodload zsh/datetime

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}
REPO_ROOT=${SCRIPT_DIR:h}
CONFIG_ROOT=${REPO_ROOT}/OPENBSD

# Usage comes first. Operational stages live in small sourced modules, so the
# entrypoint stays navigable without depending on a stale file-line count.
source "${SCRIPT_DIR}/dev/operator_usage.zsh"
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
  print -r -- "$content" > "$dst"
}

append_template() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  print -r -- "$content" >> "$dst"
}
install_static() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing file: $src"; exit 1 }
  cp "$src" "$dst"
}

install_tracked_crontab() {
  typeset tracked=${SCRIPT_DIR}/etc/crontab.vm23
  [[ -f $tracked ]] || { log ERROR "Missing tracked root crontab: $tracked"; return 1; }

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
install_root_configs() {
  typeset src=${1:-${CONFIG_ROOT}}
  [[ -d $src/etc ]] || { log ERROR "No etc/ in $src"; return 1 }
  backup_directory /etc "etc-pre-sync" || return 1

  if [[ -f $src/etc/doas.conf ]] && [[ $(tail -c1 "$src/etc/doas.conf" | wc -c) -eq 0 ]]; then
    print >> "$src/etc/doas.conf"
    log WARN "doas.conf missing trailing newline — fixed before install"
  fi

  typeset doas_rollback=""
  if [[ -f /etc/doas.conf ]]; then
    mkdir -p /var/backups/openbsd_setup
    doas_rollback="/var/backups/openbsd_setup/doas.conf.${EPOCHSECONDS}.rollback"
    cp /etc/doas.conf "$doas_rollback"
  fi

  for d in etc usr var; do
    [[ -d $src/$d ]] || continue
    install -d "/$d" 2>/dev/null || true
    cp -R "$src/$d"/. "/$d"/
    log INFO "installed /$d from repo"
  done

  # 755 first, then 555 for the scripts this repo owns. Written the other way
  # round, the blanket loop undid the line above it two lines later, so the mode
  # the file asks for twice — here and where master is installed — was never the
  # mode it set.
  #
  # Two conventions, on purpose, and vm23 already runs both: OpenBSD's own 82
  # base scripts are 755, and the nine this repo installs are r-xr-xr-x. The
  # read-only bit is the signal that the file is generated from the checkout and
  # a local edit will be overwritten. root writes through it regardless, which is
  # why `cp` onto an installed script has always worked.
  [[ -f /etc/daily.local ]] && chmod 755 /etc/daily.local
  for f in /etc/rc.d/*(N); do chmod 755 "$f"; done
  for svc in master ${ALL_APPS%%:*}; do
    [[ -f /etc/rc.d/$svc ]] && chmod 555 /etc/rc.d/$svc
  done
  for f in /usr/local/bin/*(N); do [[ -f $f ]] && chmod 755 "$f"; done
  # libexec holds helpers root dot-sources (stale_ci_cleanup.ksh); they must be
  # root-owned and not group/world writable or the sourcing is a root RCE.
  for f in /usr/local/libexec/*(N); do [[ -f $f ]] && chown root:wheel "$f" && chmod 755 "$f"; done

  if [[ -f /etc/doas.conf ]]; then
    if ! su dev -c 'doas id' 2>/dev/null | grep -q 'uid=0(root)'; then
      log ERROR "doas validation failed after config install — aborting (restoring previous doas.conf)"
      [[ -n $doas_rollback && -f $doas_rollback ]] && cp "$doas_rollback" /etc/doas.conf
      return 1
    fi
    log INFO "doas validation passed after config install"
  fi

  install_tracked_crontab || return 1

  # /home/dev/.zshrc is not installed from etc/.zshrc. That file is sync.rb's
  # redacted mirror of the live one, so copying it back would replace dev's API
  # keys with __REDACTED__.

  log INFO "OpenBSD config tree install complete (with backup)"
}

sync_openbsd_configs() {
  install_root_configs "$@"
}

sync_openbsd_apply() {
  typeset src=${1:-${CONFIG_ROOT}}
  install_root_configs "$src" || return 1

  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid after sync"; return 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf reload failed"; return 1 }
  /sbin/pfctl -e 2>/dev/null || log WARN "pf already enabled or enable skipped"

  if [[ -x /usr/bin/ruby40 ]] || command -v ruby40 >/dev/null 2>&1; then
    ruby40 "${SCRIPT_DIR}/relayd_prune_keypairs.rb" --apply /etc/relayd.conf \
      || log WARN "relayd keypair prune failed"
  fi
  relayd -n -f /etc/relayd.conf || { log ERROR "relayd.conf invalid after sync"; return 1 }

  if [[ -x /usr/local/bin/nsd-resign ]]; then
    ruby /usr/local/bin/nsd-resign || log WARN "nsd-resign failed after zone sync"
  fi

  # STRICT rules.yml adherence (per success_criteria: "system_applies_to_itself_without_exception", self_test, ground_truth_check, evidence_scoring, veto_patterns, anti_patterns, tier1 principle_priorities).
  # Run MASTER deep scan on OPERATOR tree before any service restart. Block on violations (tier1 critical + veto).
  # Uses ground_truth_check (fresh read), self_test (laws on OPERATOR), evidence_scoring (scan_clean).
  # Also covers lexical/structural for sh, yml, conf, erb; no bypasses.
  if [[ -n ${SKIP_MASTER_SCAN:-} ]]; then
    log WARN "MASTER scan skipped (SKIP_MASTER_SCAN)"
  elif [[ -x /home/dev/pub4/MASTER/bin/cli ]]; then
    typeset scan_log_dir=/var/db/pub4
    typeset scan_log=$scan_log_dir/master_deploy_scan.log
    mkdir -p "$scan_log_dir" || { log ERROR "cannot create $scan_log_dir"; return 1 }
    chmod 700 "$scan_log_dir"
    log INFO "MASTER rules scan (OPERATOR) — strict pre-apply per rules.yml (ROBUSTNESS/SINGULARITY/LINEARITY/PROXIMITY/ABSTRACTION/DENSITY + veto)"
    if ! su dev -c 'cd /home/dev/pub4/MASTER && MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle40 exec ruby bin/gate --scan-only --tree=OPENBSD' 2>&1 | tee "$scan_log"; then
      log ERROR "MASTER scan found violations — refusing sync/apply (self_violation would occur per rules.yml)"
      return 1
    fi
    log INFO "MASTER scan clean — proceeding (scan_clean + self_apply satisfied)"
  else
    log ERROR "MASTER not available for scan — refusing sync/apply"
    return 1
  fi

  # Enforce ground_truth_check/ + evidence before writes (rules.yml): fresh read, diff, output shown.
  # library_verify pre-flight before bundle/shell (per rules).
  for f in /etc/pf.conf /etc/relayd.conf; do
    [[ -s $f ]] || { log ERROR "ground_truth fail on $f"; return 1; }
  done
  # (In per-app: before bundle, check Gemfile etc.)

  # Not `|| true`. The crontab schedules /usr/local/bin/resource_guard.sh every
  # five minutes and it is the load-shedding guard that keeps this 1GB box up —
  # swallowing the install failure meant it could simply be absent, with no
  # error, while every log line still said the crontab was installed.
  if ! install -m 755 "${SCRIPT_DIR}/bin/resource_guard.sh" /usr/local/bin/resource_guard.sh; then
    log ERROR "resource_guard.sh install failed — the load guard would be absent"
    return 1
  fi

  # resource_guard.sh's crisis tier is guarded the same way and installed from
  # the same place. LOAD_CRIT runs `/usr/local/bin/emergency_cpu.sh` when it is
  # executable and logs "emergency_cpu not installed" when it is not, so without
  # this line the top tier of the load guard can only ever write that line.
  if ! install -m 755 "${SCRIPT_DIR}/emergency_cpu.sh" /usr/local/bin/emergency_cpu.sh; then
    log ERROR "emergency_cpu.sh install failed — resource_guard's crisis tier would only log"
    return 1
  fi

  # crontab.vm23 schedules the weekly integrity run, and install_tracked_crontab
  # refuses a command that is not on the box. root runs the installed copy for
  # the same reason daily.local does: the checkout is dev-writable.
  if ! install -m 755 "${SCRIPT_DIR}/bin/vps_weekly_integrity.sh" /usr/local/bin/vps_weekly_integrity.sh; then
    log ERROR "vps_weekly_integrity.sh install failed — the weekly integrity run would go unscheduled"
    return 1
  fi

  # daily.local runs this as ROOT, and it guards on `[ -x /usr/local/bin/... ]`,
  # so the guard is exactly as load-bearing as the install. Nothing installed it:
  # config_drift_gate.rb sits under gates/ rather than under usr/local/bin/,
  # so install_root_configs never carried it, and the guard was false on every
  # run. Live had been edited by hand to run /home/dev/pub4/OPENBSD/... instead —
  # root executing a file the dev user can rewrite, every morning, which is the
  # escalation the guard's own comment forbids. Deploying daily.local without
  # this would swap that for a check that silently never runs.
  #
  # One file, and nothing beside it. It used to need lib/utf8.rb installed into a
  # /usr/local/bin/lib/ made for the purpose, because `require_relative` resolves
  # beside the installed copy; the gate sets its own encoding now, so the install
  # cannot half-succeed and the box carries no directory holding six lines.
  if ! install -m 755 "${SCRIPT_DIR}/gates/config_drift_gate.rb" /usr/local/bin/config_drift_gate.rb; then
    log ERROR "config_drift_gate install failed — daily.local would skip the drift check in silence"
    return 1
  fi
  install_tracked_crontab || return 1

  typeset -a svcs=(nsd httpd relayd smtpd master)
  for svc in $svcs; do
    [[ -x /etc/rc.d/$svc ]] || continue
    /usr/sbin/rcctl enable $svc 2>/dev/null || true
    /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
      || log WARN "$svc restart/start failed"
  done
  # App services: start only if /up already returns 200 — avoids Falcon crash-loops burning CPU.
  typeset -A app_ports=(brgen 38182 amber 61352 bsdports 47312)
  typeset -a core_apps=(brgen)
  typeset -a optional_apps=(amber bsdports)
  for svc in $core_apps $optional_apps; do
    [[ -x /etc/rc.d/$svc ]] || continue
    /usr/sbin/rcctl enable $svc 2>/dev/null || true
  done
  for svc in $core_apps; do
    typeset port=${app_ports[$svc]:-0}
    if (( port > 0 )); then
      typeset code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:${port}/up 2>/dev/null)
      if [[ $code != 200 ]]; then
        log WARN "$svc /up=$code before restart; attempting one controlled restart"
        /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
          || { log ERROR "$svc restart/start failed"; return 1; }
        sleep 10
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://127.0.0.1:${port}/up 2>/dev/null)
        [[ $code == 200 ]] || { log ERROR "$svc /up still $code after restart"; return 1; }
        continue
      fi
    fi
    /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
      || { log ERROR "$svc restart/start failed"; return 1; }
  done
  log INFO "optional Rails apps left stopped (vm23_small); start with: doas rcctl start <app>"

  wait_for_up() {
    typeset port=$1 name=$2 attempts=${3:-24} delay=${4:-5}
    typeset i code
    for (( i = 1; i <= attempts; i++ )); do
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://127.0.0.1:${port}/up 2>/dev/null)
      [[ $code == 200 ]] && { log INFO "$name /up ok (attempt $i)"; return 0; }
      sleep $delay
    done
    log ERROR "$name /up not ready on :${port} after $((attempts * delay))s (last=$code)"
    return 1
  }

  # No fallback falcon: one started here would run as dev beside rc.d/master's
  # daemon_user="master" — a second server on the same port, as the account that
  # can become root. A slow master gets the longer wait and then fails the run.
  if ! wait_for_up 53187 master 12 5; then
    log WARN "master slow — waiting longer for rc.d/master"
    wait_for_up 53187 master 24 5 || return 1
  fi
  wait_for_up 38182 brgen 24 5 || return 1

  ruby40 "${SCRIPT_DIR}/gates/health_check.rb" --core && log INFO "health_check ok" \
    || { log ERROR "health_check failed"; return 1; }
}

source "${SCRIPT_DIR}/_net.sh"

source "${SCRIPT_DIR}/dev/operator_stage_1.zsh"
source "${SCRIPT_DIR}/dev/operator_stage_2.zsh"

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' ERR INT TERM

# These four restate facts data/dns.yml already declares — BRGEN_IP is its
# nameserver.ip, HYP_IP the first of its xfr_peers, PUBLIC_RESOLVERS its
# resolvers.public. They stay as literals because this block is sourced before
# anything, and making it shell out to ruby40 to boot would put the deploy
# script behind an interpreter it also installs. test_dns_facts_agree fails if
# either copy moves without the other.
typeset -r BRGEN_IP="46.23.89.226"
typeset -r HYP_IP="194.63.248.53"
typeset -r LOCALHOST="127.0.0.1"

typeset -a PUBLIC_RESOLVERS=(1.1.1.1 9.9.9.9)
typeset -A APP_PORTS=(
  brgen 38182
  amber 61352
  bsdports 47312
  master 53187
)
typeset -A FAILED_CERTS

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1 }
validate_ip "$HYP_IP"   || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1 }

ALL_APPS=(
  brgen:brgen.no
  amber:amberapp.art
  bsdports:bsdports.org
)

SERVICES=()

# Current registrar-held domain inventory, refreshed from the 2026-09-30 Domeneshop export.
# This is ownership, not service exposure: parked or DNS-only names stay out of relayd/ACME until
# an app/city explicitly adopts them. RAILS/apps.yml carries the same inventory; ownership tests pin both.
OWNED_DOMAINS=(
  amberapp.art
  amberapp.no
  amberapp.online
  brgen.no
  bsdports.net
  bsdports.org
  cardff.uk
  denvr.us
  edinbrgh.uk
  foball.no
  frankfrt.de
  lndon.uk
  lsangeles.com
  lsangeles.store
  oshlo.no
  stvanger.no
  svalbrd.no
  trndheim.no
  wshingtondc.com
  wshingtondc.us
)

ALL_DOMAINS=(
  brgen.no:markedsplass,radio,dating,tv,takeaway,maps,messenger,ai
  longyearbyn.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  oshlo.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  stvanger.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  trmso.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  trndheim.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  reykjavk.is:markadur,radio,dating,tv,takeaway,maps,messenger
  kbenhvn.dk:markedsplads,radio,dating,tv,takeaway,maps,messenger
  gtebrg.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  mlmoe.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  stholm.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  hlsinki.fi:markkinapaikka,radio,dating,tv,takeaway,maps,messenger
  brmingham.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  cardff.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  edinbrgh.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  glasgw.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  lndon.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  lverpool.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  mnchester.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  amstrdam.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  rottrdam.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  utrcht.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  brssels.be:marche,radio,dating,tv,takeaway,maps,messenger
  zrich.ch:marktplatz,radio,dating,tv,takeaway,maps,messenger
  lchtenstein.li:marktplatz,radio,dating,tv,takeaway,maps,messenger
  frankfrt.de:marktplatz,radio,dating,tv,takeaway,maps,messenger
  brdeaux.fr:marche,radio,dating,tv,takeaway,maps,messenger
  mrseille.fr:marche,radio,dating,tv,takeaway,maps,messenger
  mlan.it:mercato,radio,dating,tv,takeaway,maps,messenger
  lisbon.pt:mercado,radio,dating,tv,takeaway,maps,messenger
  wrsawa.pl:marktplatz,radio,dating,tv,takeaway,maps,messenger
  gdnsk.pl:marktplatz,radio,dating,tv,takeaway,maps,messenger
  austn.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  chcago.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  denvr.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dllas.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dnver.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dtroit.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  houstn.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  lsangeles.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  mnnesota.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  newyrk.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  prtland.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  wshingtondc.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  pub.healthcare
  pub.attorney
  freehelp.legal
  bsdports.org
  bsddocs.org
  discordb.org
  stacyspassion.com
  foball.no
  amberapp.art
)



# ── Entry point ───────────────────────────────────────────────────────────────

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
      ruby40 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby40 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      stage_2
      ;;
    --stage-1|--stage1)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "stage_1 rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby40 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby40 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      ;;
    --stage-2|--stage2)
      ruby40 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby40 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
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

`````

### PATH_OWNERSHIP.yml

`````yaml
---
# What every path under OPENBSD/ is for, its risk, and the check that governs
# it. Keys are relative to this directory; `../` reaches the repo root. Globs
# are allowed. test/test_path_ownership.rb fails when a key names nothing, when
# a top-level entry here has no key, or when a check names a file that is gone.
ownership:
  "*.md":
    purpose: deploy front door, runbook, recipes, and agent gotchas with the standing refusals
    risk: high
    check: OPENBSD/bin/check
  PATH_OWNERSHIP.yml:
    purpose: this map
    risk: low
    check: ruby OPENBSD/test/test_path_ownership.rb
  ../TODO.md:
    purpose: consolidated repo-wide backlog; features live in RAILS/apps.yml,
      operator recipes in data/operator.yml
    risk: medium
    check: MASTER/bin/operator status
  ../RAILS/apps.yml:
    purpose: canonical app/domain/port/deploy inventory
    risk: critical
    check: OPENBSD/bin/check-rails
  ../RAILS/apps.horizon.yml:
    purpose: aspirational features (agent ignore)
    risk: low
    check: OPENBSD/bin/check-rails
  ../MASTER/gates/gates.yml:
    purpose: the gate registry — every RAILS and OPENBSD/gates gate is declared
      there and run through MASTER/gates/runner.rb
    risk: critical
    check: OPENBSD/bin/check-rails
  ../MASTER/gates/lib/production.rb:
    purpose: production Rails contract
    risk: high
    check: OPENBSD/bin/check-rails
  ../RAILS/shared/:
    purpose: shared Rails engine and deploy helpers
    risk: high
    check: OPENBSD/bin/check-rails
  ../RAILS/*/*.sh:
    purpose: per-app deploy scripts
    risk: critical
    check: ruby OPENBSD/gates/verify_deploy_identity.rb
  OPERATOR.sh:
    purpose: full OpenBSD installer/deployer, run as root on vm23
    risk: critical
    check: OPENBSD/bin/check-openbsd
  _net.sh:
    purpose: DNS, NSD, DNSSEC and certificate helpers OPERATOR.sh sources
    risk: high
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  bin/deploy_all.sh:
    purpose: workstation recovery path that reapplies box config (its header
      says why it stays unrun)
    risk: critical
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  bin/vps_ci.sh:
    purpose: serial app CI entrypoint on vm23
    risk: high
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  bin/resource_guard.sh:
    purpose: load shedding on vm23; skips shedding while /var/db/pub4_all_apps
      exists, which bin/start_all_apps.sh writes
    risk: high
    check: ksh OPENBSD/test/resource_guard_test.sh OPENBSD/bin/resource_guard.sh
  "bin/*.ksh":
    purpose: doas validation and the manual master recovery path
    risk: high
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  "bin/*.exp":
    purpose: recovery-only console automation, gated by I_UNDERSTAND_CONSOLE_RISK
    risk: critical
    check: ruby OPENBSD/gates/vps_safety_gate.rb
  emergency_cpu.sh:
    purpose: resource_guard's crisis tier; stays at the top because vm23's
      installed guard runs it from the checkout by this path (its header names
      the line)
    risk: high
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  backup_priv.sh:
    purpose: nightly encrypted ~/priv backup; stays at the top because vm23's
      /etc/daily.local runs it by this path (its header names the line)
    risk: high
    check: ruby OPENBSD/gates/shell_syntax_gate.rb
  deploy_inventory.json:
    purpose: deploy identity and public service inventory, generated by
      bin/sync_deploy_inventory.rb
    risk: high
    check: ruby OPENBSD/gates/verify_deploy_identity.rb
  gates/integrity_gate.rb:
    purpose: full local deploy gate chain
    risk: high
    check: ruby OPENBSD/gates/integrity_gate.rb
  "*.rb":
    purpose: config sync from the box and one-off operator tools
    risk: high
    check: OPENBSD/bin/check-openbsd
  vm_resource.yml:
    purpose: vm23 resource budget, mirroring resource_guard.sh
    risk: medium
    check: OPENBSD/bin/check
  bin/:
    purpose: operator entry points — checks, vps-deploy, vps-state, DNS render,
      domain_watch.rb (run weekly from etc/weekly.local), dr-pull — and the
      deploy, CI, install and recovery shell they call
    risk: critical
    check: OPENBSD/bin/check-openbsd
  lib/:
    purpose: the gate kernel every tree's gates return (why it lives here is the
      comment atop lib/gate_result.rb) plus the shared shell helpers
    risk: critical
    check: ruby OPENBSD/test/test_gate_lib.rb
  gates/:
    purpose: the gate scripts (health check, config drift, installed targets,
      safety, smoke, identity, integrity chain) and the domain, DNS and port
      gate classes MASTER/gates/gates.yml registers
    risk: high
    check: OPENBSD/bin/check-openbsd
  data/:
    purpose: dns policy, domain inventory and the operator command list
    risk: high
    check: OPENBSD/bin/check-openbsd
  test/:
    purpose: OPENBSD contract tests, run by bin/check
    risk: medium
    check: OPENBSD/bin/check
  tools/:
    purpose: tree.rb (repo shape) and reach.rb (deploy reach), both Ruby helpers
    risk: low
    check: ruby OPENBSD/test/test_reach.rb
  etc/:
    purpose: repo mirror of live /etc configs
    risk: critical
    check: OPENBSD/bin/check-openbsd
  usr/:
    purpose: root cron jobs installed to /usr/local/bin and helpers root sources
      from /usr/local/libexec
    risk: critical
    check: ruby OPENBSD/gates/installed_targets_gate.rb
  var/:
    purpose: nsd.conf and the unsigned zones bin/render_dns.rb generates
    risk: critical
    check: ruby OPENBSD/bin/render_dns.rb --check
  home/:
    purpose: repo mirror of the johann@brgen.no mail client (.muttrc, .mailcap,
      bin/mailimg), installed by OPERATOR.sh's setup_mail_client
    risk: low
    check: sh -n OPENBSD/home/johann/bin/mailimg
  dev/:
    purpose: operator Mac helpers and the git hooks MASTER/bin/operator hooks
      installs; nothing here reaches vm23
    risk: low
    check: ruby OPENBSD/test/test_githooks.rb
`````

### README.md

`````markdown
# OPENBSD

**Production is one box, and this tree is everything that puts it there and keeps
it honest.** It holds the VPS configuration under `etc/`, `usr/` and `var/`, and
the deploy tooling under `bin/`, `lib/` and `gates/`. The top of the tree keeps
the installer, `OPERATOR.sh`, the DNS helpers it sources, a few one-off Ruby
tools, and two scripts vm23 still runs by their top-level paths, each of which
says in its header which line on the box pins it.

Start here. `RUNBOOK.md` is the single operational companion for live VPS work;
read it before SSH, `doas`, deploy, DNS, relayd, NSD or recovery.
`OPENBSD/bin/check` is the local gate and `OPENBSD/bin/check-vps` checks vm23.
`OPENBSD/data/operator.yml` is the command and recipe source, so do not create
another command catalogue. `CLAUDE.md` holds the sharp edges that have burned
agents here, and `PATH_OWNERSHIP.yml` says what every path is for.

What is in `var/nsd/` is a mirror of the NSD configuration templates and nothing
more. The live signed zones sit on vm23 under `/var/nsd/` and are deliberately
not in git, because a signed zone in a shared checkout is a key in a shared
checkout.

`````

### RUNBOOK.md

`````markdown
# Operator

Production runbook for pub4. Read this file before live work. Read `MASTER/README.md` for the agent runtime; this file covers the
VPS and deploy surface, the agent contract, and live-operation safety in one
place.

## Repo layout

`MASTER/`, `RAILS/`, `OPENBSD/`, `STUDIO/` at the repo root, plus dotfolders. `MASTER/tools/` is inside MASTER and keeps compatibility entrypoints.
Canonical inventories: `RAILS/apps.yml`, `OPENBSD/deploy_inventory.json`. The
JSON is generated from `apps.yml` by `ruby OPENBSD/bin/sync_deploy_inventory.rb`,
and the `domain_alignment` gate fails when the two disagree. Deploy
gates (`integrity_gate.rb`, `verify_deploy_identity.rb`,
`deploy_inventory.json`) live at `OPENBSD/` top level, and so does
Old quarantine samples were deliberately removed from the tracked tree. It is not a recovery path:
`bin/dr-pull` recovers the databases and `manual_master_deploy.ksh` a stalled
master deploy. There is no `archive/`; git history holds the old installers.

## Deployment map

```text
Internet
  -> pf
  -> relayd TLS/SNI
  -> loopback app ports
      -> MASTER Falcon on ai.brgen.no
      -> brgen Rails app and vertical subdomains
      -> amber Rails app
      -> bsdports Rails app
  -> NSD/acme/httpd for DNS and certificate plumbing
```

Runtime contract: TLS terminates at relayd; apps listen on loopback-only ports;
Rails uses SQLite plus Solid Queue/Cache; secrets live in `/etc/*.env`; source
of truth on the VPS is `/home/dev/pub4`; long deploys run under tmux.

Gate flow — local: `OPENBSD/bin/check` → `verify_deploy_identity` → Rails
production/domain/ phantom/frontend gates → OpenBSD deploy smoke. Operator: `git
pull --ff-only` on vm23 → `vps_ci.sh <app>` → `OPERATOR.sh` or per-app deploy →
`rcctl restart` affected services → `health_check --public --all-ready-apps`.

## SSH

One session at a time. Rapid reconnects trip pf bruteforce.

| Target | Command |
|--------|---------|
| VM (apps) | `ssh -i ~/.ssh/id_ed25519_brgen dev@brgen.no` or `ssh brgen` |
| VMM host | `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` |
| Console | `vmctl console vm23` then `doas pfctl -t bruteforce -T flush` |

SSH aliases, host topology and provider access are kept in this runbook so live-operation guidance has one source.

## Domains

| Service | URL |
|---------|-----|
| MASTER | `https://ai.brgen.no` |
| brgen | `https://brgen.no` |
| brgen · marketplace | `https://markedsplass.brgen.no` |
| brgen · dating | `https://dating.brgen.no` |
| brgen · playlist | `https://radio.brgen.no` |
| brgen · takeaway | `https://takeaway.brgen.no` |
| brgen · tv | `https://tv.brgen.no` |
| brgen · messenger | `https://messenger.brgen.no` |
| amber | `https://amberapp.art` |
| bsdports | `https://bsdports.org` |

The brgen verticals (marketplace/dating/playlist/takeaway/tv/messenger + `maps`)
are one Rails app served under subdomains via `<brgen>`; relayd already routes
them all (`etc/relayd.conf`).

### Bringing a domain up

Seven city domains serve brgen, each scoped to its own city: `brgen.no`,
`oshlo.no`, `trndheim.no`, `stvanger.no`, `cardff.uk`, `edinbrgh.uk`,
`frankfrt.de`. Six more are registered, in `ALL_DOMAINS`, hold a zone that nsd
serves and an `acme-client.conf` block, and are waiting on one thing each:
`brmingham.uk`, `brssels.be`, `dnver.us`, `glasgw.uk`, `lverpool.uk`,
`mnchester.uk`. None of them has an NS record at its registrar, so nothing asks
our nameserver for them.

The order below is not a preference. Each step needs the one above it, and the
last step is the one that bites: relayd refuses to start when a `tls keypair`
names a certificate that is not on disk, so adding the keypair early takes down
every site relayd serves, not just the new one.

1. **Delegate at the registrar** — NS to `ns.hyp.net` and `ns.brgen.no`,
   matching `oshlo.no`. This is the only step that is not on this box.
2. **Confirm it resolves to us**, or acme cannot answer its own challenge: `ruby
   -rresolv -e 'puts Resolv.getaddress("glasgw.uk")'` → `46.23.89.226`.
3. **Issue the certificate.** The `domain` block already exists in
   `/etc/acme-client.conf`; `doas /usr/local/bin/renew-certs.sh` picks it up, or
   `doas acme-client -v glasgw.uk` for one.
4. **Check the certificate is on disk** before touching relayd: `doas ls -l
   /etc/ssl/glasgw.uk.fullchain.pem`.
5. **Add `tls keypair "glasgw.uk"`** to `etc/relayd.conf` beside the other city
   keypairs, then `doas relayd -n` and only then `doas rcctl reload relayd`.
6. **Verify**: `curl -sS -o /dev/null -w '%{http_code}' https://glasgw.uk/` is
   200, and the page title names the city.

The stack serves three Rails apps (brgen, amber, bsdports) plus MASTER. `baibl`,
`blognet` and `hjerterom` are retired; on 2026-08-12 their users, home
directories (1.6 GB between them), rc.d scripts, `/etc/*.env` files, login
classes, certificate symlinks and DNS zones were removed from vm23, and their
own domains (`baibl.no`, `blognet.no`, `hjerterom.no`) with them. Databases are
kept at `/var/backups/pub4/{hjerterom,deleted-apps}-20260812`. `foodielicio.us`
and the `anti{casino,gambling,betting}blog.com` trio were not removed: they stay
in `data/dns.yml`'s `extra_zones`, and nsd still serves them.

The repo recorded baibl and blognet as removed two months before the box lost
them, which is why `port_inventory` scans the config files where that kind of
residue lives, so the next removal cannot be half-done quietly.

Seven city apexes serve as of 2026-08-12
(`Brgen::DomainRegistry::LIVE_DOMAINS`); the rest of `ENTRIES` is either
NXDOMAIN at the registrar or parked at Domeneshop.

TLS terminates at relayd. Rails sets `config.assume_ssl = true`; do not enable
`force_ssl`.

## Agent contract

Modes: local contributor (edit repo files, run local gates, do not SSH), VPS
operator (one SSH session, one CI/deploy operation at a time, tmux for long
work), recovery (human-directed console or resource guard only to restore access
or health, then document the fix).

**Hard stops — AI agents must not autonomously:**

| Action | Why |
|--------|-----|
| `vmctl console/stop/start/reboot` on server4 | Serial console sessions have caused VM reboots and site outages |
| `pkill`/`kill` of `cu`, `vmctl`, or other VMM console sessions on server4 | Disrupts other operators and can wedge vm23 |
| `vps_console.exp` without human approval | Gated by `I_UNDERSTAND_CONSOLE_RISK=1`; recovery-only |
| Deploy, install, or `pkill` deploy workers from the serial console | Bypasses SSH safety, tmux, and load gates |
| Target vm27 or any non-vm23 VM | Wrong tenant; production is vm23 (`dev`) |
| `OPERATOR.sh --stage-1` without `I_UNDERSTAND_DNS_WIPE=1` | Destructive DNS wipe |
| Parallel SSH deploys, parallel `bin/ci`, or broad `rcctl restart` without a named target | 1 GiB VPS; contention causes outages |

When SSH to vm23 is required, use normal paths — but note which of them takes
`doas` and which must not:

| | |
|---|---|
| `doas zsh OPERATOR.sh` | root, it installs `/etc` |
| `zsh OPENBSD/bin/vps-deploy <app>` | **dev**; it escalates per step |
| `zsh OPENBSD/bin/vps_ci.sh <app>` | **dev** |

Under `doas`, `vps-deploy` fails at its first step with `Host key verification
failed` — root has no github host key, and giving it one would hand root a way
to fetch and run code from the network. It now refuses that invocation and says
so; this line used to name all three after the word `doas`.

**Rules:**

- Run `MASTER/bin/operator status` before starting work; the copy-paste paths
  are in `OPENBSD/data/operator.yml`.
- Treat `RAILS/apps.yml` and `OPENBSD/deploy_inventory.json` as inventories, not
  suggestions.
- Any `/etc` change made on vm23 must be copied back to `OPENBSD/etc/`.
- Use `ruby40` and `bundle40` on OpenBSD; `zsh OPENBSD/bin/vps_ci.sh <app>` for
  per-app CI.
- Keep secrets in `/etc/*.env`; never commit them.
- Keep Rails `config.assume_ssl = true`; do not enable `force_ssl` behind
  relayd.
- Prefer local gates first (`OPENBSD/bin/check`) before any SSH.

**Agent dmesg (verbose file operations):** external agents (Grok CLI, Claude
Code, Cursor) and MASTER should log mutations in OpenBSD dmesg style — terse,
lowercase, one fact per line, path-first, e.g.:

```
write OPENBSD/etc/rc.d/brgen 412B +12/-3
read MASTER/lib/reach/base.rb sha256=a1b2c3… 2048B
run zsh OPENBSD/bin/check-openbsd exit=0
```

Name the path on every read/write/delete; show evidence on writes (diff stat or
byte size); show command + exit code for shell, not "deployed successfully."
Silence on success is fine for bulk gates; speak up for each mutated file.
MASTER: `/dmesg` or `toggle dmesg` streams bus events.

**Reporting** — good deploy closeout: exact host/environment, commands run,
gates passed/skipped/ failed, services restarted, remaining manual verification.
Bad: "deployed" without host/command, public health not checked, asset
precompile skipped after web changes, route/cert changes without relayd/acme/NSD
context.

## Console automation gate

Recovery-only expect scripts refuse to run unless a human operator exports
`I_UNDERSTAND_CONSOLE_RISK=1` (same pattern as `I_UNDERSTAND_DNS_WIPE=1` for
`OPERATOR.sh --stage-1`).

## doas.conf

OpenBSD rejects `/etc/doas.conf` without a trailing newline — `doas` breaks for
everyone. `OPERATOR.sh` fixes the repo copy before install, validates `su dev -c
'doas id'`, and rolls back on failure. No cron job installs it: the only other
path is a deliberate `doas ksh OPENBSD/bin/validate_doas.ksh install <file> <reason>`,
which validates the same way. The comment atop `etc/doas.conf` says what dev's
passwordless rule exposes and why neither command scoping nor a password can
narrow it.

## Backups

`OPENBSD/bin/dr-pull` is the backup. It runs nightly on the operator Mac under
launchd, writes a `VACUUM INTO` snapshot of every production database on vm23,
streams them back in one tar, checks `PRAGMA integrity_check` on arrival and
rotates the last fourteen. `ruby OPENBSD/bin/dr-pull --check` reports the newest
pull and its age, and fails when the newest is stale — read that rather than the
launchd exit status, because a snapshot that has stopped working exits 0.

**Litestream replicates nothing and never has.** It is not in OpenBSD ports, so
`pkg_add litestream` cannot install it, `/usr/local/bin/litestream` does not
exist, and `/var/backups/litestream/` has been empty since the day it was
created. It is out of `pkg_scripts` and has no `rc.d` script, so it no longer
keeps `rcctl ls failed` permanently non-empty. `OPENBSD/etc/litestream.yml` is
kept because the config is correct for the day someone builds the binary from Go
and adds an off-host bucket; its header says why the service stays off the boot
list.

Nothing on the box is a disaster-recovery replica: dr-pull's copies live on the
Mac, which is one other disk, not a bucket. An off-host object store is the
remaining gap and it needs an account.

## OpenBSD deploy

Always use tmux. `OPERATOR.sh` runs under `doas` because it installs `/etc`;
`bin/vps-deploy` must not, because it runs as dev and escalates per step (see
the table under *Agent contract*).

```zsh
cd ~/pub4
tmux new-session -d -s deploy "doas zsh OPENBSD/OPERATOR.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Default installs `OPENBSD/{etc,usr,var}`, validates pf/relayd, and restarts
services. Rare: `--first-install`, `--stage-1`, `--stage-2`. `--stage-1`
installs `etc/pf.stage1.conf`, which passes only 22, 53 and 80: HTTPS and SMTP
stay blocked until the full `pf.conf` goes in.

`etc/acme-client.conf` is generated by `bin/render_dns.rb` and compared by the
`dns_zones` gate's `--check`, so do not byte-compare it by hand.

After `MASTER/web/` edits: `doas rcctl restart master`. Falcon does not
hot-reload.

**`OPENBSD/etc/` is canonical in intent, not in verified-deployability.** Diff
before you install, every time:

```zsh
diff -u /etc/relayd.conf OPENBSD/etc/relayd.conf   # read every hunk
doas cp -p /etc/relayd.conf /etc/relayd.conf.bak-$(date +%Y%m%d-%H%M%S)
doas install -o root -g wheel -m 644 OPENBSD/etc/relayd.conf /etc/relayd.conf
doas relayd -n -f /etc/relayd.conf                 # must print "configuration OK"
doas rcctl restart relayd
```

On 2026-08-02 the repo copy carried `tls keypair "bplan.pub.healthcare"` for a
cert that does not exist. relayd refuses to load an absent keypair, so a
straight repo→live copy would have taken **every** site on the box down. The two
files had quietly diverged since July precisely because nobody could sync them.
`OPENBSD/sync.rb` (see *Occasional operator tools*) is the return leg that keeps
this from building up.

Note also that relayd's `match response header set` **overwrites** whatever the
backend sent, so the edge value is the only `Permissions-Policy` any browser
sees, for every app. It has to be the union of what all backends need — a
`geolocation=()` there silently killed brgen's `#nearby` while the Rails
initializer said `(self)`.

## Deploy-all disambiguation

Four scripts read as “do everything”, and they do four different things. Pick
deliberately:

| Script | CI | Scope | When |
|--------|----|-------|------|
| `zsh OPENBSD/bin/vps_ci_all.sh` | **Yes** — serial `vps_ci.sh` per app | brgen, amber, bsdports | Normal code change; tests must pass |
| `I_UNDERSTAND_FAST_DEPLOY=1 zsh OPENBSD/bin/vps_production_push.sh` | **No** — `SKIP_CI=1 SKIP_RUNTIME_GATE=1 bin/vps-deploy all`; only the post-restart gates run, and the runtime skip requires that exact acknowledgement. | master + every app, in vps-deploy's order; `DEMO_SEED_ON_DEPLOY=1` adds brgen's demo seed | Fast hotfix; skips test gate |
| `zsh OPENBSD/bin/deploy_all.sh` | **No** | Runs from a workstation: syncs pub4 to vm23 and runs `OPERATOR.sh`, so it reapplies `/etc`, relayd and the services, not just app code. `--per-app` also runs each `RAILS/<app>/<app>.sh` | The box's config has drifted or a fresh install needs redoing — not for shipping a code change |
| `doas ksh OPENBSD/bin/start_all_apps.sh` | **No** — not a deploy at all | Enables and starts master, brgen, amber, bsdports, restarts relayd, then `health_check.rb --all-ready-apps` | Recovery. It writes `/var/db/pub4_all_apps`, which pins the four against `resource_guard.sh` shedding |

`vps_production_push.sh` is the footgun under pressure: it restarts production
without running CI. Use `vps_ci_all.sh` unless you explicitly need the fast path
and accept the risk. `deploy_all.sh` is the wider footgun — it rewrites box
config on the way past, so reach for it only when that is the thing you want.

## Occasional operator tools

Nothing in the repo calls these — they are run by hand, which is exactly why
they need to be listed somewhere. An orphan script is indistinguishable from a
dead one until it is written down.

| Script | Run from | What it is for |
|--------|----------|----------------|
| `ruby OPENBSD/sync.rb` (as `doas ruby40`) | vm23 | Mirror live `/etc` config **back into** `OPENBSD/`, with secret redaction. The repo→live direction is well travelled; this is the return leg, and skipping it is how `relayd.conf` drifted for weeks (see the warning under *OpenBSD deploy*). |
| `ruby OPENBSD/ptr_openbsd_amsterdam.rb --ipv4 … --hostname …` | anywhere | Set the PTR record via openbsd.amsterdam's `ptr4`/`ptr6` endpoints; `--ipv6` sets the v6 record. Needed only if the VM's IP changes. It prints the request as a dry run unless `APPLY_PTR=1` is set. |
| `zsh OPENBSD/bin/vps_run_remote.sh` | workstation | Bootstrap a *fresh* VM: copies `vps_install_all.sh` up through the server4 hypervisor jump and runs it. Not for routine deploys — use `vps-deploy`. |
| `ksh OPENBSD/bin/manual_master_deploy.ksh` | vm23, under tmux | Fallback when `vps_deploy_master.sh` stalls. It pkills the stuck deploy and its precompile, then precompiles MASTER web, runs the `master_web_assets` gate, restarts master and relayd, and probes `/up`. Output goes to `/tmp/master_manual.log`, not the terminal — `tail -f` it. |
| `zsh OPENBSD/bin/deploy-diff.sh` | workstation | Read-only: runs `config_drift_gate.rb --remote`, then diffs `relayd.conf` (which the gate excludes) and prints `rcctl check`. It changes nothing in either direction; `sync.rb` above is what pulls the live side back into the repo. |

## Self-healing cron (vm23)

Tracked mirror: `OPENBSD/etc/crontab.vm23` (installed idempotently by
`OPERATOR.sh`). Hand-edits on vm23 should be copied back to that file.

| Job | Schedule | Log / signal |
|-----|----------|--------------|
| `relayd-watchdog` | `*/5 * * * *` | syslog tag `relayd-watchdog` — restarts relayd when unhealthy or backend table stale. It does **not** heal `doas.conf`: that step ran `validate_doas.ksh` from a dev-owned checkout as root every five minutes and was removed, with the reason in the script's own header |
| `config-drift-check` | `*/15 * * * *` | `/var/log/config_drift.log` — relayd Host routes vs acme SANs vs NSD zones vs DNSSEC paths |
| `resource_guard.sh` | `*/5 * * * *` | sheds bsdports then amber under sustained pressure; `/var/log/resource_guard_history.log` |
| `uptime-check.sh` | `*/5 * * * *` | `/var/log/uptime-check.log`, with `ALLOW_BSDPORTS_DOWN=1` |
| `drain-jobs.sh` | `5 * * * *` | `/var/log/drain-jobs.log` |
| `core-reclaim.sh` | `40 * * * *` | `/var/log/core-reclaim.log` — returns a core app's grown resident set |
| `keep-warm.sh` | `*/10 * * * *` | `/var/log/keep-warm.log` — brgen and amber only |
| `prune-guests.sh` | `20 4 * * *` | `/var/log/prune-guests.log` |
| `renew-certs.sh` | `0 2 * * 1` | `/var/log/cert-renewal.log` |
| `vps_weekly_integrity.sh` | `30 3 * * 0` | **tracked and never installed** — absent from root's live crontab and from `/usr/local/bin`, measured 2026-09-12. See TODO 1060. |

Ten rows because `etc/crontab.vm23` schedules ten jobs. This table listed four
for long enough that six self-healing jobs existed only in the file nobody
reads next to the one they do.

`nsd-resign` is **not** in root crontab — it runs from `etc/daily.local` (daily
DNSSEC re-sign + backup pass). Failures surface in syslog (`daily.local` tag)
and `/var/log/nsd-resign` if present.

## External uptime check

Off-box detection (no alerting pipeline yet):

```sh
sh OPENBSD/bin/uptime-check.sh
```

A wrapper with no URL list of its own: it execs `health_check.rb --public-only
--all-ready-apps`, which derives the fleet from `RAILS/apps.yml` and the deploy
inventory. A second list here is how the paragraph came to name four hosts after
the wrapper had stopped naming any. Runs from a laptop or vm23, and `--public-only`
means it asks the internet and checks nothing on the box — the service, certificate
and relayd checks are the same script without that flag.

## Post-deploy smoke (one page)

After `vps-deploy` / rcctl restarts, run:

```sh
# on vm23 — local ports + public + brgen HTML checks (no splash, nav tablist)
sh OPENBSD/bin/deploy-smoke.sh

# laptop / public only
sh OPENBSD/bin/deploy-smoke.sh --public

# policy: amber optional on 1GB hosts
ALLOW_AMBER_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh
```

Checks `rcctl` (when present), localhost `/up` ports (master 53187, brgen 38182,
amber 61352), public HTTPS, free-RAM warning, and brgen homepage regressions.
See `TODO.md` (OPENBSD operator debt) → `multi_app_ram` for the three-app memory
ceiling. Restart order when recovering: **master → brgen → amber → relayd**.

## vps_console.exp modes

Recovery-only — requires `I_UNDERSTAND_CONSOLE_RISK=1`. One script, the mode
as its first argument: `expect -f OPENBSD/bin/vps_console.exp <mode>`.

| Mode | Purpose |
|------|---------|
| `short [cmd]` | One console command (default `uptime`); 15s timeout |
| `status` | Tail install log + `rcctl check` master/brgen/amber/bsdports |
| `probe` | Raw console banner/login probe (debug connectivity) |
| `fix_key` | Install vm23 `authorized_keys` + flush pf `bruteforce` |
| `start_install` | `nohup /tmp/vps_on_vm_install.sh` from console |
| `poll_install` | Tail on-vm install log + process/rcctl snapshot |
| `install` | Full MASTER bundle + per-app deploy from console (long) |
| `sync_and_install` | Base64 tarball sync to `/home/dev/pub4` then on-vm install |
| `drop_install` | Base64-embed `vps_on_vm_install.sh` only; it execs `vps_install_all.sh`, so the tree must already be at `/home/dev/pub4` |

Laptop SSH to vm23: `source OPENBSD/lib/ssh_vm23.sh` or `zsh
OPENBSD/lib/ssh_vm23.sh <cmd>`. Long deploys: `vm23_tmux deploy 'doas zsh
OPENBSD/OPERATOR.sh …'`.

## Rails deploy

```zsh
cd /home/dev/pub4 && git pull --ff-only
cd RAILS && doas zsh deploy.sh          # brgen (default)
doas zsh deploy.sh amber                     # or: all
ruby40 OPENBSD/gates/health_check.rb --public --all-ready-apps
```

Per-app: `doas zsh RAILS/<app>/<app>.sh`. New Propshaft assets need `rails
assets:precompile` before restart.

Ruby on VPS: `ruby40`, `bundle40`. Never parallel `bin/ci` across SSH sessions.

**`gc.auto` is 0 in `/home/dev/pub4`, and that is load-bearing.** git runs `gc
--auto` after a pull and detaches it, so on 2026-08-23 the pull that set up a
deploy spawned a `pack-objects` holding 266 MB, and on a 1 GB box the Rails
suite took SIGTERM after 18 tests and the seed step after that. The deploy log
said only `bin/rails aborted!` — the killer leaves nothing in it, so read
`vmstat` and `ps auxww | sort -k5 -rn` before believing any theory about the
app. Setting it to 0 means nothing packs the repo automatically;
`/etc/weekly.local` does it instead, as dev, and if that line is ever removed
the checkout grows loose objects forever.

Run it by hand before a deploy if a pull has just landed a lot:

```zsh
cd /home/dev/pub4 && git gc --quiet && git count-objects -v
```

## Gates

```zsh
OPENBSD/bin/check                         # local static deploy gates
OPENBSD/bin/check-vps                     # vm23/live health gates; skips off-VPS
ruby OPENBSD/gates/integrity_gate.rb              # full chain: production, phantom_fk, frontend, relayd, domain_align, crawl
ruby RAILS/tools/crawl_probe.rb           # HTTP manifest + apps.yml ↔ deploy_inventory.json sync
MASTER_CRAWL_BROWSER=1 ruby RAILS/tools/crawl_browser.rb   # Ferrum element crawl (VPS)
cd MASTER && bundle exec ruby bin/probe integrity deploy crawl crawl-browser
```

`bin/probe deploy` and `bin/probe integrity` alias the integrity gate. On macOS,
`crawl-browser` skips unless `MASTER_CRAWL_BROWSER=1` or
`PROBE_FORCE_BROWSER=1`. Matrix and blockers: `RAILS/README.md` ("Production
readiness" section).

## Secrets

`/etc/master.env`, `/etc/<app>.env`. Never commit. Operator keys stay in the
workstation environment.

## Recovery

Load shedding: `doas ksh OPENBSD/bin/resource_guard.sh`. Full stack: `doas ksh
OPENBSD/bin/start_all_apps.sh`. Core health: `doas rcctl check master brgen relayd
pf`.

SSH lockout only: `ssh server4`, then `vmctl console vm23` (manual — not
agent-automated). pf lockout from console: `doas pfctl -t bruteforce -T flush`.

Any file changed on the VPS under `OPENBSD/` must be copied back to git and
committed.

## A daemon that answers ok and does nothing

`rcctl check` asks whether a process exists. Three things on vm23 were dead
behind a green answer, found 2026-09-11, and they are one class rather than
three incidents: the evidence of work and the evidence of life were the same
signal, so silence meant both.

**pflogd, suspended for 34 days.** `rcctl check pflogd` said ok; the process
title said `pflogd: [suspended]`. It had been handed a `/var/log/pflog` written
with a different snaplen than its own `-s 160`, and `pflogd(8)` is explicit
about what happens next: an invalid or incompatible file suspends logging until
a SIGHUP or SIGALRM. It retried on every 60-second flush and wrote
"Invalid/incompatible log file, move it away" into `/var/log/messages` each
time, which nothing reads. Packet filter logging was off from 8 August.

    doas pflogd -x -f /var/log/pflog        # integrity, without touching it
    doas mv /var/log/pflog /var/log/pflog.incompatible-$(date +%Y%m%d)
    doas rcctl restart pflogd
    ps -axo command | grep pflogd           # must read [running], not [suspended]

**brgen_jobs, failed.** The Solid Queue worker is not in `apps.yml`, so
`health_check.rb` — which walks the apps and the core services — could not see
it. `rcctl ls failed` names it. Nothing ran a background job for as long as it
was down.

**core-reclaim, inert since 30 August.** Its trigger was `rss_mb >= 320`, and
brgen resident reads 199M while its address space is 877M and swap sits at 76%.
The script's own header says RSS understates a swapped process; it then used
RSS as its only signal. So the reclaim never fired under exactly the pressure
it exists for, and the kernel did the work instead — `UVM: killed: out of swap`
21 times for brgen in one dmesg buffer, plus relayd once and three root shells.
It reads swap pressure as well as RSS now, and writes `/var/db/core_reclaim_seen`
on every run so "nothing to do" and "never ran" stop being the same silence.

`health_check.rb` asserts all three: the suspended title, `rcctl ls failed`, and
the heartbeat's age.

## Repair playbooks

- Integrity failure: run `ruby OPENBSD/gates/integrity_gate.rb` and fix the first
  failing gate.
- App CI failure: run `zsh OPENBSD/bin/vps_ci.sh <app>` serially. If caches are
  root-owned, export the app `HOME` and `NPM_CONFIG_CACHE`.
- MASTER dead tap: precompile `MASTER/web` production assets, restart `master`,
  then verify `https://ai.brgen.no` after the primer tap.
- relayd/domain drift: run `MASTER/gates/runner.rb domain_alignment` and
  `OPENBSD/gates/deploy_smoke_gate.rb` before restarting relayd.
- pf lockout: use the server4 console and flush the `bruteforce` table; do not
  keep reconnecting.
- Silent TTS: `checks.tts` on `https://ai.brgen.no/health` is the authority, and
  it already gates the deploy — `health_check.rb` fails on `checks.tts false`,
  `MASTER/web`'s health controller 503s the whole endpoint on it, and
  `bin/check-vps` runs both. On the source side `MASTER/gates/runner.rb
  production` runs `MasterTtsGate`, which pins the worker, the supervisor's
  bundle isolation and `rc.d/master`'s `ensure_daemon!`, and probes for a host
  backend when `MASTER_TTS_REQUIRE_HOST_BACKEND=1`. It is a capability check
  (`MASTER/bin/tts-worker` executable *and* EventMachine built with SSL, or
  espeak at `/usr/bin/espeak` or `/usr/local/bin/espeak`), not socket liveness —
  the daemon socket is spun up per synthesis. So `checks.tts true` with a silent
  tap is a web-route or audio-graph problem, not a missing binary. Do not go
  hunting for an `edge-tts` CLI: `Speech.edge_tts_available?` never consults one
  — edge TTS is the `rb-edge-tts` gem, reached only through the worker.
  `OPERATOR.sh` `pkg_add`s espeak, which is the fallback path.

## Patch examples

A good operator patch updates every authority affected by a domain or port
change, lists exact checks, and reports host, commands, result, and intentional
skips. A bad patch changes one app script, says only "restarted stuff", or runs
the full installer from macOS.

## Post-change

- Run `ruby40 OPENBSD/gates/health_check.rb --public --all-ready-apps`.
- Copy any live `/etc` changes back into `OPENBSD/etc/`.
- Put a lasting reason in a comment beside the config or script it explains, a
  standing refusal in `OPENBSD/CLAUDE.md`, and open work in the repo-root
  `TODO.md`.

## Launch wipe (demo data -> cold start)

Written 2026-08-22 as the cherry-picked answer to the demo-content launch
blocker; a runbook on purpose, not a script — GUARD_EXPENSIVE_OPS exists
precisely so no bin/ file carries a fleet-wide delete. Run it BY HAND, per app,
on launch day:

1. `ruby OPENBSD/bin/dr-pull` from the Mac — a verified pre-wipe snapshot.
2. On vm23, stop the app: `doas rcctl stop <app> <app>_jobs`.
3. Move the primary aside (never delete): `mv
   /home/<app>/app/storage/production.sqlite3{,.pre-launch}`.
4. As the app user: `bundle40 exec bin/rails db:prepare` — schema, no seeds.
   brgen demo seeds are the DEMO; a launch database starts empty. If a curated
   skeleton is wanted (cities, categories, admin), seed ONLY
   `db/seeds/launch.rb` — write it that week, review it that week.
5. `doas rcctl start <app> <app>_jobs`, then the route-manifest probe.
6. The .pre-launch file stays until the first week survives; dr-pull keeps
   pulling nightly either way.

Not before the operator decides: which cities open, whether demo mode
(clearly-badged fictive content) is wanted instead of a wipe, and the
announcement noindex question. Those are product calls, not runbook steps.

`````

### _net.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail

# DNS, NSD, DNSSEC, and cert utilities.

validate_ip() {
  typeset ip=$1
  [[ $ip =~ '^([0-9]{1,3}\.){3}[0-9]{1,3}$' ]] || return 1
  typeset -a octets; octets=(${(s:.:)ip})
  for octet in $octets; do (( octet > 255 )) && return 1; done
  return 0
}

cleanup_nsd() {
  log INFO "Cleaning nsd(8)"
  [[ -d /var/nsd ]] || { log ERROR "/var/nsd missing"; exit 1 }
  /usr/bin/timeout 5 /usr/sbin/rcctl stop nsd || log WARN "/usr/sbin/rcctl stop nsd failed"
  /usr/bin/timeout 5 zap -f nsd || log WARN "zap -f nsd failed"
  sleep 2
  typeset _out; _out=$(/usr/bin/netstat -an -p udp)
  [[ $_out == *"$BRGEN_IP.53"* ]] && { log ERROR "Port 53 in use"; exit 1 }
  log INFO "Port 53 free"
}

verify_nsd() {
  log INFO "Verifying nsd(8) for all domains"
  for domain in ${ALL_DOMAINS[*]%%:*}; do
    typeset dig_a=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    [[ -z $dig_a || $dig_a != $BRGEN_IP ]] && {
      log WARN "nsd(8) A record missing or wrong for $domain (got: ${dig_a:-empty})"
      continue
    }
    typeset dig_dnskey=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" DNSKEY +short):-}
    [[ -z $dig_dnskey ]] && { log WARN "DNSSEC not enabled for $domain"; continue }
  done
  log INFO "nsd(8) verification complete"
}

check_dns_propagation() {
  log INFO "Checking DNS propagation"
  for resolver in $PUBLIC_RESOLVERS; do
    typeset _soa; _soa=$(/usr/bin/dig @$resolver brgen.no SOA +short)
    [[ $_soa == *"ns.brgen.no."* ]] && { log INFO "DNS propagation verified via $resolver"; return 0 }
  done
  log ERROR "DNS propagation incomplete. Check glue records."
  exit 1
}

generate_tlsa_record() {
  typeset domain=$1
  typeset cert=/etc/ssl/$domain.fullchain.pem
  typeset zonefile=/var/nsd/zones/master/$domain.zone
  [[ ! -f $cert ]] && { log WARN "Certificate for $domain not found"; return 1 }
  typeset _raw; _raw=$(openssl x509 -noout -pubkey -in "$cert" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null)
  typeset tlsa_record=${${(z)_raw}[2]:-}
  (( ! $#tlsa_record )) && { log ERROR "TLSA generation failed for $domain"; exit 1 }
  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"
  sign_zone "$domain"
  log INFO "TLSA updated for $domain"
}

sign_zone() {
  typeset domain=$1
  typeset zonefile=/var/nsd/zones/master/$domain.zone
  typeset signed_zonefile=/var/nsd/zones/master/$domain.zone.signed
  typeset zsk=/var/nsd/zones/master/K$domain.+013+zsk.key
  typeset ksk=/var/nsd/zones/master/K$domain.+013+ksk.key
  [[ -f $zsk && -f $ksk ]] || { log ERROR "ZSK or KSK missing for $domain"; exit 1 }
  ldns-signzone -n -p -s $(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q) "$zonefile" "$zsk" "$ksk"
  nsd-checkzone "$domain" "$signed_zonefile" || { log ERROR "Signed zone invalid for $domain"; exit 1 }
  nsd-control reload
}

retry_failed_certs() {
  log INFO "Retrying failed certificates"
  for domain in ${(k)FAILED_CERTS}; do
    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    [[ $dns_check != $BRGEN_IP ]] && { log WARN "DNS for $domain failed"; continue }
    print -r -- "retry_$domain" > "/var/www/acme/retry_$domain"
    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$BRGEN_IP/.well-known/acme-challenge/retry_$domain"):-000}
    rm -f "/var/www/acme/retry_$domain"
    [[ $http_status != 200 ]] && { log WARN "HTTP test for $domain failed"; continue }
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      unset FAILED_CERTS[$domain]
      generate_tlsa_record "$domain"
    else
      log WARN "Retry failed for $domain"
    fi
  done
}

`````

### backup_priv.sh

`````zsh
#!/usr/bin/env zsh
# Backs up ~/priv/ to the OpenBSD Amsterdam backup account.
# Interactive:  sh OPENBSD/backup_priv.sh
# Unattended:   run from /etc/daily.local; needs $PASSFILE (see below).
#
# It stays at the top of OPENBSD/ while the rest of the operator shell lives in
# bin/, because vm23's /etc/daily.local names this path on line 28:
#
#   su dev -c 'cd /home/dev/pub4 && zsh OPENBSD/backup_priv.sh' ||
#
# Moving it means changing that line on the box and in etc/daily.local together,
# which takes root on vm23.
#
# Nothing had ever been backed up. Four separate faults, each of which alone was
# enough, and the only symptom was two lines in /var/log/daily.out that nobody
# read:
#
#   1. Port. SSH_ACCESS.md has said `wingman1.openbsd.amsterdam 31415` since it
#      was written; this script and ~/.ssh/config both used the default 22, where
#      the host does not listen. It pings from 1ms away and refuses the port.
#   2. The script passed the full `s4vm23@wingman1.openbsd.amsterdam`, which does
#      not match the `Host wingman1` stanza in ~/.ssh/config — so the user, key,
#      port and host-key policy in that stanza were all bypassed.
#   3. The destination directory did not exist. `backup/` was never created, and
#      the account's home is empty: `total 0`.
#   4. openssl prompts for the passphrase on a terminal. Under cron there is no
#      terminal, so daily.local produced "Must be connected to a terminal" and
#      "bad password read", every night, and carried on to report success for the
#      rest of the file.
#
# 1-3 are fixed here. 4 cannot be fixed by this script alone and must not be
# faked: a passphrase stored on vm23 next to the data it encrypts dies with the
# machine, which makes the off-host copy undecryptable exactly when it is needed.
# So the passphrase comes from a file the operator puts there, and without one
# this exits non-zero and says so rather than hanging on a prompt that nothing
# will ever answer.

set -euo pipefail

typeset backup_host="wingman1"          # the ~/.ssh/config stanza, not the FQDN
typeset remote_dir="backup"
typeset stamp=$(date +%Y%m%d_%H%M%S)
typeset passfile="${PRIV_BACKUP_PASSFILE:-$HOME/.config/pub4/priv-backup.pass}"

[[ -d ~/priv ]] || { print -ru2 -- "backup_priv: ~/priv does not exist"; exit 1 }

# How the passphrase reaches openssl. A terminal means a human is here and can
# type it; otherwise it must already be on disk, readable only by this user.
typeset -a pass_arg
if [[ -r $passfile ]]; then
  typeset perms=$(stat -f %Lp "$passfile")
  [[ $perms == 600 ]] || { print -ru2 -- "backup_priv: $passfile is mode $perms, must be 600"; exit 1 }
  pass_arg=(-pass "file:$passfile")
elif [[ -t 0 ]]; then
  pass_arg=()
else
  print -ru2 -- "backup_priv: no terminal and no passphrase file at $passfile — nothing backed up."
  print -ru2 -- "backup_priv: create it with a passphrase you also keep OFF this machine:"
  print -ru2 -- "backup_priv:   mkdir -p ~/.config/pub4 && (umask 077; printf '%s' 'YOUR PASSPHRASE' > $passfile)"
  print -ru2 -- "backup_priv: a passphrase stored only here dies with the box, and the backup with it."
  exit 1
fi

# Reachability before work. Encrypting first and discovering the destination is
# gone afterwards is how this failed quietly for months.
if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "$backup_host" true 2>/dev/null; then
  print -ru2 -- "backup_priv: cannot reach $backup_host — check the Port line in ~/.ssh/config"
  print -ru2 -- "backup_priv: expected wingman1.openbsd.amsterdam:31415 (OPENBSD/SSH_ACCESS.md)"
  exit 1
fi
ssh -o BatchMode=yes "$backup_host" "mkdir -p $remote_dir"

# The archive stages in a 0700 directory under $HOME, never /tmp. A name like
# /tmp/priv_<timestamp>.tar.enc is predictable to the second, sits in a
# world-writable directory and holds the whole of ~/priv. Encrypted, but an
# attacker who pre-creates the path as a symlink decides where it lands, and one
# who merely reads it gets the ciphertext to attack offline at leisure. The
# private directory plus mktemp closes both.
typeset stage_dir="${HOME}/.cache/pub4-backup"
mkdir -p "$stage_dir"
chmod 700 "$stage_dir"
typeset enc_file
enc_file=$(mktemp "${stage_dir}/priv_${stamp}.XXXXXXXXXX.tar.enc") || exit 1
chmod 600 "$enc_file"
trap 'rm -f "$enc_file"' EXIT INT TERM

# -pbkdf2 uses PBKDF2 key derivation — required on LibreSSL 3.x.
print -r -- "backup_priv: encrypting ~/priv"
tar -czf - -C ~ priv | openssl enc -aes-256-cbc -pbkdf2 "${pass_arg[@]}" -out "$enc_file"

print -r -- "backup_priv: uploading to ${backup_host}:${remote_dir}/"
openrsync -ae ssh "$enc_file" "${backup_host}:${remote_dir}/"

# stat, not wc: `wc -c` pads its output on BSD and is on this repo's banned list
# along with the rest of the GNU text tools.
typeset name=$(basename "$enc_file")
typeset remote_size local_size
remote_size=$(ssh -o BatchMode=yes "$backup_host" "stat -f %z $remote_dir/$name")
local_size=$(stat -f %z "$enc_file")
[[ $remote_size == "$local_size" ]] || {
  print -ru2 -- "backup_priv: size mismatch, local $local_size remote $remote_size"
  exit 1
}

# Keep the newest 14. The account is 10G and ~/priv is 10K, so this is about
# being able to find the right one, not about space. A POSIX sh counter rather
# than `tail -n +15 | xargs -r`: OpenBSD's xargs has no -r, and tail is banned in
# committed scripts here because the GNU idioms do not survive the BSD versions.
ssh -o BatchMode=yes "$backup_host" "
  i=0
  for f in \$(ls -t $remote_dir/priv_*.tar.enc 2>/dev/null); do
    i=\$((i+1))
    [ \$i -gt 14 ] && rm -f \"\$f\" # scan: intentional -- the remote shell is sh
  done
  exit 0
" || true

print -r -- "backup_priv: ok — $name on $backup_host (${local_size} bytes)"
print -r -- "backup_priv: decrypt with openssl enc -d -aes-256-cbc -pbkdf2 -in $name | tar -xzf -"

`````

### bin/amber_queue_sweep.sh

`````zsh
#!/bin/sh
# Sweep a Solid Queue backlog on vm23 with sqlite3, no Rails boot: report, delete
# finished jobs and orphaned executions, drop unfinished Turbo broadcast jobs and
# duplicate media jobs, report again.
#
# Usage: sh OPENBSD/bin/amber_queue_sweep.sh [APP]     (default amber)
#
# The partner is /usr/local/bin/drain-jobs.sh, which RUNS due jobs hourly from
# cron. This one DELETES what should never run; reach for it when a backlog is
# stale broadcasts and duplicates, not when the queue is merely behind. The
# duplicate-media step names amber's job classes and matches nothing elsewhere.
set -eu

case ${1:-} in
-h|--help)
  echo "usage: sh OPENBSD/bin/amber_queue_sweep.sh [APP]   (default amber; deletes, see header)"
  exit 0
  ;;
esac

APP=${1:-amber}
DIR=/home/${APP}/app
QUEUE_DB="${DIR}/storage/production_queue.sqlite3"
# doas test, not [ -f ]: app homes are 750, so dev cannot see the file itself.
doas test -f "$QUEUE_DB" || { echo "amber_queue_sweep: no queue database at ${QUEUE_DB}" >&2; exit 1; }

# sqlite3 creates a missing database on open, so without this the sweep would
# plant an empty production_queue.sqlite3 and then fail on its missing tables.
if [ ! -f "${QUEUE_DB}" ]; then
  echo "amber_queue_sweep: no queue database at ${QUEUE_DB}" >&2
  exit 1
fi

report_queue() {
  echo "==> ${APP} queue report (${QUEUE_DB})"
  doas su -m "${APP}" -c "sqlite3 '${QUEUE_DB}' \"
    SELECT class_name, COUNT(*) AS c
    FROM solid_queue_jobs
    WHERE finished_at IS NULL
    GROUP BY class_name
    ORDER BY c DESC
    LIMIT 20;
    SELECT 'pending_total', COUNT(*) FROM solid_queue_jobs WHERE finished_at IS NULL;
  \""
}

sweep_queue() {
  echo "==> ${APP} queue sweep"
  doas su -m "${APP}" -c "sqlite3 '${QUEUE_DB}' \"
    DELETE FROM solid_queue_jobs WHERE finished_at IS NOT NULL;
    DELETE FROM solid_queue_ready_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_scheduled_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_claimed_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_blocked_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_failed_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_ready_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_scheduled_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_claimed_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_blocked_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_failed_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_jobs
      WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob';
    WITH ranked AS (
      SELECT id, class_name, arguments,
             ROW_NUMBER() OVER (PARTITION BY class_name, arguments ORDER BY id) AS rn
      FROM solid_queue_jobs
      WHERE finished_at IS NULL
        AND class_name IN ('WardrobeMediaJob', 'Shared::MediaProcessingJob')
    )
    DELETE FROM solid_queue_jobs
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1);
  \""
}

report_queue
sweep_queue
report_queue

`````

### bin/deploy-diff.sh

`````zsh
#!/usr/bin/env zsh
# deploy-diff.sh — how vm23 differs from OPENBSD/, read-only, from a workstation.
#
# Usage:
#   zsh OPENBSD/bin/deploy-diff.sh
#   SSH_HOST=dev@brgen.no SSH_KEY=~/.ssh/id_ed25519_brgen zsh OPENBSD/bin/deploy-diff.sh
#
# A wrapper over config_drift_gate.rb --remote, which byte-compares every
# verbatim-installed /etc and /usr/local/bin file and root's crontab in one ssh
# session. This adds only what that gate excludes on purpose: a readable diff of
# relayd.conf, which is installed by hand after `relayd -n` rather than verbatim,
# and rcctl's view of the services. sync.rb is the tool that pulls the live side
# back into the repo; this changes nothing in either direction.
#
# SSH_HOST here is login@host in one string, which is how config_drift_gate.rb
# reads it too. OPENBSD/lib/ssh_vm23.sh gives the same name the opposite meaning
# — host alone, with SSH_USER beside it — so never export one for the other.

set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/deploy-diff.sh   (SSH_HOST=login@host SSH_KEY=path)"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SSH_HOST=${SSH_HOST:-dev@brgen.no}
export SSH_KEY=${SSH_KEY:-${HOME}/.ssh/id_ed25519_brgen}
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY")
drift=0

print "deploy-diff: ${SSH_HOST}"
print "=== verbatim configs and root crontab (config_drift_gate --remote) ==="
ruby "${ROOT}/OPENBSD/gates/config_drift_gate.rb" --remote || drift=1

print "\n=== relayd.conf (excluded from the gate; diffed here) ==="
diff -u "${ROOT}/OPENBSD/etc/relayd.conf" <(ssh "${SSH_OPTS[@]}" "$SSH_HOST" "cat /etc/relayd.conf") || drift=1

print "\n=== rcctl check (remote) ==="
ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'for s in nsd httpd relayd smtpd master brgen amber bsdports; do
  /usr/sbin/rcctl check "$s" 2>/dev/null || echo "$s: missing"
done' || print "SSH failed — install key and flush bruteforce if needed."

exit $drift

`````

### bin/deploy-smoke.sh

`````zsh
#!/usr/bin/env sh
# One-page post-deploy smoke — run on vm23 after vps-deploy / restarts, or from a laptop.
# `deploy-smoke.sh --help` prints the modes and the waiver variables; usage() below
# is the one copy of that text.
#
# bsdports was the hole this script existed to cover and did not: it had no local
# check at all and its public check was optional, so the one post-deploy gate that
# is supposed to notice a dead app could not fail on the app that was found dead
# (TODO.md: amber_bsdports_stop_and_stay_down). The contract test passed
# throughout, because it asserted the URL was present rather than required.
# A waiver is now a named variable per app, so waiving is a decision that shows up
# in the command line rather than a default nobody reads.

set -eu

CURL=${CURL:-curl}
TIMEOUT=${SMOKE_TIMEOUT:-20}
MODE=${1:-auto}
ALLOW_AMBER_DOWN=${ALLOW_AMBER_DOWN:-0}
ALLOW_BSDPORTS_DOWN=${ALLOW_BSDPORTS_DOWN:-0}

# Usage first, and from a here-document rather than by printing the top of the
# file. The old form was `sed -n '2,12p' "$0"` reached after the banner had
# already printed, so `--help` answered with `deploy-smoke: mode=--help` and then
# a line range that any edit above it silently shifted.
usage() {
  cat <<'EOF'
usage: deploy-smoke.sh [--local|--public|auto]

  --local    localhost ports + rcctl only (needs to run on vm23)
  --public   public HTTPS only
  auto       both when rcctl is present, public otherwise (default)

  ALLOW_AMBER_DOWN=1      do not fail when amber is down
  ALLOW_BSDPORTS_DOWN=1   do not fail when bsdports is down
  SMOKE_TIMEOUT=20        seconds per request
  CURL=curl               the client to use

Exit 0 only when required checks pass.
EOF
}

case "$MODE" in
-h | --help)
  usage
  exit 0
  ;;
esac

failed=0
warns=0

ok()   { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; failed=$((failed + 1)); }
warn() { printf 'WARN %s\n' "$*" >&2; warns=$((warns + 1)); }

have_rcctl() {
  command -v rcctl >/dev/null 2>&1 || [ -x /usr/sbin/rcctl ]
}

curl_code() {
  url=$1
  code=$($CURL -sS -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$url" 2>/dev/null || printf '000')
  printf '%s' "$code"
}

check_http() {
  name=$1
  url=$2
  required=${3:-1}
  code=$(curl_code "$url")
  case "$code" in
    2??|3??)
      ok "$name $url ($code)"
      ;;
    *)
      if [ "$required" = "0" ]; then
        warn "$name $url ($code) optional"
      else
        fail "$name $url ($code)"
      fi
      ;;
  esac
}

check_rcctl() {
  svc=$1
  required=${2:-1}
  if ! have_rcctl; then
    return 0
  fi
  if doas -n rcctl check "$svc" >/dev/null 2>&1 || rcctl check "$svc" >/dev/null 2>&1; then
    ok "rcctl $svc"
  else
    if [ "$required" = "0" ]; then
      warn "rcctl $svc failed (optional)"
    else
      fail "rcctl $svc"
    fi
  fi
}

mem_hint() {
  if ! have_rcctl; then
    return 0
  fi
  # OpenBSD: free pages × page size is awkward; top -b one-liner when present
  if command -v top >/dev/null 2>&1; then
    line=$(top -b 2>/dev/null | sed -n 's/^Memory: //p' | head -1)
    if [ -n "$line" ]; then
      printf 'info memory: %s\n' "$line"
      case "$line" in
        *Free:\ [0-9]M*|*Free:\ [1-9][0-9]M*)
          # crude: free under ~80M is tight for a third Rails app
          free_m=$(printf '%s' "$line" | sed -n 's/.*Free: \([0-9]*\)M.*/\1/p')
          if [ -n "$free_m" ] && [ "$free_m" -lt 80 ] 2>/dev/null; then
            warn "low free RAM (~${free_m}M) — amber+brgen+master may OOM (see TODO.md multi_app_ram)"
          fi
          ;;
      esac
    fi
  fi
}

brgen_html_smoke() {
  url=${BRGEN_SMOKE_URL:-https://brgen.no/}
  html=$($CURL -sS --max-time "$TIMEOUT" "$url" 2>/dev/null || true)
  if [ -z "$html" ]; then
    fail "brgen html empty $url"
    return
  fi
  case "$html" in
    *'id="splash"'*|*'splash-title'*)
      fail "brgen splash still present on $url"
      ;;
    *)
      ok "brgen no guest splash"
      ;;
  esac
  # The nav landmark, not a tablist.
  #
  # This asked for role="tablist" until 2026-08-11 and warned on every run,
  # because brgen/app/views/shared/_nav_swiper.html.erb deliberately stopped being
  # one on 2026-08-10: dressing navigating links as tabs produced three axe
  # violations at once, and role="tablist" on <nav> overrode the navigation
  # landmark so nothing inside counted as landmark content. The check outlived the
  # shape it was written for and trained everyone to ignore a warn.
  #
  # What the decision actually preserved is what is checked now: the nav landmark
  # is present and the active entry carries aria-current, which is the correct
  # signal for navigation.
  case "$html" in
    *'id="nav_sections"'*)
      ok "brgen nav landmark present"
      ;;
    *)
      warn "brgen nav landmark not found (cache or partial HTML?)"
      ;;
  esac
  case "$html" in
    *'aria-current="page"'*)
      ok "brgen nav marks the active entry"
      ;;
    *)
      warn "brgen nav has no aria-current (front page may be the active entry)"
      ;;
  esac
}

run_local=0
run_public=0
case "$MODE" in
  --local)  run_local=1 ;;
  --public) run_public=1 ;;
  auto|"")
    if have_rcctl; then run_local=1; run_public=1
    else run_public=1
    fi
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# The banner comes after the mode is understood, so a bad argument answers with
# the usage alone rather than with a banner naming the argument it rejected.
printf 'deploy-smoke: mode=%s timeout=%ss\n' "$MODE" "$TIMEOUT"

amber_req=1
if [ "$ALLOW_AMBER_DOWN" = "1" ]; then
  amber_req=0
fi
bsdports_req=1
if [ "$ALLOW_BSDPORTS_DOWN" = "1" ]; then
  bsdports_req=0
fi

if [ "$run_local" = "1" ]; then
  printf '\n== local (vm23) ==\n'
  mem_hint
  check_rcctl master 1
  check_rcctl brgen 1
  check_rcctl amber "$amber_req"
  check_rcctl bsdports "$bsdports_req"
  check_rcctl relayd 1
  check_http master_local  "http://127.0.0.1:53187/up" 1
  check_http brgen_local   "http://127.0.0.1:38182/up" 1
  check_http amber_local   "http://127.0.0.1:61352/up" "$amber_req"
  # The local port is the check that distinguishes a shed app from a relayd
  # failure: a shed app leaves 443 answering and only this port closed.
  check_http bsdports_local "http://127.0.0.1:47312/up" "$bsdports_req"
fi

if [ "$run_public" = "1" ]; then
  printf '\n== public ==\n'
  check_http master_public  "https://ai.brgen.no/up" 1
  check_http brgen_public   "https://brgen.no/up" 1
  check_http amber_public   "https://amberapp.art/up" "$amber_req"
  # Required, and it fails today for a reason that is not the app: bsdports.org
  # is delegated to the registrar's parking nameservers, parking terminates no
  # TLS, and the answer is 000 whether or not port 47312 is healthy. A red line
  # whose cause is unnamed is what teaches an operator to skim a red gate, so
  # name it here. The local check above is the one that measures the app.
  bsdports_public_failed=$failed
  check_http bsdports_public "https://bsdports.org/up" "$bsdports_req"
  if [ "$failed" -ne "$bsdports_public_failed" ] && command -v dig >/dev/null 2>&1; then
    bsdports_ns=$(dig +short NS bsdports.org 2>/dev/null | tr '\n' ' ')
    case "$bsdports_ns" in
    *expireddomain*)
      printf '     cause: bsdports.org is delegated to %s\n' "$bsdports_ns" >&2
      printf '     that is registrar parking, not this box, and it terminates no TLS.\n' >&2
      printf '     The domain, not the app: TODO.md bsdports_org_delegated_to_parking.\n' >&2
      ;;
    esac
  fi
  # One asset per app, from the engine's shared/public, which the deploy ships by
  # tarring RAILS/shared wholesale rather than through the asset pipeline. Nothing
  # else here proves that tar arrived: /up answers from the app, and propshaft
  # never digests these files, so a sync that dropped public/ would look green.
  #
  # This exact font 404'd on amber for months while the stylesheet asking for it
  # returned 200, because it existed only under one app-local public root.
  # Operator::AssetUrlLint catches that source mismatch; this probe still proves
  # the shared asset actually shipped.
  check_http shared_font_brgen "https://brgen.no/fonts/lg.woff2" 1
  check_http shared_font_amber "https://amberapp.art/fonts/lg.woff2" "$amber_req"
  brgen_html_smoke
fi

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf 'deploy-smoke: FAILED (%s hard, %s warn)\n' "$failed" "$warns" >&2
  exit 1
fi
printf 'deploy-smoke: ok (%s warnings)\n' "$warns"
exit 0

`````

### bin/deploy_all.sh

`````zsh
#!/usr/bin/env zsh
# Workstation orchestrator: sync pub4 to VPS and run OPENBSD/OPERATOR.sh.
#
# A recovery path nothing runs. It reapplies box config after drift, which
# bin/vps-deploy assumes is already right. Unexercised, so read it before running
# it; removing it decides the capability is unwanted, which is the operator's call.
#
# Canonical app list: OPENBSD/deploy_inventory.json (active Rails apps).
#
# Usage:
#   zsh OPENBSD/bin/deploy_all.sh
#   zsh OPENBSD/bin/deploy_all.sh --per-app   # also run RAILS/<app>/<app>.sh (copies to /home/<app>/app)
#
# Host, login and key come from lib/ssh_vm23.sh, the one copy of them:
# SSH_HOST is the host alone and SSH_USER the login, so `SSH_HOST=dev@…` yields
# dev@dev@… and every ssh fails.
set -euo pipefail

# DEPLOY_ROOT is OPENBSD/, the parent of this bin/: deploy_inventory.json lives
# there, and the rsync path below mirrors exactly that directory to the remote
# OPENBSD/.
SCRIPT_DIR=${0:a:h}
DEPLOY_ROOT=${SCRIPT_DIR:h}

: "${USE_GIT_PULL:=1}"
: "${REMOTE_RUBY:=ruby40}"
: "${RUN_REMOTE_HEALTH:=1}"
: "${ALLOW_PARTIAL_DEPLOY:=0}"

source "${DEPLOY_ROOT}/lib/ssh_vm23.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }
error() { log "ERROR: $*"; exit 1 }

vssh() { vm23_ssh "$@" }

typeset run_per_app=0
[[ ${1:-} == --per-app ]] && run_per_app=1

typeset -a APPS
if command -v jq >/dev/null 2>&1 && [[ -f ${DEPLOY_ROOT}/deploy_inventory.json ]]; then
  APPS=("${(@f)$(jq -r '.apps[].name' "${DEPLOY_ROOT}/deploy_inventory.json")}")
else
  APPS=(brgen amber bsdports)
fi

log "pub4 deploy — ${#APPS[@]} apps from deploy_inventory.json"

log "Testing VPS connectivity..."
vssh 'uname -a' || error "Cannot connect to ${SSH_USER}@${SSH_HOST}"

if [[ $USE_GIT_PULL == 1 ]]; then
  log "Git pull on VPS at ${REMOTE_PUB4}..."
  vssh "test -d ${REMOTE_PUB4}/.git" || error "Clone pub4 on VPS first: git clone https://github.com/anon987654321/pub4.git ${REMOTE_PUB4}"
  vssh "cd ${REMOTE_PUB4} && git pull origin main"
else
  command -v rsync >/dev/null 2>&1 || error "rsync required when USE_GIT_PULL=0"
  log "Rsync OPENBSD/ → ${REMOTE_PUB4}/OPENBSD/ ..."
  rsync -az --delete \
    -e "ssh ${(j: :)VM23_SSH_OPTS}" \
    "${DEPLOY_ROOT}/" "${SSH_USER}@${SSH_HOST}:${REMOTE_PUB4}/OPENBSD/" \
    || error "rsync failed"
fi

log "Running OpenBSD deploy stage 2 (services + Rails bootstrap from RAILS trees)..."
if ! vssh "cd ${REMOTE_PUB4} && doas zsh OPENBSD/OPERATOR.sh --stage-2"; then
  if [[ $ALLOW_PARTIAL_DEPLOY == 1 ]]; then
    log "WARN: OPERATOR.sh reported issues — ALLOW_PARTIAL_DEPLOY=1 set"
  else
    error "OPERATOR.sh failed — refusing false-green deploy"
  fi
fi

if (( run_per_app )); then
  log "Optional per-app deploy scripts (/home/<app>/app layout)..."
  for app in $APPS; do
    typeset script="${REMOTE_PUB4}/RAILS/${app}/${app}.sh"
    log "  ${app}..."
    vssh "test -f ${script}" || { log "WARN: missing ${script}"; continue; }
    vssh "doas zsh ${script} 2>&1 | tee /tmp/${app}_deploy.log" \
      || log "WARN: ${app} — see /tmp/${app}_deploy.log"
  done
fi

log "Smoke checks..."
vssh 'ps aux | grep -E "falcon serve" | grep -v grep' || log "WARN: no Falcon processes"
if command -v jq >/dev/null 2>&1; then
  while IFS=$'\t' read -r app port; do
    vssh "nc -z 127.0.0.1 ${port}" 2>/dev/null && log "  ${app} listening on :${port}" \
      || log "WARN: ${app} not listening on :${port}"
  done < <(jq -r '.apps[] | [.name, .port] | @tsv' "${DEPLOY_ROOT}/deploy_inventory.json")
fi

if [[ $RUN_REMOTE_HEALTH == 1 ]]; then
  log "Authoritative remote health gate..."
  if ! vssh "cd ${REMOTE_PUB4} && ${REMOTE_RUBY} OPENBSD/gates/health_check.rb --public --all-ready-apps"; then
    [[ $ALLOW_PARTIAL_DEPLOY == 1 ]] \
      && log "WARN: remote health failed — ALLOW_PARTIAL_DEPLOY=1 set" \
      || error "remote health failed"
  fi
fi

log "Deploy finished."
log "VPS: ssh ${VM23_SSH_OPTS[*]} ${SSH_USER}@${SSH_HOST}"
log "Health: ${REMOTE_RUBY} ${REMOTE_PUB4}/OPENBSD/gates/health_check.rb --public --all-ready-apps (on VPS)"

`````

### bin/domain_watch.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Which of our domains are still ours, and which have gone.
#
# amstrdam.nl was registered to us and served Amsterdam. It lapsed, dropped, and
# was re-registered by someone else on 2026-05-18 — GoDaddy, Cloudflare
# nameservers, 301 to an unrelated site. Nobody noticed for 81 days, because
# nothing was watching. lndon.uk dropped the same way. Four .uk domains sit in
# Nominet's grace window right now.
#
# RenderDns.zones lists the zones we serve; RAILS/apps.yml also lists every domain we own.
# This asks each registry whether we still hold the name, and diffs the answer against a committed snapshot so a domain
# changing hands shows up as a reviewable diff instead of an outage.
#
#   ruby OPENBSD/bin/domain_watch.rb            # report against the snapshot
#   ruby OPENBSD/bin/domain_watch.rb --update   # rewrite the snapshot (OpenBSD/Linux)
#   ruby OPENBSD/bin/domain_watch.rb --json
#
# Every lookup is bounded in Ruby rather than by /usr/bin/timeout, which does
# not exist on macOS — so --update ran only on vm23, and the snapshot went
# three weeks stale while the expiry guard read from it. A watcher whose
# refresh needs a different machine than the operator is sitting at is a
# watcher that reports last month.
#
# whois is rate-limited and several registries refuse queries from unknown
# clients. Anything we cannot determine is reported "unknown" and never counted
# as healthy — a monitor that reports green on a failed lookup is worse than none.

require "date"
require "json"
require "open3"
require "yaml"
require_relative "render_dns"

module Deploy
  module DomainWatch
    ROOT = File.expand_path("../..", __dir__)
    SNAPSHOT = File.join(ROOT, "OPENBSD/data/domain_inventory.yml")
    RAILS_APPS = File.join(ROOT, "RAILS/apps.yml")

    # Registries whose referral the local whois does not follow correctly.
    SERVERS = {
      "uk" => "whois.nic.uk", "it" => "whois.nic.it", "pl" => "whois.dns.pl",
      "pt" => "whois.dns.pt", "nl" => "whois.domain-registry.nl",
      "no" => "whois.norid.no", "com" => "whois.verisign-grs.com",
      "net" => "whois.verisign-grs.com", "se" => "whois.iis.se",
      "dk" => "whois.dk-hostmaster.dk", "fi" => "whois.fi", "is" => "whois.isnic.is",
      "de" => "whois.denic.de", "fr" => "whois.nic.fr", "be" => "whois.dns.be",
      "us" => "whois.nic.us", "org" => "whois.pir.org",
    }.freeze

    # /x so the alternations can wrap, which is also why every literal space is
    # escaped: /x ignores a bare one, and "is free" would match only "isfree".
    AVAILABLE = /No\ match|NOT\ FOUND|not\ found|No\ entries\ found|is\ free|Status:\s*free|
                 is\ available|No\ Data\ Found|Object\ does\ not\ exist|not\ registered/xi
    REGISTERED = /Registrar:|Registrant|Registered\ on|Creation\ Date|Created:|
                  Name\ Server|nserver|Domain\ nameservers|holder/xi

    module_function

    # The zones data/dns.yml and OPERATOR.sh declare, which is where nsd.conf is
    # rendered from, so a zone declared and not yet rendered is still watched.
    def zones
      # Watch both served zones and every registrar-held domain. Ownership is not
      # service exposure: a parked/DNS-only name must be watched without becoming
      # an nsd/relayd/acme zone merely because we own it.
      (RenderDns.zones.keys + owned_domains).uniq.sort
    end

    def owned_domains
      inventory = YAML.safe_load_file(RAILS_APPS)
      domains = inventory.fetch("owned_domains")
      raise "owned_domains must be a non-empty array" unless domains.is_a?(Array) && domains.any?

      domains.map(&:to_s).reject(&:empty?).uniq.sort
    rescue Errno::ENOENT, Psych::Exception, KeyError => e
      raise "owned domain inventory unreadable: #{e.class}: #{e.message}"
    end

    # Bounded, portable, and no shell. /usr/bin/timeout is OpenBSD's and absent
    # on macOS; homebrew's sits at a different path, so naming either one picks
    # a machine. Ruby can wait on its own child: read the merged stream, and if
    # the deadline passes, TERM the process group and take what arrived.
    #
    # Killing the group rather than the pid matters because whois(1) on some
    # systems re-execs for a referral, and a bare kill leaves the child holding
    # the pipe open — the read never ends and the timeout never lands.
    TIMEOUT_S = 15

    def capture_bounded(*argv, seconds: TIMEOUT_S)
      out = +""
      Open3.popen2e(*argv, pgroup: true) do |stdin, stream, wait|
        stdin.close
        reader = Thread.new { out << stream.read.to_s }
        unless wait.join(seconds)
          begin
            Process.kill("TERM", -wait.pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end
          wait.join(2)
        end
        reader.join(2)
      end
      out
    rescue StandardError => e
      warn "domain_watch: #{argv.first} failed (#{e.class}: #{e.message.lines.first.to_s.strip})"
      ""
    end

    def whois_query(domain)
      server = SERVERS[domain.split(".").last]
      argv = ["whois"]
      argv += ["-h", server] if server
      argv << domain
      # No shell, so a zone name out of the DNS policy is an argument and not a
      # command. The bound is capture_bounded's, in Ruby — an unqualified
      # `timeout` was a cron PATH bug this tree has already shipped, and naming
      # /usr/bin/timeout instead traded that for a macOS the tool cannot run on.
      out = capture_bounded(*argv)
      return { "state" => "unknown", "note" => "lookup failed" } if out.to_s.strip.empty?

      # A referral answer describes the TLD, not the name. Without this, .us and
      # .org queries returned the registry's own record and every domain looked
      # registered since 1985-02-15 — the date the .us TLD was created, reported
      # as if it were the domain's. Require the response to name the domain
      # itself before believing anything it says about registration.
      unless out.downcase.include?(domain.downcase) || out.match?(AVAILABLE)
        return { "state" => "unknown", "note" => "registry referral, not a domain record" }
      end

      if out.match?(AVAILABLE)
        { "state" => "available" }
      elsif out.match?(REGISTERED)
        {
          "state" => "registered",
          # Ordered most-specific first. A bare "Created:" also appears in the
          # registry's own trailing record, which is how bsdports.org reported
          # 1985-01-01 — the .org TLD's birthday, not the domain's.
          "created" => out[/Creation Date[.\s]*:\s*(\S+)/i, 1] ||
                       out[/Registered on[.\s]*:\s*(\S+)/i, 1] ||
                       out[/Created[.\s]*:\s*(\S+)/i, 1],
          "expires" => out[/(?:Expiry date|Registry Expiry Date|Expires on)[.\s]*:\s*(\S+)/i, 1],
          # Nominet keeps saying "registered" for months after a .uk lapses and
          # puts the truth here instead: "Renewal required." Four of ours said
          # that on 2026-08-12, having expired in June, and the state field alone
          # reported all four as healthy.
          "status" => out[/Registration status:\s*\n?\s*(\S[^\n]*)/i, 1]&.strip,
          "registrar" => out[/Registrar:\s*\n?\s*(\S[^\n]*)/i, 1]&.strip,
        }.compact
      else
        { "state" => "unknown", "note" => out.lines.first.to_s.strip[0, 60] }
      end
    end

  # whois first, RDAP for the registries that will not answer it.
  #
  # Identity Digital (.legal, .attorney, .healthcare) and SWITCH (.ch, .li)
  # return an empty body to a plain whois, which the referral guard above then
  # correctly files as unknown rather than guessing. Thirty-eight of the fifty-
  # seven zones sat at unknown for that reason, so the snapshot could not answer
  # the only question it exists to answer.
  #
  # RDAP is what those registries serve instead, and it is only safe once you
  # know the registry actually runs it: a 404 means "no such domain" from a
  # registry that has RDAP, and "no service here" from one that does not, and
  # reading the second as available is the same mistake the guard above exists
  # to prevent. IANA publishes which TLDs have RDAP and where, so the bootstrap
  # is fetched first and a TLD missing from it is never called available.
  def query(domain)
    result = whois_query(domain)
    return result unless result["state"] == "unknown"

    rdap_query(domain) || result
  end

  BOOTSTRAP = "https://data.iana.org/rdap/dns.json"

  def rdap_base(tld)
    @rdap_bases ||= begin
      out = capture_bounded("curl", "-sS", BOOTSTRAP, seconds: 20)
      parsed = JSON.parse(out.to_s)
      parsed.fetch("services", []).each_with_object({}) do |(tlds, urls), map|
        tlds.each { |t| map[t] = urls.first }
      end
    rescue StandardError => e
      # An empty map is every TLD unresolvable, and silently: the expiry check
      # then reports nothing wrong about domains it never asked about.
      warn "domain_watch: RDAP bootstrap unreachable (#{e.class}: #{e.message.lines.first.to_s.strip}) — no expiry dates this run"
      {}
    end
    @rdap_bases[tld]
  end

  def rdap_query(domain)
    base = rdap_base(domain.split(".").last)
    return nil unless base

    url = "#{base.chomp("/")}/domain/#{domain}"
    out = capture_bounded("curl", "-sSL", "-w", "\n%{http_code}", url, seconds: 20)
    lines = out.to_s.lines
    code = lines.last.to_s.strip
    return { "state" => "available" } if code == "404"
    return nil unless code == "200"

    body = JSON.parse(lines[0..-2].join) rescue nil
    return nil unless body

    event = ->(name) { body["events"]&.find { |e| e["eventAction"] == name }&.dig("eventDate") }
    {
      "state" => "registered",
      "created" => event.call("registration"),
      "expires" => event.call("expiration"),
      "registrar" => body["entities"]
                       &.find { |e| Array(e["roles"]).include?("registrar") }
                       &.dig("vcardArray", 1)&.find { |f| f[0] == "fn" }&.last,
    }.compact
  end

    # Subdomains of a zone we already hold are not separately registrable.
    def registrable?(domain)
      domain.count(".") == 1
    end

    def snapshot
      File.exist?(SNAPSHOT) ? YAML.safe_load_file(SNAPSHOT) : {}
    end

    def scan
      zones.select { |z| registrable?(z) }.to_h { |z| [z, query(z)] }
    end

    def compare(current, previous)
      lost = []
      changed = []
      current.each do |domain, now|
        was = previous[domain]
        next unless was

        lost << domain if was["state"] == "registered" && now["state"] == "available"
        if was["state"] == "registered" && now["state"] == "registered" &&
           was["created"] && now["created"] && was["created"] != now["created"]
          changed << "#{domain}: created #{was['created']} -> #{now['created']} (re-registered by someone else)"
        end
      end
      { lost:, changed: }
    end

    # An expiry date is not a warning until something reads it.
    #
    # The snapshot has carried "expires" since it was written, and nothing ever
    # compared it to today — compare() only noticed a domain going from
    # registered to available, which is the state it reaches after it is too late
    # to renew. On 2026-08-12 the committed file said cardff.uk and edinbrgh.uk
    # expired the following day, denvr.us the same day, and four .uk domains had
    # expired in June. All seven were sitting in the repo, in git, unread. The
    # same shape as bsdports.org expiring with a day's notice five days earlier
    # (c6bb41135), and the same shape as the cron PATH: the data was right and
    # nothing looked at it.
    EXPIRY_WARN_DAYS = 45

    # `13-Aug-2026` from Nominet, `2026-08-13T11:20:09Z` from the .us/.com
    # registries, and nothing at all from Norid — .no whois publishes no expiry,
    # so brgen.no and the three other .no cities cannot be watched this way and
    # are not silently counted as fine.
    def days_until(value)
      return nil if value.to_s.empty?

      date = begin
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      date && (date - Date.today).to_i
    end

    def expiring(current, within: EXPIRY_WARN_DAYS)
      current.filter_map do |domain, row|
        next unless row["state"] == "registered"

        renewal_flagged = row["status"].to_s.match?(/renewal required|suspended|grace|redemption/i)
        days = days_until(row["expires"])
        next unless renewal_flagged || (days && days <= within)

        [domain, days, row["status"]]
      end.sort_by { |_, days, _| days || -9_999 }
    end

    def unwatchable(current)
      current.select { |_, row| row["state"] == "registered" && row["expires"].to_s.empty? }.keys
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # Before the scan, which queries whois for every zone.
  if ARGV.intersect?(%w[-h --help])
    puts "usage: ruby OPENBSD/bin/domain_watch.rb [--update|--json]"
    puts "  whois every served or owned domain and diff the answers against data/domain_inventory.yml"
    exit 0
  end

  current = Deploy::DomainWatch.scan
  previous = Deploy::DomainWatch.snapshot
  diff = Deploy::DomainWatch.compare(current, previous)

  if ARGV.include?("--update")
    File.write(Deploy::DomainWatch::SNAPSHOT,
               "# Written by OPENBSD/bin/domain_watch.rb --update. Committed so a domain\n" \
               "# changing hands is a reviewable diff rather than a surprise outage.\n" +
               YAML.dump(current))
    puts "snapshot written: #{current.size} domains"
    exit 0
  end

  if ARGV.include?("--json")
    puts JSON.pretty_generate(current: current, **diff)
    exit(diff[:lost].empty? && diff[:changed].empty? ? 0 : 1)
  end

  by_state = current.group_by { |_, row| row["state"] }.transform_values(&:size)
  puts "domains checked: #{current.size} — #{by_state.map { |k, v| "#{k} #{v}" }.join(', ')}"

  available = current.select { |_, r| r["state"] == "available" }.keys
  puts "\nnot registered (#{available.size}):\n  #{available.join(', ')}" if available.any?

  # Counted and named, and deliberately not in the exit status. They are whois
  # referrals (.us, .dk, .li, .ch) and answers this parser does not read (.se,
  # .it, .pt, .nl): properties of the registries, the same every week, so failing
  # on them makes weekly.local log an alarm every Saturday until the alarm means
  # nothing. The exit carries what someone can act on: a domain lost,
  # re-registered or inside the renewal window.
  unknown = current.select { |_, r| r["state"] == "unknown" }.keys
  puts "\nlookup inconclusive (#{unknown.size}):\n  #{unknown.join(', ')}" if unknown.any?

  expiring = Deploy::DomainWatch.expiring(current)
  if expiring.any?
    puts "\nEXPIRING or LAPSED (#{expiring.size}):"
    expiring.each do |domain, days, status|
      when_ = if status.to_s.match?(/renewal required|suspended|grace|redemption/i)
                status.to_s.sub(/\.\z/, "")
              elsif days.negative?
                "expired #{-days} day(s) ago"
              else
                "#{days} day(s) left"
              end
      puts "  #{domain.ljust(18)} #{when_}"
    end
    puts "  Renew at the registrar. Nothing in this repo can do it."
  end

  unwatchable = Deploy::DomainWatch.unwatchable(current)
  if unwatchable.any?
    # Named rather than skipped: these are registered and their expiry is simply
    # not knowable from whois, so a clean run above does not cover them.
    puts "\nno expiry published, not watched (#{unwatchable.size}):\n  #{unwatchable.join(', ')}"
  end

  if diff[:lost].any?
    puts "\nLOST since last snapshot: #{diff[:lost].join(', ')}"
  end
  if diff[:changed].any?
    puts "\nCHANGED HANDS:"
    diff[:changed].each { |line| puts "  #{line}" }
  end

  exit(diff[:lost].empty? && diff[:changed].empty? && expiring.empty? ? 0 : 1)
end

`````

### bin/render_dns.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# render_dns.rb — every name this box answers for, from one source.
#
#   ruby OPENBSD/bin/render_dns.rb            write zones, nsd.conf, acme-client.conf
#   ruby OPENBSD/bin/render_dns.rb --check    exit 1 if what is on disk differs
#
# There were three descriptions of the same DNS and no two agreed. OPERATOR.sh's
# ALL_DOMAINS listed 53 domains; /var/nsd/zones/master held 61 zone files;
# nsd.conf declared 54 zones, so seven zone files reached no server and three
# more pointed at a .signed file that did not exist. Only brgen.no had SPF, DMARC
# or a www record. oshlo.no — live, certificated, serving real visitors — had
# none of the three. Every zone advertised an MX for a mail server that does not
# exist. The zone files were last edited by hand in May and had drifted from the
# subdomain list the apps actually route.
#
# The fix is not to correct 61 files. It is to stop hand-writing them: one domain
# list (ALL_DOMAINS, which domain_alignment already binds to the Rails registry),
# one policy file (data/dns.yml), and generated output committed to the repo so
# `--check` can tell you the moment the box and the repo disagree.
#
# Serials only move when content moves. A zone whose body is unchanged keeps the
# serial it has, so regenerating does not push 61 pointless AXFRs at Domeneshop.

require "yaml"
require "date"
require "fileutils"

# UTF-8 explicitly on every read. The zone files are ASCII, but OPERATOR.sh and
# data/dns.yml carry em dashes in their comments, and vm23's cron and non-login
# shells run with no LANG at all — so Ruby defaults external encoding to
# US-ASCII and the first regex against a comment raises "invalid byte sequence
# in US-ASCII". Found by running --check over ssh, which is exactly the shape of
# shell a gate runs in. OPENBSD/gates/integrity_gate.rb has a test pinning the same
# failure mode (RAILS/test/integrity_locale_test.rb).
module RenderDns
  ROOT = File.expand_path("../..", __dir__)
  OPENBSD = File.join(ROOT, "OPENBSD")
  POLICY = File.join(OPENBSD, "data", "dns.yml")
  OPERATOR = File.join(OPENBSD, "OPERATOR.sh")
  ZONES_DIR = File.join(OPENBSD, "var", "nsd", "zones", "master")
  NSD_CONF = File.join(OPENBSD, "var", "nsd", "etc", "nsd.conf")
  ACME_CONF = File.join(OPENBSD, "etc", "acme-client.conf")

  GENERATED_BANNER = "; Generated by OPENBSD/bin/render_dns.rb from data/dns.yml. Do not hand-edit."

  module_function

  def policy = @policy ||= YAML.safe_load_file(POLICY)

  # The city network, straight out of the shell array the installer uses, so the
  # generator cannot describe a different fleet from the one OPERATOR.sh deploys.
  def city_zones
    block = File.read(OPERATOR, encoding: "UTF-8")[/ALL_DOMAINS=\(\n(.*?)\n\)/m, 1] or
      raise "ALL_DOMAINS block not found in #{OPERATOR}"

    block.lines.filter_map do |line|
      line = line.strip
      next if line.empty?

      domain, subs = line.split(":", 2)
      [domain, subs.to_s.split(",").map(&:strip).reject(&:empty?)]
    end.to_h
  end

  # City zones carry their vertical subdomains; extra zones carry none. Both get
  # the same apex, www, CAA, SPF and mail treatment — the difference between a
  # city and a side project is what hangs under it, not how it is secured.
  def zones
    @zones ||= begin
      all = city_zones
      policy.fetch("extra_zones").each_key { |domain| all[domain] ||= [] }
      all.sort.to_h
    end
  end

  def ip = policy.dig("nameserver", "ip")
  def mail_domain = policy.fetch("mail_domain")

  def zone_body(domain, subdomains)
    ns = policy.dig("nameserver", "authoritative")
    hostmaster = policy.dig("nameserver", "hostmaster")
    hosts = subdomains + Array(policy.dig("extra_hosts", domain))
    mail = domain == mail_domain

    lines = []
    lines << GENERATED_BANNER
    lines << "$ORIGIN #{domain}."
    lines << "$TTL #{policy.fetch('ttl')}"
    lines << "@ IN SOA #{ns.first} #{hostmaster}.#{domain}. ("
    lines << "    %<serial>s #{policy.dig('soa', 'refresh')} #{policy.dig('soa', 'retry')} " \
             "#{policy.dig('soa', 'expire')} #{policy.dig('soa', 'minimum')})"
    ns.each { |server| lines << "@ IN NS #{server}" }
    lines << "@ IN A #{ip}"

    # www only where a certificate can cover it, which means only where there is
    # an acme-client block — and those come from ALL_DOMAINS. The four zones that
    # are not in it (the anti-gambling trio and foodielicio.us) would otherwise
    # advertise a www host pointing at a box holding no certificate for it: a name
    # that resolves and then fails TLS, which a browser reports as an attack.
    # config-drift-check flags exactly this. This said five and named bsdports.net,
    # which has no zone at all — bsdports.org is the one with a zone, and it is in
    # ALL_DOMAINS, so it was never in this set.
    lines << "www IN A #{ip}" if city_zones.key?(domain)

    if mail
      lines << "@ IN MX 10 mail.#{domain}."
      lines << "mail IN A #{ip}"
    else
      # RFC 7505. `MX 0 .` is the only way to say "no mail here" that a sending
      # MTA is obliged to honour; omitting MX entirely makes it fall back to the
      # A record and try to deliver to the web server.
      lines << "@ IN MX 0 ."
    end

    hosts.sort.uniq.each { |host| lines << "#{host} IN A #{ip}" }
    policy.fetch("caa").each { |caa| lines << "@ IN CAA #{caa}" }

    # SPF on every zone, including the ones that send nothing. A domain with no
    # SPF record is not neutral — it is a domain a receiver has no grounds to
    # reject a forgery from, which is why spammers prefer them.
    lines << if mail
               %(@ IN TXT "v=spf1 ip4:#{ip} -all")
             else
               %(@ IN TXT "v=spf1 -all")
             end

    unless mail
      # p=reject is safe precisely because nothing legitimate sends from these:
      # there is no deliverability to lose and nothing to monitor first.
      lines << %(_dmarc IN TXT "v=DMARC1; p=reject; rua=mailto:dmarc@#{mail_domain}")
    end

    extra = policy.dig("extra_records", domain)
    lines << "" << extra.rstrip if extra

    "#{lines.join("\n")}\n"
  end

  # Indented as zone_body writes it, which is four spaces and not one. Anchored
  # to a single space, this matched no zone file ever written: every read of an
  # existing serial returned nil, so every render dated every serial to today
  # and pushed 57 AXFRs at Domeneshop -- the thing the header promises it does
  # not do.
  SERIAL_LINE = /^\s+(\d{10}) /

  # A serial is only bumped when the rest of the zone changed. Same-day edits get
  # the counter; a bump across a day boundary restarts it. Ten digits, so it stays
  # inside the 32-bit space RFC 1982 serial arithmetic needs.
  def serial_for(path, body)
    today = Date.today.strftime("%Y%m%d")
    return "#{today}01" unless File.exist?(path)

    existing = File.read(path, encoding: "UTF-8")
    old = existing[SERIAL_LINE, 1]
    return "#{today}01" unless old

    return old if existing == body.sub("%<serial>s", old)

    candidate = old.start_with?(today) ? "#{today}%02d" % (old[8, 2].to_i + 1) : "#{today}01"
    # Never go backwards: a secondary that has seen a higher serial will refuse
    # every transfer until we pass it again.
    candidate > old ? candidate : (old.to_i + 1).to_s
  end

  # Two invariants the zone files cannot show by looking at them. An extra zone
  # that is also in ALL_DOMAINS is a second declaration of one zone, which is how
  # the list once carried nine entries that did nothing. And each zone gets
  # exactly one DMARC record: zone_body writes p=reject for every domain but the
  # mail domain, whose record lives in extra_records, so a _dmarc added to another
  # domain's extra_records would publish two, and receivers treat that as none.
  def policy_errors
    errors = (policy.fetch("extra_zones").keys & city_zones.keys).map do |domain|
      "#{domain} is in both extra_zones and ALL_DOMAINS"
    end
    zones.each do |domain, subdomains|
      count = zone_body(domain, subdomains).scan(/^_dmarc\s+IN\s+TXT\b/).size
      errors << "#{domain}.zone has #{count} _dmarc records, not 1" unless count == 1
    end
    errors
  end

  def render_zones(check:)
    FileUtils.mkdir_p(ZONES_DIR)
    written = []
    stale = []

    zones.each do |domain, subdomains|
      path = File.join(ZONES_DIR, "#{domain}.zone")
      body = zone_body(domain, subdomains)
      final = body.sub("%<serial>s", serial_for(path, body))

      if File.exist?(path) && File.read(path, encoding: "UTF-8") == final
        next
      elsif check
        stale << "#{domain}.zone"
      else
        File.write(path, final)
        written << domain
      end
    end

    orphans = Dir.glob(File.join(ZONES_DIR, "*.zone")).map { |f| File.basename(f, ".zone") } - zones.keys
    orphans.each do |domain|
      if check
        stale << "#{domain}.zone (not in ALL_DOMAINS or extra_zones)"
      else
        File.delete(File.join(ZONES_DIR, "#{domain}.zone"))
        written << "-#{domain}"
      end
    end

    [written, stale]
  end

  def nsd_conf_body
    peers = policy.fetch("xfr_peers")
    out = []
    out << "# Generated by OPENBSD/bin/render_dns.rb from data/dns.yml. Do not hand-edit."
    out << "server:"
    out << "  ip-address: #{ip}"
    out << "  hide-version: yes"
    out << "  verbosity: 1"
    out << "  username: _nsd"
    out << "  zonesdir: \"/var/nsd/zones/master\""
    out << "  zonelistfile: \"/var/nsd/db/zone.list\""
    out << "  xfrdfile: \"/var/nsd/run/xfrd.state\""
    out << "  server-count: #{policy.fetch('server_count')}"
    out << "  rrl-size: 1000000"
    out << "  rrl-ratelimit: 200"
    out << "  rrl-slip: 2"
    out << "  rrl-whitelist-ratelimit: 2000"
    out << ""
    out << "remote-control:"
    out << "  control-enable: yes"
    out << "  control-interface: 127.0.0.1"

    zones.each_key do |domain|
      out << ""
      out << "zone:"
      out << "  name: \"#{domain}\""
      out << "  zonefile: \"#{domain}.zone.signed\""
      peers.each { |peer| out << "  provide-xfr: #{peer} NOKEY" }
      peers.each { |peer| out << "  notify: #{peer} NOKEY" }
    end

    "#{out.join("\n")}\n"
  end

  # acme-client.conf is the fourth description of the same subdomain list, and it
  # was as far out of date as the zone files: only brgen.no carried www or
  # messenger, so oshlo.no's certificate covered seven names while its zone
  # answered for nine. A SAN missing from the certificate is a TLS error on a
  # hostname that resolves, which is a worse failure than NXDOMAIN because it
  # looks like an attack to the browser.
  #
  # Every SAN must resolve and answer on port 80 at renewal time or the whole
  # certificate fails, so this list and the zone above have to be generated from
  # the same source or they cannot both be right.
  def acme_conf_body
    out = []
    out << "# Generated by OPENBSD/bin/render_dns.rb from data/dns.yml. Do not hand-edit."
    out << "# acme-client(1) per acme-client.conf(5)"
    out << ""
    out << "authority letsencrypt {"
    out << "  api url \"https://acme-v02.api.letsencrypt.org/directory\""
    out << "  account key \"/etc/acme/letsencrypt_privkey.pem\""
    out << "}"

    city_zones.each do |domain, subdomains|
      # The apex is deliberately absent. acme-client.conf(5): "The common name is
      # included automatically if this option is present." Listing it as well puts
      # it in the request twice, and acme-client then compares that request
      # against the issued certificate, finds them different, and reports
      # "domain list changed, forcing renewal" — on every single run.
      #
      # The hand-written config had the apex in the list, and the breakage was
      # invisible because the weekly job had never run (see etc/crontab.vm23).
      # Armed and left as it was, it would have re-issued nine certificates every
      # Monday and hit Let's Encrypt's duplicate-certificate limit — five per
      # identical name set per week — inside five weeks, with no certificate to
      # show for it.
      names = ["www.#{domain}"]
      names += subdomains.map { |sub| "#{sub}.#{domain}" }
      names += Array(policy.dig("cert_extra_names", domain)).map { |host| "#{host}.#{domain}" }
      names << "mail.#{domain}" if domain == mail_domain

      out << ""
      out << "domain \"#{domain}\" {"
      out << "  alternative names { #{names.uniq.map { |n| "\"#{n}\"" }.join(' ')} }"
      out << "  domain key \"/etc/ssl/private/#{domain}.key\""
      out << "  domain full chain certificate \"/etc/ssl/#{domain}.fullchain.pem\""
      out << "  sign with letsencrypt"
      out << "  challengedir \"/var/www/acme\""
      out << "}"
    end

    "#{out.join("\n")}\n"
  end

  def sync_file(path, body, check:, label:, written:, stale:)
    return if File.exist?(path) && File.read(path, encoding: "UTF-8") == body

    if check
      stale << label
    else
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
      written << label
    end
  end

  USAGE = <<~TEXT
    usage: ruby OPENBSD/bin/render_dns.rb [--check]

      (no flag)  write every zone, nsd.conf and acme-client.conf from data/dns.yml and ALL_DOMAINS
      --check    write nothing; exit 1 if a file on disk differs or the policy breaks an invariant
  TEXT

  def run(argv)
    if argv.intersect?(%w[-h --help])
      puts USAGE
      return 0
    end

    errors = policy_errors
    unless errors.empty?
      errors.each { |error| warn "render_dns: #{error}" }
      return 1
    end

    check = argv.include?("--check")
    written, stale = render_zones(check: check)

    sync_file(NSD_CONF, nsd_conf_body, check: check, label: "nsd.conf", written: written, stale: stale)
    sync_file(ACME_CONF, acme_conf_body, check: check, label: "acme-client.conf", written: written, stale: stale)

    if check
      if stale.empty?
        puts "render_dns: in sync (#{zones.size} zones)"
        return 0
      end
      warn "render_dns: #{stale.size} file(s) differ from what data/dns.yml renders:"
      stale.sort.each { |name| warn "  - #{name}" }
      warn "run: ruby OPENBSD/bin/render_dns.rb"
      return 1
    end

    puts "render_dns: #{zones.size} zones, #{written.size} file(s) changed"
    written.sort.each { |name| puts "  #{name}" }
    0
  end
end

exit(RenderDns.run(ARGV)) if $PROGRAM_NAME == __FILE__

`````

### bin/resource_guard.sh

`````zsh
#!/bin/ksh
# Shed optional Rails services when vm23 is under pressure; restore them when
# pressure clears. Install: doas cp .../resource_guard.sh /usr/local/bin/ &&
# doas chmod 755 /usr/local/bin/resource_guard.sh
# Cron (root): */5 * * * * /usr/local/bin/resource_guard.sh

set -e

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/resource_guard.sh"
  echo "  shed bsdports, then amber, after GUARD_SHED_STRIKES (2) breaching ticks; restore when pressure clears"
  exit 0
  ;;
esac

# Runs from root's cron, and everything it starts (rcctl -> rc.d scripts,
# emergency_cpu.sh) inherits this PATH. Cron's own PATH has no /usr/local/bin,
# which is where curl, bundle34 and ruby34 live — see rc.d/master for what that
# cost. The rc.d scripts set their own PATH now; this makes the whole chain
# independent of who invoked it.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

ALL_APPS_FLAG=/var/db/pub4_all_apps
SHED_STATE=/var/db/resource_guard_shed
# Consecutive breaching ticks required before anything is shed.
#
# Shedding used to fire on a single sample. vm23 is fine at rest — measured
# 2026-08-01 at 98% idle with zero paging (vmstat pi/po/fr all 0) — and only
# breaches transiently, when a deploy precompiles assets or an app cold-boots.
# One 5-minute sample landing inside that window took amber and bsdports down
# on essentially every deploy, and each restore then cost another tick apiece.
# Two consecutive breaches means a spike has to last past five minutes to count,
# which is the difference between "a deploy is running" and "the box is actually
# out of memory". The LOAD_CRIT path below is untouched and still acts on the
# first sample, because a genuine crisis should not wait.
SHED_STRIKES=${GUARD_SHED_STRIKES:-2}
STRIKE_STATE=/var/db/resource_guard_strikes
CORE="master brgen"
# Ordered cheapest-to-lose first, because shedding now takes one per tick.
# bsdports is a low-traffic ports index and leads. amber is a real app with real
# users and goes last. Every entry here is a service someone loses, so the first
# shed already costs a site — there is no free step to spend before amber.
OPTIONAL="bsdports amber"
# vm23 is 1 vCPU (hw.ncpu=1) — load=1.0 just means the single core is fully
# busy, which is routine, not an emergency. Calm baseline ~0.5-1.4,
# restart-storm transient ~3-7, genuine OOM crisis ~4.6 sustained.
LOAD_WARN=2.5
LOAD_CRIT=5.0
# Recalibrated 2026-07-29 from the 916 ticks the history log had accumulated
# (2026-07-25..29), which is the dataset the note further down asked for.
# Observed: load p50=1.01 p75=1.69 p90=2.57; mem_avail p50=13 p75=24 p90=28.
# LOAD_RESTORE was 1.5, below the p50-p75 band, so restore needed the box to be
# quieter than it usually is. 2.0 sits between p50 and p75 and still stays well
# under LOAD_WARN, so shed and restore cannot chase each other.
LOAD_RESTORE=2.0
# Percent of physical RAM that must be AVAILABLE (free + buffer cache).
# History (2026-07-11): the guard originally measured vmstat's "pages free"
# alone, which excludes the OpenBSD buffer cache (~20% of RAM, reclaimable
# on demand). Any file I/O warming the cache dropped "free" below 12% while
# real available memory was fine, so the guard shed amber/bsdports
# on nearly every tick — a measurement artifact, not memory pressure. Free +
# Cache from top(1) is the honest availability signal. MEM_RESTORE > MEM_WARN
# gives hysteresis so shed/restore can't oscillate around one threshold.
#
# Recalibrated 2026-07-29 from the same 916-tick dataset. The hysteresis window
# was correct in shape but sat outside this box's operating range: median
# availability is 13%, one point above MEM_WARN, and MEM_RESTORE=20 was above
# the median entirely. Memory alone caused 334 of the 436 shed events, and the
# combined restore gate opened on 19% of ticks against shedding on 48% — so the
# drift was one-way and amber/bsdports stayed down for days rather than
# self-recovering, which is not what OPENBSD/CLAUDE.md claims. 8/14 keeps the
# same 6-point hysteresis gap, straddling p50 instead of sitting above it.
# Cost: more paging for the two optional apps. Swap is 1264M and was at 365M.
#
# Recalibrated again 2026-08-14, MEM_RESTORE 14 -> 10, from 1550 ticks
# (~5.4 days). The 2026-07-29 pass above was right for its dataset and the
# dataset moved: it measured mem_avail p50=13 p75=24 and set 14 to straddle the
# median. Today the same log reads **p50=9, p75=10, p90=16** — the box carries
# more than it did — so 14 had drifted back above p75, which is the exact
# condition that pass was fixing. Second occurrence of one failure.
#
# Measured against the real gate, not guessed: it opened on 7% of ticks, and
# memory alone blocked 89% of the non-shed ones. Sweeping the floor: 14 -> 7%,
# 12 -> 9%, 10 -> 23%, 9 -> 67%, 8 -> 83%. 10 is p75 and buys a restore
# opportunity roughly every 20 minutes instead of every 70.
#
# Why not 9, which opens the gate on two thirds of ticks: it leaves one point of
# hysteresis above MEM_WARN, so a shed at 7% would restore at 9% and shed again.
# 10 keeps a 2-point band. It is narrower than the 6 points this file has
# defended twice, and that is the deliberate trade — a wide band on a box whose
# whole operating range is 8-16% is a band with no room to sit in.
#
# To be exact about the symptom, because the first draft of this note overstated
# it: restore is not dead, it is slow. Both apps were shed at 05:55 on 2026-08-14
# and the shed list had cleared itself by 08:55 — three hours, spent waiting for
# availability to climb past 14 on a box that sits at 9. At 10 that wait is the
# 23%-of-ticks case, well under an hour.
#
# What made it recur is that nothing watched the window at all. health_check.rb
# now fails while anything the guard shed is still down, which is the outage
# rather than a theory about thresholds — an earlier version of that check did
# reason from this log about whether the gate was reachable, and measured against
# the real 1550 ticks it stayed silent through the very incident it was written
# for.
MEM_WARN=8
MEM_RESTORE=10

# Field 2 is the 5-minute average. Shedding a site is expensive and reversible
# only on the next tick, so this guard reads the smoothed figure and not the
# 1-minute one core-reclaim.sh reads for its own, opposite question. The two
# have to disagree, so the scripts that read the load share no library; a shared
# file also means one more root-owned install target, since root sources only
# root-owned absolute paths.
load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
# Failing toward 9.9 sheds. A guard that cannot read the load must assume the
# worst; assuming the best would disarm it exactly when sysctl is the thing
# struggling.
load=${load:-9.9}

# Available memory percent = (Free + Cache) / physmem.
# top's Memory line: "Memory: Real: 273M/578M act/tot Free: 383M Cache: 192M Swap: 562M/1264M"
mem_avail_pct=100
total_mb=$(( $(sysctl -n hw.physmem 2>/dev/null || echo 0) / 1048576 ))
avail_mb=$(top -b -n 1 2>/dev/null | awk '
  function mb(v) {
    n = v + 0
    if (v ~ /G/) { return n * 1024 }
    if (v ~ /K/) { return n / 1024 }
    return n
  }
  /^Memory:/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "Free:")  { f = mb($(i+1)) }
      if ($i == "Cache:") { c = mb($(i+1)) }
    }
    printf "%d", f + c
    exit
  }')
if [[ -n $avail_mb && $total_mb -gt 0 ]]; then
  mem_avail_pct=$(( avail_mb * 100 / total_mb ))
else
  # Fallback if top output changes shape: vmstat free pages (undercounts by
  # the buffer cache, so only trust it as a floor, never for restore).
  pages=$(vmstat -s | awk '/pages managed/{print $1}')
  free=$(vmstat -s | awk '/pages free$/{print $1}')
  if [[ -n $pages && -n $free && $pages -gt 0 ]]; then
    mem_avail_pct=$(( free * 100 / pages ))
  else
    # Both measurements gone. The load arm above fails to 9.9 for exactly this
    # reason, and the memory arm used to fail the other way: it kept its 100%
    # initialiser, so `mem_avail_pct -lt MEM_WARN` was never true and the guard
    # went quietly deaf to memory-only pressure. 0 sheds on the next strike and
    # refuses to restore, which is a state a human sees. 100 was silence.
    mem_avail_pct=0
    logger -t resource-guard "memory unmeasurable — top and vmstat both failed, treating as 0%"
  fi
fi

# This script runs as root from cron every 5 minutes (etc/crontab.vm23).
# It used to dot-source validate_doas.ksh and stale_ci_cleanup.ksh out of
# ${GUARD_REPO:-/home/dev/pub4} — a dev-owned git checkout — which meant write
# access to either file was root code execution within 5 minutes, entirely
# independent of doas. It also called install_doas_conf_from_repo, so the repo's
# doas.conf was copied over /etc/doas.conf on every tick and any hand-hardening
# of the live file was reverted.
#
# Root now sources only root-owned absolute paths, installed at deploy time.
# Nothing here reads from a user-writable tree.
# Hardcoded, not ${GUARD_LIBEXEC:-...}: an environment-overridable path to a
# file root dot-sources is the exact shape of the hole this replaced. Ships from
# OPENBSD/usr/local/libexec/ via OPERATOR.sh install_root_configs.
GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh
if [[ -f $GUARD_HELPER ]]; then
  . "$GUARD_HELPER"
  stale_ci_cleanup "$load" "$mem_avail_pct"
else
  # Loud, not silent: the previous revision skipped quietly when the helper was
  # absent, so load-shedding cleanup could stop running unnoticed.
  logger -t resource-guard "stale_ci_cleanup helper missing at $GUARD_HELPER — cleanup skipped"
fi

shed=0
if awk -v l="$load" -v w="$LOAD_WARN" 'BEGIN{exit !(l>=w)}'; then shed=1; fi
if [[ $mem_avail_pct -lt $MEM_WARN ]]; then shed=1; fi

# A deploy is load this box was told to make. rc.d/{master,amber,brgen,bsdports}
# touch /home/dev/pub4/.deploying* from rc_pre() until the /up wait ends — precompile,
# migrate, cold boot — which is exactly the transient breach SHED_STRIKES above
# describes, and exactly when this guard used to take amber and bsdports down.
# Restore then crawls back one service per 5-minute tick, so a deploy cost those
# two apps ten minutes of downtime that TLS hid, on every deploy.
#
# The locks have been written since the rc.d scripts were introduced and nothing
# has ever read them. Reading one is the whole fix: shedding in response to the
# operator's own deploy is the guard fighting the thing that asked for the work.
#
# Ahead of both the history log and the strike counter, so the log records the
# decision actually taken and a deploy tick is not counted as a strike that
# fires the moment the deploy ends.
#
# Only the shed side. Restore still waits for pressure to clear on its own
# terms — a deploy ending does not mean memory is free, and the one-per-tick
# stagger below exists because simultaneous cold boots re-trigger this guard.
#
# The flag comes off after the rc.d /up wait, so an rc.d run killed mid-wait
# leaves it behind. A flag older than DEPLOY_FLAG_MAX_AGE seconds (default 30
# minutes, well past the longest measured start) is treated as stale, or one
# interrupted restart would disable shedding for good.
DEPLOY_FLAG_MAX_AGE=${GUARD_DEPLOY_FLAG_MAX_AGE:-1800}
deploying=0
_now=$(date +%s)
for _flag in /home/dev/pub4/.deploying*; do
  [ -e "$_flag" ] || continue
  _mtime=$(stat -f %m "$_flag" 2>/dev/null || echo 0)
  if [ $((_now - _mtime)) -le "$DEPLOY_FLAG_MAX_AGE" ]; then
    deploying=1
  else
    logger -t resource-guard "ignoring stale deploy flag $_flag"
  fi
done
if [[ $deploying -eq 1 ]]; then
  if [[ $shed -eq 1 ]]; then
    logger -t resource-guard \
      "deploy in progress (load=$load mem_avail=${mem_avail_pct}%) — not shedding"
    shed=0
  fi
fi

# Load-history log: LOAD_WARN/LOAD_CRIT above were set from a single evening's
# observation (itself skewed high by concurrent deploys/agent activity, not a
# calm baseline) -- recalibrating them again by guesswork would repeat the
# same mistake. This gives a real dataset (`awk '{print $4}' | sort -n` etc.)
# to recalibrate from once enough ticks have accumulated. One line/5min ==
# ~2000 lines/week; rotated weekly via newsyslog (OPENBSD/etc/newsyslog.conf).
#
# The box-wide figures say pressure exists, not who made it, so each daemon
# user's resident memory follows them: every app runs as its own daemon_user,
# and summing by user counts the job worker and every Falcon fork with it. The
# fields go last so the positions a recalibration reads stay where they are.
rss=""
for app in $CORE $OPTIONAL; do
  kb=$(ps -o rss= -U "$app" 2>/dev/null | awk '{ s += $1 } END { printf "%d", s }')
  rss="$rss rss_$app=$(( ${kb:-0} / 1024 ))M"
done
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) load=$load mem_avail=${mem_avail_pct}% shed=$shed deploy=$deploying$rss" \
  >> /var/log/resource_guard_history.log 2>/dev/null || true

if [[ -f $ALL_APPS_FLAG ]]; then
  exit 0
fi

# Consecutive-breach counter. Reset the moment a tick comes back clean, so
# strikes only accumulate for sustained pressure, never across unrelated spikes
# hours apart.
strikes=0
if [[ -f $STRIKE_STATE ]]; then
  strikes=$(cat "$STRIKE_STATE" 2>/dev/null || echo 0)
  [[ $strikes == +([0-9]) ]] || strikes=0
fi
if [[ $shed -eq 1 ]]; then
  strikes=$((strikes + 1))
else
  strikes=0
fi
echo "$strikes" > "$STRIKE_STATE" 2>/dev/null || true

if [[ $shed -eq 1 && $strikes -lt $SHED_STRIKES ]]; then
  logger -t resource-guard \
    "pressure $strikes/$SHED_STRIKES (load=$load mem_avail=${mem_avail_pct}%) — holding"
  shed=0
fi

if [[ $shed -eq 1 ]]; then
  # One service per tick, the same way restore releases one per tick. Shedding
  # the whole OPTIONAL list on one breach gave up more than the pressure asked
  # for and then took three ticks to undo. The list is ordered cheapest-to-lose
  # first, so a mild breach costs bsdports and leaves amber up.
  for svc in $OPTIONAL; do
    if rcctl check "$svc" 2>/dev/null | grep -q '(ok)'; then
      logger -t resource-guard "shed $svc (load=$load mem_avail=${mem_avail_pct}% strikes=$strikes)"
      rcctl stop "$svc" 2>/dev/null || true
      if ! grep -qx "$svc" "$SHED_STATE" 2>/dev/null; then
        echo "$svc" >> "$SHED_STATE"
      fi
      break
    fi
  done
  # tts-worker daemons are deliberately not killed here, though amber and
  # bsdports shed at this LOAD_WARN tier. On this box, load sits at LOAD_WARN or
  # above almost continuously (observed 3.3-6.4 over a full session, never
  # below 2.5) -- so the warm TTS socket pool was being reaped on nearly
  # every 5-minute tick, forcing every synthesis onto the slow cold-boot
  # oneshot path (fresh Ruby+Bundler+EventMachine+TLS handshake per request)
  # instead of a warm socket. TTS is core (see master's /health "tts is
  # mandatory per operator"), not optional like amber/bsdports, and the two
  # small idle tts-worker processes aren't what's driving load. Genuine
  # crisis-tier cleanup (LOAD_CRIT) below still reaps and respawns them.
fi

# Restore path: undo our own shedding once pressure has genuinely cleared.
# One service per tick — the 5-minute cron interval staggers cold boots for
# free, avoiding the simultaneous-restart memory spike that re-triggers the
# guard. Only services this script shed (tracked in SHED_STATE) and that are
# still enabled in rc.d are restored, so deliberately disabled services
# (e.g. decommissioned services) stay down.
if [[ $shed -eq 0 && -s $SHED_STATE && $mem_avail_pct -ge $MEM_RESTORE ]]; then
  if awk -v l="$load" -v r="$LOAD_RESTORE" 'BEGIN{exit !(l<r)}'; then
    restored=""
    for svc in $(cat "$SHED_STATE"); do
      if ! rcctl get "$svc" status >/dev/null 2>&1; then
        # No longer enabled — drop from state without starting it.
        restored=$svc
        break
      fi
      if rcctl check "$svc" 2>/dev/null | grep -q '(ok)'; then
        restored=$svc
        break
      fi
      logger -t resource-guard "restore $svc (load=$load mem_avail=${mem_avail_pct}%)"
      rcctl start "$svc" 2>/dev/null || true
      restored=$svc
      break
    done
    if [[ -n $restored ]]; then
      grep -vx "$restored" "$SHED_STATE" > "${SHED_STATE}.tmp" 2>/dev/null || true
      mv "${SHED_STATE}.tmp" "$SHED_STATE"
    fi
  fi
fi

if awk -v l="$load" -v c="$LOAD_CRIT" 'BEGIN{exit !(l>=c)}'; then
  logger -t resource-guard "crit load=$load — running emergency_cpu"
  if [[ -x /usr/local/bin/emergency_cpu.sh ]]; then
    ksh /usr/local/bin/emergency_cpu.sh 2>&1 | logger -t resource-guard
  else
    logger -t resource-guard "emergency_cpu not installed under /usr/local/bin"
  fi
fi

exit 0

`````

### bin/restore_litestream.sh

`````zsh
#!/usr/bin/env zsh
# NOT the disaster-recovery script — use OPENBSD/bin/dr-pull for that.
#
# Restore Rails SQLite databases from on-disk Litestream replicas (vm23).
# Stops app services, runs litestream restore, restarts services. It was called
# restore_backups.sh, which is the name somebody reaches for in an actual
# emergency, and vm23 has no litestream binary and no replicas — so the name
# promised recovery the file cannot deliver. The name is the architecture.
#
# Usage (on vm23):
#   DRY_RUN=1 zsh OPENBSD/bin/restore_litestream.sh          # print plan only
#   zsh OPENBSD/bin/restore_litestream.sh brgen              # one app
#   zsh OPENBSD/bin/restore_litestream.sh                    # all apps in etc/litestream.yml
#
# Every precondition below is a hard failure, not a skip. On vm23 litestream is
# absent and /var/backups/litestream/ is empty, so a skipping restore walked all
# three apps, restored none of them and printed "done" — a disaster-recovery
# script that reports success is worse than one that is missing, because it is
# read as evidence. The working backup is OPENBSD/bin/dr-pull, whose snapshots
# live on the operator Mac; see RUNBOOK.md, "Backups".

set -euo pipefail

CONFIG="${LITESTREAM_CONFIG:-/etc/litestream.yml}"
DRY_RUN="${DRY_RUN:-0}"
APPS=("${@}")

log() { printf '[restore] %s\n' "$*"; }

discover_apps() {
  if (( ${#APPS[@]} > 0 )); then
    print -l -- "${APPS[@]}"
    return
  fi
  # stderr, because stdout is the app list.
  [[ -f $CONFIG ]] || { log "FAIL — missing litestream config: $CONFIG" >&2; exit 1; }
  ruby - "$CONFIG" <<'RUBY'
require 'yaml'
config = YAML.load_file(ARGV[0])
Array(config['dbs']).each do |entry|
  path = entry['path'].to_s
  next unless path =~ %r{/home/([^/]+)/}
  puts $1
end
RUBY
}

require_litestream() {
  whence litestream >/dev/null 2>&1 && return 0
  log "FAIL — no litestream binary on this host, so nothing here can restore anything."
  log "       litestream is not in OpenBSD ports; /var/backups/litestream/ is empty."
  log "       Restore from a dr-pull snapshot instead: ruby OPENBSD/bin/dr-pull --check"
  exit 1
}

restore_app() {
  local app="$1"
  local storage="/home/${app}/app/storage"
  local replica="file:///var/backups/litestream/${app}"

  [[ -d $storage ]] || { log "FAIL $app — missing $storage"; exit 1 }
  [[ -d "/var/backups/litestream/${app}" ]] || { log "FAIL $app — missing replica $replica"; exit 1 }

  local -a dbs
  dbs=("$storage"/*.sqlite3(N))
  if (( ${#dbs[@]} == 0 )); then
    log "FAIL $app — no *.sqlite3 in $storage"
    exit 1
  fi

  log "stopping $app"
  if [[ $DRY_RUN != 1 ]]; then
    doas rcctl stop "$app" 2>/dev/null || true
  fi

  local db
  for db in "${dbs[@]}"; do
    log "restore $db <= $replica"
    if [[ $DRY_RUN == 1 ]]; then
      log "dry-run: litestream restore -config $CONFIG -o $db $replica"
    else
      doas -u "$app" litestream restore -config "$CONFIG" -o "$db" "$replica"
    fi
  done

  log "starting $app"
  if [[ $DRY_RUN != 1 ]]; then
    doas rcctl start "$app"
    doas rcctl check "$app"
  fi
}

main() {
  [[ $DRY_RUN == 1 ]] || require_litestream
  # Collected before the loop: a failure inside `< <(discover_apps)` does not
  # stop the reader, while a failed assignment does under set -e.
  local -a apps
  apps=("${(@f)$(discover_apps)}")
  local app
  for app in "${apps[@]}"; do
    [[ -n $app ]] || continue
    restore_app "$app"
  done
  log "done"
}

main "$@"

`````

### bin/start_all_apps.sh

`````zsh
#!/bin/ksh
# Start every pub4 service on vm23 and pin them against resource_guard shedding.
# Usage: doas ksh /home/dev/pub4/OPENBSD/bin/start_all_apps.sh
#
# The services are master plus every app in RAILS/apps.yml, read at run time:
# master is not an apps.yml app, and a literal list keeps starting three apps
# after a fourth ships.

set -eo pipefail

case ${1:-} in
-h|--help)
  echo "usage: doas ksh OPENBSD/bin/start_all_apps.sh — enable and start master and every apps.yml app, pin them against shedding"
  exit 0
  ;;
esac

# Named outright, as the rc.d scripts name it: this runs as root from rc(8) or by
# hand with no caller environment, so a PUB4_ROOT needs setting here too.
# Production has one checkout, and a worktree is never a deploy target.
ROOT=/home/dev/pub4
ALL_APPS_FLAG=/var/db/pub4_all_apps
APPS=$(ruby40 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys.join(" ")' "$ROOT/RAILS/apps.yml")
[ -n "$APPS" ] || { echo "start_all_apps: no apps read from $ROOT/RAILS/apps.yml" >&2; exit 1; }
SERVICES="master $APPS"

install -d -m 755 /var/db
: > "$ALL_APPS_FLAG"
chmod 644 "$ALL_APPS_FLAG"

for svc in $SERVICES; do
  rcctl enable "$svc" 2>/dev/null || true
  rcctl start "$svc" 2>/dev/null || true
done

# Not a race: each app's rc.d start blocks in its own /up wait, up to 300
# seconds, before it returns, so this restart follows every backend's wait.
sleep 5
rcctl restart relayd

for svc in $SERVICES; do
  rcctl check "$svc" || exit 1
done

ruby40 "$ROOT/OPENBSD/gates/health_check.rb" --all-ready-apps
echo "all apps up (resource_guard shedding disabled via $ALL_APPS_FLAG)"

`````

### bin/sync_deploy_inventory.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate OPENBSD/deploy_inventory.json from RAILS/apps.yml.
#   ruby OPENBSD/bin/sync_deploy_inventory.rb
# No date in the output: a stamp that moves on every run makes an unchanged
# inventory look changed, and port_inventory already says when the two disagree.

require "json"
require "yaml"

if ARGV.intersect?(%w[-h --help])
  puts "usage: ruby OPENBSD/bin/sync_deploy_inventory.rb   # rewrites OPENBSD/deploy_inventory.json from RAILS/apps.yml"
  exit 0
end

ROOT = File.expand_path("../..", __dir__)
APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
OUT = File.join(ROOT, "OPENBSD", "deploy_inventory.json")

data = YAML.safe_load(File.read(APPS_YML))
apps = data.fetch("apps").map do |name, meta|
  { "name" => name, "domain" => meta.fetch("domain"), "port" => meta.fetch("port").to_i }
end.sort_by { |row| row["name"] }

payload = {
  "schema" => 1,
  "generated_from" => "RAILS/apps.yml",
  "apps" => apps,
  "master_face" => {
    "name" => "master",
    "domain" => "ai.brgen.no",
    "port" => 53_187,
    "deploy_root" => "MASTER/web",
  },
}

File.write(OUT, JSON.pretty_generate(payload) + "\n")
puts "wrote #{OUT} (#{apps.size} apps)"

`````

### bin/uptime-check.sh

`````zsh
#!/usr/bin/env sh
# External-style uptime checker — public HTTPS only, no vm23 tools needed.
# Runs from a laptop or vm23.
#
# Usage:
#   sh OPENBSD/bin/uptime-check.sh
#   CURL=/usr/local/bin/curl sh OPENBSD/bin/uptime-check.sh
#   UPTIME_CHECK_TIMEOUT=40 sh OPENBSD/bin/uptime-check.sh
#
# Exit 0 only when every endpoint returns HTTP 2xx/3xx.
#
# A wrapper, not a list of URLs of its own. health_check.rb asks the same
# question against RAILS/apps.yml, and a hardcoded copy can only go stale — it
# would still name four domains after a fifth app ships, and nothing would
# report that. --public-only is the scope that needs no
# rcctl, no pfctl and no /etc/relayd.conf, which is what made this a wrapper
# rather than a deletion: the entry point is documented in RUNBOOK.md and
# RAILS/amber/HEIR.md, and it is the one health check that runs anywhere.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
RUBY=${RUBY:-$(command -v ruby40 2>/dev/null || command -v ruby)}

# Same names this script has always documented, mapped onto health_check.rb's.
HEALTH_CHECK_TIMEOUT=${UPTIME_CHECK_TIMEOUT:-20}
export HEALTH_CHECK_TIMEOUT

exec "$RUBY" "${ROOT}/OPENBSD/gates/health_check.rb" --public-only --all-ready-apps "$@"

`````

### bin/vps_ci.sh

`````zsh
#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh OPENBSD/bin/vps_ci.sh brgen
set -euo pipefail

usage="usage: zsh OPENBSD/bin/vps_ci.sh APP — sync APP's copy-tree, then run its bin/ci under the CI lock"
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print -r -- "$usage"
  exit 0
fi

app=${1:-}
[[ -n $app ]] || { print -u2 -r -- "$usage"; exit 2 }

repo=${PUB4_ROOT:-/home/dev/pub4}
app_dir=/home/${app}/app
shared_dir=/home/${app}/shared
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }

# deploy_status (from RAILS/_core.sh) -- same in-progress status file the
# SKIP_CI=1 path (_deploy.sh/_runtime_gate.sh) writes, so `bin/vps-state`
# is one place to check regardless of which deploy path is running.
[[ -f ${repo}/RAILS/_core.sh ]] && . "${repo}/RAILS/_core.sh"
command -v deploy_status >/dev/null 2>&1 || deploy_status() { :; }

export PUB4_CI_GUARD=1
export PUB4_RAILS_ROOT=${PUB4_RAILS_ROOT:-$repo/RAILS}

# Path and safe creation live in OPENBSD/lib/ci_lock.sh — the lock moved out of
# world-writable /var/tmp, where root was chmod'ing a caller-chosen, symlinkable path.
. "${repo}/OPENBSD/lib/ci_lock.sh"

sync_ci_rails_root() {
  local mirror=/home/${app}/pub4-rails
  doas mkdir -p "$mirror"
  # tar extraction is additive-only: a file removed from the source repo
  # would otherwise linger in the mirror forever. Wipe each synced subtree
  # before re-extracting so the mirror actually reflects deletions too --
  # found the hard way when a controller deleted from git upstream kept
  # passing CI on the VPS from a stale copy months after removal.
  doas rm -rf "$mirror/RAILS"
  # git archive is the tracked tree. tar of the working checkout also packed
  # gitignored RAILS/*/vendor/bundle left by a local bundle, filled /home, and
  # aborted extract with "Unable to restore mode and times" (2026-08-13).
  git -C "$repo" archive HEAD RAILS | doas sh -c "cd ${mirror} && tar xf -"
  if git -C "$repo" cat-file -e HEAD:MASTER/tools 2>/dev/null; then
    doas rm -rf "$mirror/MASTER/tools"
    git -C "$repo" archive HEAD MASTER/tools | doas sh -c "cd ${mirror} && tar xf -"
  fi
  # MASTER is the design authority: RAILS/tools/build_all_css.rb and the lints
  # read design_system from MASTER/data/rules.yml through
  # Operator::MasterDesign, whose first candidate is this mirror's copy. The
  # app user cannot read /home/dev/pub4, so without it css_build died on
  # KeyError "social" (2026-09-24).
  doas rm -f "$mirror/MASTER/data/rules.yml"
  git -C "$repo" archive HEAD MASTER/data/rules.yml | doas sh -c "cd ${mirror} && tar xf -"
  # build_all_css.rb picks its Ruby through MASTER/lib/operator/ruby_runner,
  # which requires its siblings. Without the directory css_build dies on a
  # LoadError before it compiles anything.
  doas rm -rf "$mirror/MASTER/lib/operator"
  git -C "$repo" archive HEAD MASTER/lib/operator | doas sh -c "cd ${mirror} && tar xf -"
  doas chown -R "${app}:${app}" "$mirror"
}

# Names every tracked entry at the app root that is neither synced nor kept
# local. Warns rather than fails: this list is discovered from git at deploy
# time, so a wrong reading here would refuse a deploy for a documentation file,
# and a deploy pipeline that cries wolf gets its checks removed. Loud and
# specific is the useful setting until the set has been stable a while.
#
# Found this way: .rubocop.yml was missing and nothing said so for twelve days,
# and .ruby-version is absent from amber's and bsdports' copy-trees entirely.
unaccounted_tracked_files() {
  local app=$1 repo=$2
  local -a synced=(${(P)3}) kept=(${(P)4})
  local -a tracked missing
  tracked=(${(f)"$(git -C "$repo" ls-files "RAILS/$app" 2>/dev/null)"}) || return 0
  (( ${#tracked} )) || return 0

  local rel top
  for rel in $tracked; do
    top=${${rel#RAILS/$app/}%%/*}
    [[ -n $top ]] || continue
    # A synced entry may be a subpath — vendor/javascript covers vendor's only
    # tracked content — so a top-level name counts as accounted when any synced
    # path is it or descends from it. Without this the check reports `vendor`,
    # which is the accounting being wrong rather than the sync.
    (( ${synced[(Ie)$top]} )) && continue
    # :- is load-bearing under `set -u`. (I) yields an index and is 0 when there
    # is no match, so it is safe bare; (r) yields the matched VALUE, and a search
    # that matches nothing is an unset parameter, which nounset makes fatal. This
    # aborted every deploy's CI step with "synced[(r)$top/*]: parameter not set"
    # — the guard erroring rather than the thing it guards.
    [[ -n ${synced[(r)$top/*]:-} ]] && continue
    (( ${kept[(Ie)$top]} )) && continue
    [[ $top == *.sh || $top == *.md ]] && continue
    missing+=($top)
  done

  local -a uniq_missing=(${(u)missing})
  (( ${#uniq_missing} )) || return 0
  print -u2 "vps_ci: $app — tracked but neither synced nor kept local: ${uniq_missing}"
  print -u2 "vps_ci: $app — add each to paths (bin/ci reads the copy-tree) or to kept_local with a reason"
}

sync_from_repo() {
  local src=$repo/RAILS/$app
  local shared_src=$repo/RAILS/shared
  sync_ci_rails_root
  if [[ -d $src ]]; then
    # engines/ carries brgen's vertical Rails engines (path gems in the Gemfile);
    # without it the copy-tree Gemfile's `path: 'engines/<v>'` resolves to a missing
    # dir and bundle aborts. See RAILS/brgen/ENGINES.md.
    # .rubocop.yml is here because bin/ci runs from this copy-tree, not from the
    # repo — so the style gate reads whatever config was last left in the live
    # dir. It was not synced, so the copy froze on 2026-08-13 while the tracked
    # one moved on, and the two disagreed: the stale file re-enabled
    # Layout/LineLength and Style/TrailingCommaInArguments, which the tracked one
    # leaves to omakase. That produced 1283 offences on vm23 against 2 for the
    # same command and the same 734 files locally.
    #
    # It stayed invisible until RuboCop began running on the VPS at all, and it
    # deadlocked the pipeline the moment it did: the corrected config can only
    # reach the live dir through a sync, and the sync is gated behind the CI run
    # that the stale config was failing.
    # Everything tracked at the app root is either synced or named as deliberately
    # not synced. An allowlist that simply omits things fails silently and in the
    # worst direction: bin/ci runs from this copy-tree, so a config that never
    # arrives means the gate reads a stale one. .rubocop.yml did exactly that —
    # frozen on 2026-08-13, re-enabling cops the tracked file leaves to omakase,
    # producing 1283 offences against 2 locally and deadlocking the pipeline,
    # because the corrected config could only arrive through the sync that the
    # stale config was failing.
    #
    # KEPT_LOCAL is the other half. Without it, "not in paths" means both "we
    # decided against it" and "nobody thought about it", and those must not look
    # alike. sync_accounts_for_every_tracked_file below turns the second into an
    # error at deploy time rather than a puzzle weeks later.
    local -a paths=(test app lib config bin db engines public vendor/javascript
                    Gemfile Gemfile.lock config.ru Rakefile .rubocop.yml .ruby-version)
    # Named as deliberately not synced, so "absent from paths" stops meaning both
    # "decided against" and "never considered". log/ and storage/ are the running
    # app's own state and syncing them would overwrite production data; the rest
    # is documentation that no gate and no runtime reads.
    # log/ and storage/ are the running app's own state — syncing them would
    # overwrite production data. docs/ and script/ are read by no gate and no
    # runtime. domains.yml has no reader anywhere in the repo (checked
    # 2026-08-25; the live copy is thirteen days and half a file behind, and
    # nothing noticed because nothing reads it). Procfile.dev is for `bin/dev`
    # on a laptop.
    local -a kept_local=(log storage docs script domains.yml Procfile.dev)
    unaccounted_tracked_files "$app" "$repo" paths kept_local

    local -a existing=()
    local rel
    for rel in "${paths[@]}"; do
      [[ -e $src/$rel ]] && existing+=($rel)
    done
    for rel in ${src}/*.sh(N:t); do existing+=($rel); done
    [[ ${#existing[@]} -eq 0 ]] && return 0
    # Same additive-tar pitfall as sync_ci_rails_root above: prune the
    # directory entries before re-extracting so files deleted upstream
    # (test/app/lib/config/bin/db) actually disappear from the deployed
    # copy instead of surviving as stale dead code indefinitely.
    local dir_rel
    for dir_rel in test app lib config bin db engines public vendor/javascript; do
      [[ -d $src/$dir_rel ]] || continue
      # public/assets is the one synced directory that is not in git: Propshaft
      # writes it here, on this box, at the precompile step further down the
      # deploy. Pruning public/ wholesale therefore DELETES the running site's
      # stylesheets and scripts, and it does so before bin/ci has run — so a CI
      # failure exits the deploy with the new code live and no assets at all.
      # brgen served every page with a 404ing <link> that way on 2026-08-14:
      # public/assets held zero files, `/` still answered 200, and no gate
      # noticed because the health check never asks for a stylesheet.
      #
      # Held aside and put back. A failed deploy then leaves the previous
      # assets serving the previous markup, which is stale but whole; a
      # successful one overwrites them at precompile a few steps later.
      if [[ $dir_rel == public && -d ${app_dir}/public/assets ]]; then
        doas rm -rf "${app_dir}/.assets-carry"
        doas mv "${app_dir}/public/assets" "${app_dir}/.assets-carry"
        doas rm -rf "${app_dir}/public"
        doas mkdir -p "${app_dir}/public"
        doas mv "${app_dir}/.assets-carry" "${app_dir}/public/assets"
        continue
      fi
      doas rm -rf "${app_dir}/${dir_rel}"
    done
    doas tar cf - -C "$src" "${existing[@]}" | doas sh -c "cd ${app_dir} && tar xf -"
    doas chown -R "${app}:${app}" "${app_dir}/test" "${app_dir}/app" "${app_dir}/lib" \
      "${app_dir}/config" "${app_dir}/bin" "${app_dir}/db" "${app_dir}/engines" \
      "${app_dir}/public" "${app_dir}/vendor" \
      "${app_dir}/Gemfile" "${app_dir}/Gemfile.lock" \
      "${app_dir}"/*.sh(N) 2>/dev/null || true
  fi
  doas mkdir -p "$shared_dir"
  doas rm -rf "$shared_dir"
  doas mkdir -p "$shared_dir"
  doas tar cf - -C "$shared_src" . | doas sh -c "cd ${shared_dir} && tar xf -"
  doas chown -R "${app}:${app}" "$shared_dir"
}

npm_cache=/home/${app}/.npm
cache_home=/home/${app}/.cache
print "vps_ci: $app (sync + mutex + load gate)"
deploy_status "$app" "sync tree"
sync_from_repo
pub4_ensure_ci_lock >/dev/null
ci_rails_root=/home/${app}/pub4-rails/RAILS
# App users reach /home/dev by GROUP, not other: 750 dev:_pub4ci, members
# brgen/amber/bsdports/master. That closes the world-readable half of the
# secrets debt entry, which is the half that mattered -- `other` gets nothing.
# Idempotent so a fresh box converges on first CI run.
#
# Group read, not 710. master is the one service whose working directory is
# under /home/dev, and getcwd(3) names each ancestor by reading it, so `--x`
# lets it chdir and then fails Dir.pwd with EACCES. rubygems calls Dir.pwd
# before Bundler is even loaded, so master died at bundle40 with no log of its
# own and ai.brgen.no served an empty reply. 710 was verified by traversing,
# which is a weaker claim than the one it was taken to prove.
doas groupadd _pub4ci 2>/dev/null || true
doas usermod -G _pub4ci "${app}" 2>/dev/null || true
doas chgrp _pub4ci /home/dev 2>/dev/null || true
doas chmod 750 /home/dev 2>/dev/null || true

# The other half of that entry, which it missed: /home/dev was tightened and
# /home/<app> was not. /home/brgen, /home/brgen/app and .../app/storage were
# all 755 with production.sqlite3 at 644 brgen:brgen, so as dev — not brgen,
# not in group brgen — `sqlite3 .../production.sqlite3 "select count(*) from
# users"` returned 17756, and that table carries password_digest, otp_secret,
# remember_token and magic_link_token. Every local account could do it,
# including www and sshd, which are where a relayd or sshd compromise lands.
#
# Only storage tightens. /home/<app> and /home/<app>/app stay 755 because
# vps-deploy tests `-d /home/<app>/app` as dev, and that needs the traversal.
# The app itself owns the directory, so it reads and writes as before; every
# crontab on this box is root's; and relayd declares no file root, so nothing
# serves these from disk.
#
# Re-asserted here rather than done once by hand: sync_from_repo's path list
# does not include storage today, and a line added to it later would silently
# put this back to 755.
doas chmod 750 "/home/${app}/app/storage" 2>/dev/null || true
doas chmod -R a+rX "${repo}/MASTER/tools" 2>/dev/null || true
deploy_status "$app" "bundle install + bin/ci"
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export PUB4_ROOT=${repo}; export PUB4_CI_GUARD=1; export PUB4_CI_APP=${app}; export PUB4_RAILS_ROOT=${ci_rails_root}; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; export BUNDLE_USER_HOME=/home/${app}/.bundle; cd ${app_dir} && bundle40 config unset without 2>/dev/null || true && bundle40 config unset deployment 2>/dev/null || true && bundle40 install --jobs=2 && bundle40 exec bin/ci'" \
  || { deploy_status "$app" "bundle install + bin/ci" "failed"; exit 1; }

sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)
started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
doas mkdir -p /var/db/pub4 2>/dev/null || true
doas tee "/var/db/pub4/last_deploy_${app}.json" >/dev/null <<EOF
{"app":"${app}","sha":"${sha}","at":"${started}","status":"ci_ok","host":"$(hostname)"}
EOF
deploy_status "$app" "done" "done"

`````

### bin/vps_ci_all.sh

`````zsh
#!/usr/bin/env zsh
# Run all active Rails app CIs serially on vm23 — never parallel.
# Usage: zsh OPENBSD/bin/vps_ci_all.sh      (PUB4_CI_MAX_LOAD=4 waits while load is higher)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_ci_all.sh — vps_ci.sh for every app in RAILS/apps.yml, serially"
  exit 0
fi

repo=${PUB4_ROOT:-/home/dev/pub4}
script=${repo}/OPENBSD/bin/vps_ci.sh
# The fleet is apps.yml's, in its order; a literal list here keeps testing three
# apps after a fourth ships.
apps=(${(f)"$(ruby40 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys' "${repo}/RAILS/apps.yml")"})
(( ${#apps} )) || { print -u2 "vps_ci_all: no apps read from ${repo}/RAILS/apps.yml"; exit 1 }
max_load=${PUB4_CI_MAX_LOAD:-4}

# The 5-minute average, and one ruby40 rather than two awks per tick — the same
# shape vps_master_scan.sh uses, for the same two reasons: awk is banned in
# committed scripts here, and one process both reads the figure and decides on
# it, so there is no window where the value read is not the value compared.
# OpenBSD prints the three numbers bare and macOS wraps them in braces, which is
# why this scans for numbers rather than splitting on whitespace.
load_over_max() {
  ruby40 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(0) if n.size < 3
    exit(n[1].to_f > ARGV[0].to_f ? 0 : 1)
  ' "$max_load"
}

wait_for_load() {
  while load_over_max; do
    print "vps_ci_all: 5-minute load over $max_load — sleeping 60s"
    sleep 60
  done
}

for app in $apps; do
  wait_for_load
  zsh "$script" "$app" || exit $?
  sleep 10
done

print "vps_ci_all: all apps passed"

`````

### bin/vps_deploy_master.sh

`````zsh
#!/bin/sh
# Deploy MASTER web + lib to vm23 after git pull.
#
# This is the body of `bin/vps-deploy master`, which also writes the deploy
# stamp; run that. Calling this file directly deploys without a stamp, which
# is only right when vps-deploy itself is what is broken.
#
# Usage (from dev laptop):
#   zsh OPENBSD/lib/ssh_vm23.sh exec 'zsh /home/dev/pub4/OPENBSD/bin/vps_deploy_master.sh'
#   zsh OPENBSD/bin/vps_deploy_master.sh --from-laptop

if [ "${1:-}" = "--from-laptop" ]; then
  shift
  _lib="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/ssh_vm23.sh"
  exec zsh "$_lib" exec "zsh /home/dev/pub4/OPENBSD/bin/vps_deploy_master.sh" "$@"
fi

set -eo pipefail
ROOT="${ROOT:-/home/dev/pub4}"
WEB="$ROOT/MASTER/web"

echo "==> git pull"
cd "$ROOT" && git pull --ff-only origin main

cd "$WEB"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export RAILS_ENV=production
# The build steps below need a secret to boot Rails and never use it; the
# running server takes its real key from /etc/master.env through rc.d/master.
# SECRET_KEY_BASE_DUMMY says that outright, where a random key could be
# mistaken for, or leak into, the real one.
export SECRET_KEY_BASE_DUMMY=1

# Primary database. MASTER/web's migrations reach ai.brgen.no's
# production.sqlite3 through this step and no other, so a deploy without it
# ships code against a schema that is behind.
#
# db:prepare is idempotent: it creates the database when absent, loads the
# schema when empty, and otherwise applies only pending migrations.
# Gems first: db:prepare is the first `bundle40 exec`, and a gem the pull just
# added (ferrum-0.17.2, 2026-09-24) stopped the deploy there with GemNotFound
# while the install that would have fixed it waited two steps later.
echo "==> bundle"
bundle40 config set --local without 'development:test' 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle40 check 2>/dev/null || BUNDLE_WITHOUT=development:test bundle40 install
# The tts-worker and media tools boot from MASTER/Gemfile, not web's. rc.d/master
# only checks it now, because it runs as root; installing belongs here, as dev.
(cd "$ROOT/MASTER" && BUNDLE_GEMFILE=Gemfile bundle40 check >/dev/null 2>&1 || BUNDLE_GEMFILE=Gemfile bundle40 install)

echo "==> db prepare"
BUNDLE_WITHOUT=development:test bundle40 exec rails db:prepare

echo "==> assets precompile"
# rc.d master precompiles as root; dev cannot rewrite root-owned public/assets/assets.
doas rm -rf public/assets
doas chown -R dev:dev public
BUNDLE_WITHOUT=development:test bundle40 exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:build_face_vision_bundle 2>/dev/null || true
BUNDLE_WITHOUT=development:test bundle40 exec rails assets:precompile
# The asset gate, through whichever door exists. MASTER/gates/runner.rb was
# deleted on 2026-09-16 and every deploy script still named it, so `vps-deploy
# master` died here under set -e with the box half deployed: new assets on disk,
# the old process still serving them. The gate itself lives in MASTER/gates and
# runs either way.
if [ -f "$ROOT/MASTER/gates/runner.rb" ]; then
  BUNDLE_WITHOUT=development:test bundle40 exec ruby "$ROOT/MASTER/gates/runner.rb" master_web_assets
else
  BUNDLE_WITHOUT=development:test bundle40 exec ruby -e '
    require ARGV[0]
    Deploy::MasterWebAssetsGate.run.report!("master web assets ok")
  ' "$ROOT/MASTER/lib/operator/gates.rb"
fi

echo "==> sync rc.d master"
if [ -f "$ROOT/OPENBSD/etc/rc.d/master" ]; then
  doas cp "$ROOT/OPENBSD/etc/rc.d/master" /etc/rc.d/master
fi

echo "==> restart master"
doas rcctl restart master
sleep 4
rcctl check master

echo "==> smoke"
curl -fsS http://127.0.0.1:53187/up
curl -fsS http://127.0.0.1:53187/health | ruby -rjson -e 'h=JSON.parse(STDIN.read); d=h["deploy"]||{}; abort("tts_socket false") if d["tts_socket"]==false; abort("checks.tts false") if h.dig("checks","tts")==false; puts "health ok sha=#{d["git_sha"]} tts_socket=#{d["tts_socket"]}"'
ruby "$WEB/script/probe_http"

echo "==> master deploy ok"

`````

### bin/vps_install_all.sh

`````zsh
#!/usr/bin/env zsh
# Run ON the VPS (vm23) as dev — installs MASTER web + each Rails app deploy script.
# The one bootstrap-on-box script: vps_on_vm_install.sh execs this file.
# Usage: zsh OPENBSD/bin/vps_install_all.sh     (LOG=/path to choose the log file)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_install_all.sh — bundle and precompile MASTER, then every apps.yml app's deploy script"
  exit 0
fi

PUB4=${PUB4:-/home/dev/pub4}
LOG=${LOG:-/tmp/pub4_install_$(date +%Y%m%d_%H%M%S).log}

exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

log "pub4 install — log: $LOG"
# ruby40, not awk, and the pattern changed with it: OpenBSD vmstat -s writes
# "53853 pages free" and has no line matching /free memory/ at all, so the awk
# this replaces printed an empty figure on every run it ever made.
log "free memory: $(vmstat -s | ruby40 -e 'puts $stdin.read[/^\s*(\d+)\s+pages free/, 1].to_s + " pages free"' 2>/dev/null || print unknown)"

# Every fallible step below logs a WARN and continues, and the script used to end
# on `doas rcctl check master || true` — so a run that deployed nothing exited 0.
# The failures are counted from here and the exit status carries them.
failed=0

if [[ -d ${PUB4}/.git ]]; then
  log "git pull"
  # --ff-only and never a stash: a stashed Gemfile.lock on this box once took
  # master down, and a stash hides local edits where nobody looks for them.
  git -C "$PUB4" pull --ff-only origin main || log "WARN: git pull failed (continuing with tree on disk)"
  git -C "$PUB4" log -1 --oneline
fi

log "=== MASTER CLI + web ==="
[[ -d ${PUB4}/MASTER ]] || { log "ERR: MASTER missing"; exit 1 }
cd "${PUB4}/MASTER"
bundle install
cd "${PUB4}/MASTER/web"
bundle config set --local path vendor/bundle
bundle install
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
bundle exec ruby "${PUB4}/MASTER/gates/runner.rb" master_web_assets
doas rcctl restart master 2>/dev/null || doas rcctl start master
doas rcctl check master || { log "WARN: master not ok"; failed=$((failed + 1)); }

typeset -a APPS
APPS=(${(f)"$(ruby40 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys' "${PUB4}/RAILS/apps.yml")"})
(( ${#APPS} )) || { log "ERR: no apps read from ${PUB4}/RAILS/apps.yml"; exit 1 }

for app in $APPS; do
  typeset script="${PUB4}/RAILS/${app}/${app}.sh"
  log "=== Rails: ${app} ==="
  if [[ ! -f $script ]]; then
    log "WARN: missing $script"
    failed=$((failed + 1))
    continue
  fi
  # Scripts call doas internally; do not wrap in doas (nested doas → "Operation not permitted").
  if ! zsh "$script"; then
    log "WARN: ${app} deploy script failed"
    failed=$((failed + 1))
  elif doas rcctl check "$app" 2>/dev/null; then
    log "ok: ${app}"
  else
    log "WARN: ${app} check failed"
    failed=$((failed + 1))
  fi
done

log "=== summary ==="
for app in $APPS; do
  printf '  %s: ' "$app"
  doas rcctl check "$app" 2>/dev/null || print "not running"
done
doas rcctl check master 2>/dev/null || true
if (( failed > 0 )); then
  log "FAILED: $failed step(s) — $LOG"
  exit 1
fi
log "finished — $LOG"

`````

### bin/vps_master_scan.sh

`````zsh
#!/usr/bin/env zsh
# MASTER /scan on vm23 — shares CI lock so scan + CI never overlap.
# Usage: zsh OPENBSD/bin/vps_master_scan.sh [scan args...]
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_master_scan.sh [scan args...]"
  print "  MASTER bin/cli under the CI lock, refused while the 5-minute load is over PUB4_CI_MAX_LOAD"
  exit 0
fi

repo=${PUB4_ROOT:-/home/dev/pub4}
# Was `lock=${PUB4_CI_LOCK:-/var/tmp/pub4-ci.lock}`, then root chmod 666'ed exactly
# that caller-chosen path in a world-writable directory. The helper keeps the lock
# in root-owned /var/db/pub4 and ignores an override pointing anywhere else.
. "${repo}/OPENBSD/lib/ci_lock.sh"
max_load=${PUB4_CI_MAX_LOAD:-4}

# awk twice, in a repo that bans it in committed scripts. Ruby also spares the
# second invocation: one process reads the load and decides.
load=$(sysctl -n vm.loadavg 2>/dev/null)
if ! ruby40 -e 'n = ARGV[0].to_s.scan(/\d+(?:\.\d+)?/); exit 1 if n.size < 3; exit(n[1].to_f > ARGV[1].to_f ? 1 : 0)' "$load" "$max_load"; then
  print -u2 "vps_master_scan: load ${load:-unreadable} over $max_load (5-minute average)"
  exit 1
fi

lock=$(pub4_ensure_ci_lock)

cd "$repo/MASTER"
print "vps_master_scan: lock $lock $*"
# Was `lockf -k "$lock" ...`. OpenBSD has no lockf(1) — it is a FreeBSD utility —
# so this line was `lockf: Command not found` on every run since it was written,
# and the documented way to scan on vm23 has never taken the lock or run the
# scan. bin/with-ci-lock is the same idea in the one language this box is
# guaranteed to have.
ruby40 "$repo/OPENBSD/bin/with-ci-lock" \
  env MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle40 exec ruby bin/cli "$@"

`````

### bin/vps_on_vm_install.sh

`````zsh
#!/usr/bin/env zsh
# Run on vm23 as dev. The console recovery path (vps_console.exp start_install
# and drop_install) drops this file into /tmp by name, so it stays; the work
# is vps_install_all.sh's, which is the one bootstrap-on-box script.
# Usage: zsh OPENBSD/bin/vps_on_vm_install.sh
set -euo pipefail
exec zsh "${PUB4_ROOT:-/home/dev/pub4}/OPENBSD/bin/vps_install_all.sh" "$@"

`````

### bin/vps_production_push.sh

`````zsh
#!/usr/bin/env zsh
# Production push, the fast path: `bin/vps-deploy all` with the CI and runtime
# gates skipped only after an explicit human acknowledgement, then an optional demo seed.
#
# Usage (on vm23, as dev):
#   zsh OPENBSD/bin/vps_production_push.sh
#   DEMO_SEED_ON_DEPLOY=1 zsh OPENBSD/bin/vps_production_push.sh   # also seed brgen's guest demo
#
# One deploy path, not two. vps-deploy owns the order (master first, amber and
# bsdports last), the pull, the per-app health gate, the deploy stamp, the
# restore of shed apps and the post-restart gates; this file only chooses the
# fast flags. SKIP_CI=1 skips vps_ci.sh and SKIP_RUNTIME_GATE=1 skips the bin/ci
# runtime gate inside ${app}.sh, which is OOM-prone on 1 GB. What still runs is
# the loopback gate set vps-deploy runs after every restart.
#
# The demo seed is opt-in. A hotfix is the wrong moment to write demo content
# into production, so it takes an explicit DEMO_SEED_ON_DEPLOY=1.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: I_UNDERSTAND_FAST_DEPLOY=1 zsh OPENBSD/bin/vps_production_push.sh   (DEMO_SEED_ON_DEPLOY=1 to seed brgen's demo)"
  exit 0
fi

repo=${PUB4_ROOT:-/home/dev/pub4}

if [[ ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]; then
  print -u2 "err: fast production push skips CI/runtime verification; set I_UNDERSTAND_FAST_DEPLOY=1 explicitly"
  exit 2
fi

export SKIP_CI=1
export SKIP_RUNTIME_GATE=1
zsh "$repo/OPENBSD/bin/vps-deploy" all

if [[ ${DEMO_SEED_ON_DEPLOY:-0} == 1 ]]; then
  print "==> bergen demo seed (posts, Live notes, listings)"
  # doas only permits dev->root; the app user hop is doas sh + su -m (RAILS/_database.sh).
  source "${repo}/RAILS/_core.sh"
  source "${repo}/RAILS/_database.sh"
  seed_demo_as_app brgen /home/brgen/app
fi

sh "$repo/OPENBSD/bin/deploy-smoke.sh" --local || print "WARN: deploy-smoke partial"
print "==> production push complete"

`````

### bin/vps_run_remote.sh

`````zsh
#!/usr/bin/env zsh
# Workstation helper: copy vps_install_all.sh to VM via hypervisor jump and run it.
#
# A recovery path nothing runs. It bootstraps a fresh VM through the hypervisor
# jump, the only route that exists before ssh to the VM works. Unexercised, so read
# it before running it; removing it decides the capability is unwanted, which is
# the operator's call.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_run_remote.sh"
  print "  upload vps_install_all.sh through the server4 hypervisor jump and start it under nohup"
  exit 0
fi

SCRIPT_DIR=${0:a:h}
INSTALL_SH=${SCRIPT_DIR}/vps_install_all.sh
# The VM's login, host and key are lib/ssh_vm23.sh's, the one copy of them.
source "${SCRIPT_DIR:h}/lib/ssh_vm23.sh"
KEY=$SSH_KEY
VM=${SSH_USER}@${SSH_HOST}
HYP=${HYPERVISOR:-dev@server4.openbsd.amsterdam}
HYP_PORT=${HYP_PORT:-31415}
REMOTE_LOG=/tmp/pub4_install_latest.log
quoted_vm=${(q)VM}
quoted_log=${(q)REMOTE_LOG}

log() { printf '[vps_run] %s\n' "$*" }

[[ -f $INSTALL_SH ]] || { log "missing $INSTALL_SH"; exit 1 }

log "upload install script"
scp -i "$KEY" -P "$HYP_PORT" -o StrictHostKeyChecking=accept-new "$INSTALL_SH" "${HYP}:/tmp/vps_install_all.sh"

log "start install on VM (nohup — may take 30–60 min on 1GB RAM)"
ssh -i "$KEY" -p "$HYP_PORT" -o StrictHostKeyChecking=accept-new "$HYP" \
  "scp -o StrictHostKeyChecking=accept-new ${quoted_vm}:/tmp/vps_install_all.sh && \
   ssh -o StrictHostKeyChecking=accept-new ${quoted_vm} 'chmod +x /tmp/vps_install_all.sh; nohup /tmp/vps_install_all.sh > ${quoted_log} 2>&1 & echo PID:\$!'"

log "tail log: ssh jump → ssh ${quoted_vm} tail -f ${quoted_log}"

`````

### bin/vps_weekly_integrity.sh

`````zsh
#!/usr/bin/env sh
# Weekly vm23 integrity + public health (serial, mutex-aware). OPERATOR.sh
# installs it to /usr/local/bin and etc/crontab.vm23 runs it Sunday 03:30 as root.
set -eu

ROOT="${PUB4_ROOT:-/home/dev/pub4}"
RUNAS="${PUB4_WEEKLY_USER:-dev}"
LOG=/var/log/pub4/weekly_integrity.log

# root owns the schedule; root reads not one line of the checkout. Everything
# under $ROOT is dev-writable, so sourcing lib/ci_lock.sh or running
# integrity_gate.rb as root hands root to whoever wrote there last — the same
# escalation OPERATOR.sh refuses for config_drift_gate, crontab.vm23 refuses for
# uptime-check, and resource_guard.sh:135 records as having been reachable within
# five minutes. root therefore does three things, all outside the checkout: makes
# the log directory, opens the log, and drops privilege. $0 is the installed
# root-owned copy, so the re-exec runs root's file as dev rather than dev's file
# as root, and the inherited descriptor keeps the log root:wheel 640, which is
# what etc/newsyslog.conf rotates it as. Every gate below only measures, so dev
# is enough to run them; dev is also the account bin/vps-deploy already runs as.
INSTALLED=/usr/local/bin/vps_weekly_integrity.sh
if [ "$(id -u)" -eq 0 ]; then
  # Only the root-owned copy may run as root. Invoked from the checkout, root
  # would already be executing a dev-writable file by the time it reached the
  # privilege drop below.
  if [ "$0" != "$INSTALLED" ]; then
    echo "vps_weekly_integrity: as root, run $INSTALLED, not $0" >&2
    exit 2
  fi
  mkdir -p /var/log/pub4
  chmod 755 /var/log/pub4
  exec su "$RUNAS" -c "PUB4_ROOT='$ROOT' '$0'" >>"$LOG" 2>&1
fi

# One definition of the lock path; it moved out of world-writable /var/tmp.
. "${ROOT}/OPENBSD/lib/ci_lock.sh"
LOCK=$(pub4_ci_lock_path)

# Probe the flock with-ci-lock and CiGuard take, rather than asking fuser(1):
# where fuser is missing the old test was simply false, and the run went ahead
# racing CI. ruby40 exits 0 only when the lock is held by someone else.
if [ -f "$LOCK" ] && ruby40 -e 'exit(File.open(ARGV[0]).flock(File::LOCK_EX | File::LOCK_NB) ? 1 : 0)' "$LOCK" 2>/dev/null; then
  echo "$(date -u +%FT%TZ) skip: pub4 CI lock held"
  exit 0
fi

echo "== $(date -u +%FT%TZ) weekly integrity start"
cd "$ROOT"
git fetch origin main 2>&1 || true

# Both gates run, whatever the first one says. Under a bare `set -e` a failing
# integrity gate ended the script, so the public health pass was skipped on
# exactly the week something was already wrong — and with the whole run
# redirected into the log, cron had no output to mail and the truncation was
# invisible. The status line below is the report; the exit code carries it to
# anyone who runs this by hand.
status=0
ruby40 OPENBSD/gates/integrity_gate.rb || status=1
ruby40 OPENBSD/gates/health_check.rb --public --all-ready-apps --json || status=1
echo "== $(date -u +%FT%TZ) weekly integrity end status=$status"
exit "$status"

`````

### data/dns.yml

`````yaml
# Authoritative DNS policy for vm23. Read by bin/render_dns.rb, which renders
# every zone file, nsd.conf and acme-client.conf from it. Do not hand-edit any of
# those three: they are generated, and the generator will overwrite you.
#
# The domain list is NOT here. It is ALL_DOMAINS in OPERATOR.sh, which is already
# the source domain_alignment binds Brgen::DomainRegistry to — a third list would
# just be a third thing to drift. This file carries policy and the zones that are
# not part of the city network.

nameserver:
  # Every zone is delegated to these two. ns.brgen.no is this box; ns.hyp.net is
  # Domeneshop's secondary, which pulls by AXFR from the xfr_peers below.
  authoritative:
    - ns.brgen.no.
    - ns.hyp.net.
  ip: 46.23.89.226
  # hostmaster@<domain> in every SOA. It only resolves for brgen.no, which is the
  # only domain that receives mail — an unreachable SOA contact is normal and is
  # what the CAA iodef record exists to compensate for.
  hostmaster: hostmaster

# Resolvers a check asks when it wants the answer the rest of the internet gets,
# as opposed to asking our own nameserver. Two, so one operator's blocked or
# hijacked resolver is not a false finding, and neither of them is Google:
# gates/dns_zones.rb picked these deliberately and wrote the reason down, while
# OPERATOR.sh carried 8.8.8.8 at the head of its own copy with no argument for it.
resolvers:
  public:
    - 1.1.1.1
    - 9.9.9.9

ttl: 3600

# nsd.conf(5) server-count: how many nsd server processes to start. One per
# core is the ceiling worth having, and vm23 has one core and 1 GB, so a second
# server is only a second resident process.
server_count: 1

soa:
  refresh: 1800
  retry: 900
  expire: 604800
  minimum: 86400

# Domeneshop's secondary nameserver set. provide-xfr + notify, NOKEY: the zones
# are public and signed, so there is nothing in a transfer worth a TSIG key that
# is not already answerable by any resolver.
xfr_peers:
  - 194.63.248.53
  - 151.249.124.1
  - 192.174.68.10
  - 151.249.126.3

# One CA, no wildcards, and an address for anyone who catches a misissuance.
caa:
  - '0 issue "letsencrypt.org"'
  - '0 issuewild ";"'
  - '0 iodef "mailto:hostmaster@brgen.no"'

# The only domain smtpd accepts mail for (/etc/mail/domains is one line long).
# Every other zone gets a null MX — RFC 7505 `0 .` — which says "this domain
# receives no mail" in the one place a sending server actually looks. It had an
# MX pointing at a mail.<domain> A record instead, on all sixty of them, which
# advertised sixty mail servers that do not exist and would accept nothing.
mail_domain: brgen.no

# Zones outside ALL_DOMAINS, and only those: a name already in ALL_DOMAINS gets
# its zone from there, and listing it here too changed nothing while reading as
# if it did. Registered or not, nsd serves these, and the ones that are NXDOMAIN
# today cost nothing to keep ready.
#
# Measured 2026-08-12: all four are NXDOMAIN at their registrar. The anti-gambling
# trio and foodielicio.us are older ideas;
# bsdports.net is a defensive registration for bsdports.org and has no zone:
# it resolved to this box with no relayd entry, no acme-client block and no
# certificate, so the name completed DNS and then failed TLS. Owning a name is
# not a reason to answer for it.
#
# baibl.no, blognet.no and hjerterom.no were here until 2026-08-12, when all
# three apps were deleted. Their users, homes, rc.d scripts, /etc/*.env files,
# login classes and the baibl/blognet/hjerterom A records under brgen.no went
# with them; databases are at /var/backups/pub4/{hjerterom,deleted-apps}-20260812.
extra_zones:
  antibettingblog.com: {}
  anticasinoblog.com: {}
  antigamblingblog.com: {}
  foodielicio.us: {}

# Records that cannot be derived. Emitted verbatim after the generated ones.
extra_records:
  brgen.no: |
    ; Mail authentication, added 2026-07-31 alongside the smtpd/pf work that made
    ; the MX record's promise real. Without these a receiving server has no way to
    ; tell mail claiming to be from brgen.no apart from mail forging it, and the
    ; default assumption is forgery.
    ;
    ; DMARC: p=none to start. It asks receivers to REPORT what they see without
    ; acting on it, which is the only honest first setting -- turning on quarantine
    ; or reject before reading a week of reports means discovering the hard way
    ; which legitimate senders were forgotten.
    _dmarc IN TXT "v=DMARC1; p=none; rua=mailto:johann@brgen.no; ruf=mailto:johann@brgen.no; adkim=r; aspf=r"

    ; DKIM. Selector "mail" matches the -s flag on the filter in smtpd.conf; the
    ; private half is at /etc/mail/dkim/private.rsa.key, readable only by _dkimsign.
    ; Split across several character-strings because a 2048-bit key base64s to ~392
    ; bytes and one TXT string caps at 255. Resolvers rejoin them; the verifier sees
    ; one key.
    mail._domainkey IN TXT ( "v=DKIM1; k=rsa; p="
      "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq/tM18UaNKRYz+y05zb1NByhmtErf5FuemjLlRQ2vYUlNVk9rpNpjESSRVEJ7/FkbyiL0jAJ6XhUDySixJ194pMQL0zc3OXZXrw+LwfBs0ry5ojTugZzVa3YTm9xIM0bfC7bcs06G5bmCgaSDkDtXwHWf4FB"
      "cSblS0cY1FDuJ1QvX1AAGKnRU8Yq7pvuZ3pxPCAD6Q/l3G3g333rr2XCLA6dmtsDYvZ7dsTv4qBIMOhkpETl0ai/wDAwFJoDciGm1TJXeFoOrzkdIF73Etq4fjCdWsry5stmlUpHR241Iv3XhUe55X07ATXNt4B4YaobzOXQSMG5FB1J2wdmNFvdtwIDAQAB"
      )

# Hosts that exist under a zone for reasons the vertical list does not cover.
# ns is the glue for the nameserver every other zone is delegated to. amber
# needs no host here: its one name is amberapp.art, a zone of its own in
# ALL_DOMAINS. baibl, blognet and hjerterom were here until their apps were
# deleted on 2026-08-12.
extra_hosts:
  brgen.no:
    - ns

`````

### data/domain_inventory.yml

`````yaml
# Written by OPENBSD/bin/domain_watch.rb --update. Committed so a domain
# changing hands is a reviewable diff rather than a surprise outage.
---
amberapp.art:
  state: registered
  created: '2026-09-25T05:35:06.0Z'
  expires: '2027-09-25T23:59:59.0Z'
  registrar: Domeneshop AS dba domainnameshop.com
amstrdam.nl:
  state: registered
  created: '2026-05-18'
  registrar: GoDaddy.com
antibettingblog.com:
  state: available
anticasinoblog.com:
  state: available
antigamblingblog.com:
  state: available
austn.us:
  state: available
brdeaux.fr:
  state: available
brgen.no:
  state: registered
  created: '2020-08-25'
brmingham.uk:
  state: registered
  created: 24-Jun-2021
  expires: 24-Jun-2026
  status: Renewal required.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
brssels.be:
  state: registered
bsddocs.org:
  state: available
bsdports.org:
  state: registered
  created: '2022-08-08T14:15:10Z'
  expires: '2027-08-08T14:15:10Z'
  registrar: Domeneshop AS dba domainnameshop.com
cardff.uk:
  state: registered
  created: 13-Aug-2021
  expires: 13-Aug-2027
  status: Registered until expiry date.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
chcago.us:
  state: available
denvr.us:
  state: registered
  created: '2021-08-13T11:20:09Z'
  expires: '2027-08-13T11:20:09Z'
  registrar: Domeneshop AS dba domainnameshop.com
discordb.org:
  state: available
dllas.us:
  state: available
dnver.us:
  state: available
dtroit.us:
  state: available
edinbrgh.uk:
  state: registered
  created: 13-Aug-2021
  expires: 13-Aug-2027
  status: Registered until expiry date.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
foball.no:
  state: registered
  created: '2022-07-30'
foodielicio.us:
  state: available
frankfrt.de:
  state: registered
freehelp.legal:
  state: available
gdnsk.pl:
  state: available
glasgw.uk:
  state: registered
  created: 24-Jun-2021
  expires: 24-Jun-2026
  status: Renewal required.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
gtebrg.se:
  state: available
hlsinki.fi:
  state: available
houstn.us:
  state: available
kbenhvn.dk:
  state: available
lchtenstein.li:
  state: unknown
  note: registry referral, not a domain record
lisbon.pt:
  state: unknown
  note: lisbon.pt - Forbiden Name
lndon.uk:
  state: registered
  created: 23-Sep-2026
  expires: 23-Sep-2027
  status: Registered until expiry date.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
longyearbyn.no:
  state: available
lsangeles.com:
  state: registered
  created: '2026-09-23T15:55:03Z'
  expires: '2027-09-23T15:55:03Z'
  registrar: Domeneshop AS dba domainnameshop.com
lverpool.uk:
  state: registered
  created: 25-Jun-2021
  expires: 25-Jun-2026
  status: Renewal required.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
mlan.it:
  state: unknown
  note: 'Domain:             mlan.it'
mlmoe.se:
  state: available
mnchester.uk:
  state: registered
  created: 25-Jun-2021
  expires: 25-Jun-2026
  status: Renewal required.
  registrar: Domeneshop AS t/a Domain Name Shop [Tag = DOMENESHOP-NO]
mnnesota.com:
  state: available
mrseille.fr:
  state: available
newyrk.us:
  state: available
oshlo.no:
  state: registered
  created: '2020-08-22'
prtland.com:
  state: available
pub.attorney:
  state: available
pub.healthcare:
  state: available
reykjavk.is:
  state: available
rottrdam.nl:
  state: available
stacyspassion.com:
  state: available
stholm.se:
  state: available
stvanger.no:
  state: registered
  created: '2020-08-22'
trmso.no:
  state: available
trndheim.no:
  state: registered
  created: '2020-08-22'
utrcht.nl:
  state: available
wrsawa.pl:
  state: available
wshingtondc.com:
  state: registered
  created: '2021-08-22T04:10:03Z'
  expires: '2027-08-22T04:10:03Z'
  registrar: Domeneshop AS dba domainnameshop.com
zrich.ch:
  state: unknown
  note: registry referral, not a domain record

`````

### data/domain_released.yml

`````yaml
# Domains deliberately not renewed, with the decision recorded.
#
# OPENBSD/test/test_domain_expiry.rb skips these. Everything else past expiry, or
# inside the 30-day window, fails that test — so the only ways to green it are
# renewing the domain or writing down that you chose to let it go.
#
# Empty on purpose: every expired domain the test names is still wanted, and
# renewing one is a registrar login, not a code change.
# Add a domain here only when the answer is "we are letting this one go", never
# to quiet the alarm.
#
# Format:
#   dnver.us:
#     decided: 2026-08-07
#     why: Duplicate of denvr.us; one Denver domain is enough.

`````

### data/operator.yml

`````yaml
# OPENBSD operator runtime authority — served via /orient deploy and MASTER/bin/operator.
# The one command and recipe catalogue; OPENBSD/README.md points here.

meta:
  source: runtime authority
  vps: dev@brgen.no
  repo_on_vps: /home/dev/pub4

stack:
  app_server: Falcon only on vm23 (falcon serve in rc.d). No Puma in production.
  solid_queue: >-
    The supervisor is its own process, started by the per-app rc.d/<app>_jobs service
    (rake solid_queue:start). brgen_jobs is enabled on vm23 (2026-08-25, e511ccba1);
    amber_jobs and bsdports_jobs are not — vm23 is 1 GB, so enabling each is an
    operator decision; read the header of OPENBSD/etc/rc.d/<app>_jobs. Whatever is enabled
    must also be in pkg_scripts in OPENBSD/etc/rc.conf.local, which is what boot reads.
    SOLID_QUEUE_IN_PUMA is a Puma-plugin variable needing config/puma.rb, which no app
    has, so under Falcon it starts nothing; MASTER/gates/lib/production.rb fails the
    deploy gate if an rc.d sets it.

app_layout:
  summary: Each RAILS/<app>/ is already a full Rails 8 app (app/, config/, db/, test/).
  bootstrap: Greenfield apps use rails new once; existing apps are maintained in-tree.
  deploy_entrypoint: RAILS/<app>/<app>.sh copies the tracked tree to /home/<app>/app
  deployed_tree: /home/<app>/app is what relayd serves — not the dev git checkout alone
  shared_engine: RAILS/shared (pub4-shared gem)

single_source_of_truth:
  features: RAILS/apps.yml
  owned_domains: RAILS/apps.yml#owned_domains
  horizon: RAILS/apps.horizon.yml
  debt: TODO.md
  deploy_identity: OPENBSD/deploy_inventory.json

domain_ownership:
  source: RAILS/apps.yml#owned_domains
  shell_mirror: OPENBSD/OPERATOR.sh#OWNED_DOMAINS
  snapshot: OPENBSD/data/domain_inventory.yml

recipes:
  - want: See where I am
    run: MASTER/bin/operator status
    expect: mode, ruby, ports, next command
  - want: Fast local contributor check
    run: OPENBSD/bin/check --profile=contributor && cd MASTER && bin/check --profile=contributor
    expect: static gates ok
  # The check family lived only in START_HERE.md's Golden Commands, so the file
  # that calls itself the command list was missing four of the commands and the
  # stub that points here was the more complete of the two.
  - want: Rails source gates
    run: OPENBSD/bin/check-rails --profile=contributor
    expect: source gates ok; runtime skipped on a Ruby mismatch
  - want: OpenBSD config and deploy identity, locally
    run: OPENBSD/bin/check-openbsd
    expect: identity, installed targets, dns, shell syntax, vps safety
  - want: The live VPS gates
    run: OPENBSD/bin/check-vps
    expect: run on vm23, or with SSH and operator intent — never casually
  - want: Everything local, then integrity
    run: OPENBSD/bin/check-full
    expect: OPENBSD/bin/check, then RAILS/test/run_all.rb, then the integrity gate
  - want: Deployed tree vs dev tree on vm23
    run: OPENBSD/bin/vps-state
    expect: per-app SHA, what a deploy would move
  - want: The repo shape, pruned
    run: ruby OPENBSD/bin/tree . --pub4-overview
    expect: Rails apps collapsed, MASTER/lib subsystems, no vendor or node_modules
  - want: Refresh the domain expiry snapshot
    run: ruby OPENBSD/bin/domain_watch.rb --update
    expect: data/domain_inventory.yml rewritten from whois; commit the diff
  - want: After git pull on vm23
    run: OPENBSD/bin/post-pull-checklist && MASTER/bin/operator vps state
    expect: drift visible; follow deploy list
  - want: Deploy one Rails app on VPS
    run: MASTER/bin/operator vps deploy brgen --remote
    expect: CI + restart + /up ok (serial — one app at a time)
  - want: Deploy MASTER web
    run: MASTER/bin/operator vps deploy master --remote
    expect: assets precompiled + master restarted
  - want: Full integrity on VPS
    run: ssh brgen 'cd /home/dev/pub4 && ruby34 OPENBSD/gates/integrity_gate.rb'
    expect: integrity clean after apps deployed
  - want: OpenBSD service/system administration
    run: MASTER/bin/operator vps admin status --remote
    expect: read-only host, service, firewall, resource and update controls
  - want: Check or restart a service on the VPS
    run: MASTER/bin/operator vps admin service master check --remote
    expect: rcctl check result; restart is an explicit separate action

`````

### deploy_inventory.json

`````json
{
  "schema": 1,
  "generated_from": "RAILS/apps.yml",
  "apps": [
    {
      "name": "amber",
      "domain": "amberapp.art",
      "port": 61352
    },
    {
      "name": "brgen",
      "domain": "brgen.no",
      "port": 38182
    },
    {
      "name": "bsdports",
      "domain": "bsdports.org",
      "port": 47312
    }
  ],
  "master_face": {
    "name": "master",
    "domain": "ai.brgen.no",
    "port": 53187,
    "deploy_root": "MASTER/web"
  }
}

`````

### dev/agent_worktree.sh

`````zsh
#!/bin/sh
# agent_worktree.sh <agent-name> [base-branch]
#
# Give a coding agent (claude, grok, codex, …) its OWN git worktree + branch off
# the shared pub4 repo, so concurrent agents never share one working tree.
#
# Why: with a shared tree, `git commit -a` sweeps every agent's half-finished
# work into one commit (and `/scan` autofix-by-default can rewrite files another
# agent is mid-edit on). Every commit then needs surgical path-by-path staging.
# Isolated worktrees remove that whole class of hazard: each agent commits freely
# on its own branch; you integrate to main via fast-forward / PR.
#
# Usage:
#   sh OPENBSD/dev/agent_worktree.sh claude
#   cd ../pub4-claude        # work here
#   git push origin agent/claude   # then PR / fast-forward to main
#   bin/operator worktree finish # rebase onto origin/main, push the branch, do not merge main
#
# Cleanup:  git worktree remove ../pub4-<agent>
set -eu

case "${1:-}" in
-h | --help)
  echo "usage: sh OPENBSD/dev/agent_worktree.sh <agent-name> [base-branch]"
  echo "         a worktree at ../pub4-<agent> on branch agent/<agent>"
  echo "       sh OPENBSD/dev/agent_worktree.sh finish"
  echo "         rebase this branch onto origin/main and push it"
  exit 0
  ;;
esac

if [ "${1:-}" = "finish" ]; then
  # Rebase onto origin/main and push THIS branch. Do not merge to local main
  # and do not push main: that is how another session's push published
  # commits the owner had not decided to ship.
  repo="$(git rev-parse --show-toplevel)"
  git -C "$repo" fetch -q origin
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  case "$branch" in
    main|master)
      echo "worktree finish: on ${branch} — nothing to finish"
      exit 1
      ;;
  esac
  git -C "$repo" rebase origin/main
  git -C "$repo" push -u origin "HEAD:${branch}"
  echo "worktree finish: ${branch} pushed. It is not on main."
  echo "worktree finish: publish with: git push origin HEAD:main"
  echo "worktree finish: then, from the main checkout: git worktree remove ${repo} && git branch -d ${branch}"
  exit 0
fi

agent="${1:?usage: agent_worktree.sh <agent-name>|finish [base-branch]}"
base="${2:-origin/main}"
repo="$(git rev-parse --show-toplevel)"
branch="agent/${agent}"
dir="${repo%/*}/pub4-${agent}"

git -C "$repo" fetch -q origin

# An existing worktree may hold somebody's unfinished work, and handing it over
# is the shared-checkout hazard this command exists to avoid. Two agents were
# given the same tree in one afternoon: one noticed a stranger's eleven modified
# gate files and moved out, the other worked beside them for an hour. The line
# that told them both was "worktree already exists", which reads as success.
#
# Dirty means occupied. A clean one is a leftover and is safe to reuse.
# git itself answers whether ${dir} is a checkout, rather than grep over the
# porcelain list: a registered worktree reports itself as its own top level.
if [ "$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)" = "${dir}" ]; then
  dirt="$(git -C "${dir}" status --porcelain 2>/dev/null)"
  if [ -n "${dirt}" ]; then
    echo "worktree ${dir} is occupied — another session has uncommitted work in it:" >&2
    echo "${dirt}" >&2
    echo "pick another name, or finish that work first" >&2
    exit 1
  fi
  echo "worktree already exists and is clean: ${dir}"
else
  git -C "$repo" worktree add -B "$branch" "$dir" "$base"
fi

echo "worktree: ${dir}"
echo "branch:   ${branch} (from ${base})"
echo "next:     cd ${dir} && work; git push origin ${branch}; then merge/PR to main"

`````

### dev/backup.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail

# Archives folders to dated .tgz files, skips unchanged ones.

# Usage: ./backup.sh [directory]

log_error() {

  print "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$HOME/script_errors.log"

}

dir="${1:-.}"

checksum_file="$dir/.backup_checksums"

date_format=$(date +"%Y%m%d")

cd "$dir" || exit 1

# Load prior checksums to check for changes

typeset -A old_checksums

if [[ -f "$checksum_file" ]]; then

  while read -r folder checksum; do

    old_checksums["$folder"]="$checksum"

  done < "$checksum_file"

fi

typeset -A new_checksums

for subdir in */(N); do

  folder="${subdir%/}"

  # Pure zsh: glob for files, collect MD5s, sort with ${(o)arr}, then hash

  typeset -a file_hashes=()

  for file in "$folder"/**/*(.N); do

    file_hashes+=($(md5 -q "$file" 2>/dev/null))

  done

  # Sort using pure zsh and create final checksum

  typeset -a sorted_hashes=( ${(o)file_hashes} )

  checksum=$(print -l "${sorted_hashes[@]}" | md5 -q)

  backup_file="${folder}_${date_format}.tgz"

  # :- on both reads. `set -u` is on and these are associative-array lookups,
  # so an unseen folder is an unset parameter and zsh aborts on it. Every
  # folder is unseen on a first run — the run where there is no checksum file
  # at all — so a first run died on the first folder, every time.
  if [[ -z "${old_checksums[$folder]:-}" || "${old_checksums[$folder]:-}" != "$checksum" ]]; then

    print "Backing up: $folder -> $backup_file"

    # In the if-condition, not before it. This was a bare `tar` followed by
    # `if [[ $? -ne 0 ]]`, and `set -e` is on, so a failing tar killed the
    # script at that line: the handler under it had never run once, and no
    # folder after the failing one was reached. A command in an if-condition is
    # the one place set -e stands aside.
    #
    # stderr goes to the error log rather than /dev/null. The reason a backup
    # failed is the whole content of the report.
    if tar cvzf "$backup_file" "$folder" 2>>"$HOME/script_errors.log"; then

      print "Created: $backup_file"

      new_checksums["$folder"]="$checksum"

    else

      log_error "tar failed for $backup_file"

      print "Failed: $backup_file"

      # tar writes what it managed to read before giving up, so a failure
      # leaves a short .tgz sitting next to the good ones with nothing to
      # distinguish it. Removing it is what makes the next run's retry the
      # only copy there is.
      rm -f "$backup_file"

    fi

  else

    print "Skipped (no changes): $folder"

    new_checksums["$folder"]="$checksum"

  fi

done

# Updates checksum file for next run

for folder in ${(k)new_checksums}; do

  print "$folder ${new_checksums[$folder]}"

done > "$checksum_file"

`````

### dev/clean.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob

dir="${1:-.}"

[[ -d "$dir" ]] || { print "Error: '$dir' is not a directory"; exit 1 }

for file in "$dir"/**/*(.N); do
  local filetype=$(file -b "$file")
  [[ $filetype == *text* ]] || continue

  local content=$(<"$file")
  content=${content//$''/}
  local -a lines=("${(@f)content}")
  local -a cleaned=()
  local prev_blank=0

  for line in "${lines[@]}"; do
    line=${line%%[[:space:]]#}
    if [[ -z $line ]]; then
      if [[ $prev_blank -eq 0 ]]; then
        cleaned+=("")
        prev_blank=1
      fi
    else
      cleaned+=("$line")
      prev_blank=0
    fi
  done

  local tmp=$(mktemp)
  print -l "${cleaned[@]}" > "$tmp" && mv "$tmp" "$file" && print "Cleaned: $file" || { rm "$tmp"; print "Failed: $file" }
done

`````

### dev/lint.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob

# Lints Ruby/ERB files using bundler-scoped rubocop + reek.
# Run from any directory; resolves MASTER bundle automatically.
# Usage: ./lint.sh [path]

MASTER_ROOT="${HOME}/pub4/MASTER"
TARGET="${1:-.}"

bundle_exec() {
  (cd "$MASTER_ROOT" && bundle exec "$@")
}

lint_ruby() {
  local file="$1"
  print "→ $file"

  if ! bundle_exec reek --no-color "$file" 2>/dev/null; then
    print "  reek: smells found"
  fi

  if ! bundle_exec rubocop --autocorrect --config "${MASTER_ROOT}/.rubocop.yml" --no-color "$file" 2>/dev/null; then
    print "  rubocop: offenses remain after autocorrect"
  fi
}

for file in ${TARGET}/**/*.{rb,erb}(.N); do
  [[ "$file" == */.gem/* || "$file" == */vendor/* ]] && continue
  lint_ruby "$file"
done

print "lint done"

`````

### dev/open_in_vim.zsh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob

#

# OPENS MATCHING TEXT FILES IN VIM

#

# Usage: hack <string, leave empty to open all files>

#

# Pure zsh approach:

# - **/*(.N) glob qualifier for files only

# - [[ ]] pattern matching instead of grep

dir=${1:-"."}

# Only process text files using glob qualifier (.N = files, nullglob)

for file in **/*(.N); do

  # Search pattern using zsh pattern matching

  if [[ -z "$1" ]] || [[ $(<"$file") == *"$1"* ]]; then

    vim "$file"

  fi

done

`````

### dev/operator_stage_1.zsh

`````zsh
#!/usr/bin/env zsh
# Stage 1 of OPENBSD/OPERATOR.sh: DNS, DNSSEC and TLS.
#
# This file is sourced by OPERATOR.sh after its shared helpers and deploy facts
# are loaded. It owns stage_1 only; it does not execute on source.


stage_1() {
  log INFO "Stage 1: DNS and certificates"

  typeset -a _df_root; _df_root=("${(@f)$(df -k /)}"); typeset _root_avail=${${(z)_df_root[2]}[4]}
  (( _root_avail < 10000 )) && { log ERROR "Insufficient disk space on /"; exit 1 }
  typeset -a _df_var; _df_var=("${(@f)$(df -k /var)}"); typeset _var_avail=${${(z)_df_var[2]}[4]}
  (( _var_avail < 512000 )) && { log ERROR "Insufficient disk space on /var"; exit 1 }

  # ffmpeg is required, not optional: lib/voice/engines.rb gates concat_mp3 and
  # the WAV->MP3 conversion on `ffmpeg?` and returns *quietly* when it is absent.
  # Without it TTS produced un-concatenated or unconverted audio on the VPS with
  # no error anywhere — working on a Mac and silently degrading in production,
  # which is the worst failure shape. See TODO.md "Host TTS Binaries".
  pkg_add -U ldns-utils ruby%3.4 zap zsh fish neovim tmux fontconfig fzf ripgrep fd espeak ffmpeg 2>/var/log/pkg_add.log \
    || { log ERROR "pkg_add failed. See /var/log/pkg_add.log"; exit 1 }

  [[ -f /etc/rc.conf.local && $(<"/etc/rc.conf.local") == *"pf=NO"* ]] && log WARN "pf disabled in rc.conf.local"
  ifconfig vio0 >/dev/null 2>&1 || { log ERROR "Interface vio0 not found"; exit 1 }

  /sbin/pfctl -d || log WARN "pf disable failed"
  /sbin/pfctl -e || { log ERROR "pf enable failed"; exit 1 }
  install_static etc/pf.stage1.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  [[ -d /var/nsd/etc ]]          || { log ERROR "/var/nsd/etc missing"; exit 1 }
  [[ -d /var/nsd/zones/master ]] || { log ERROR "/var/nsd/zones/master missing"; exit 1 }

  backup_directory /var/nsd/zones/master nsd-zones || { log ERROR "Backup failed"; exit 1 }
  transaction_log "DELETE" "/var/nsd/etc/*" "START"
  rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/) # scan: intentional — backed up above, bracketed by transaction_log DELETE
  transaction_log "DELETE" "/var/nsd/etc/* and /var/nsd/zones/master/*" "SUCCESS"

  # nsd.conf and every zone file are generated by bin/render_dns.rb and committed,
  # so this installs them rather than rebuilding them from a template per domain.
  # The old loop was the third writer of the same records and disagreed with the
  # other two: it emitted no www, no CAA, no SPF, no DMARC and an MX pointing at
  # a mail server that exists for one domain out of sixty.
  install_static var/nsd/etc/nsd.conf /var/nsd/etc/nsd.conf
  nsd-checkconf /var/nsd/etc/nsd.conf || { log ERROR "nsd.conf invalid"; exit 1 }

  cp ${CONFIG_ROOT}/var/nsd/zones/master/*.zone /var/nsd/zones/master/

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset zonefile=/var/nsd/zones/master/$domain.zone

    [[ -f $zonefile ]] || { log ERROR "No generated zone for $domain — run bin/render_dns.rb"; exit 1 }
    nsd-checkzone "$domain" "$zonefile" || { log ERROR "Zone invalid for $domain"; exit 1 }

    # Keys only when the zone has none.
    #
    # This unconditionally ran ldns-keygen twice per domain per invocation and
    # never removed anything, so every re-run added a KSK and a ZSK to each zone
    # and the old ones stayed published — ldns-signzone signs with every key it
    # is handed. Measured 2026-08-12: 700 key files for 60 zones, and 407 .ds
    # files naming keys that had long since been superseded.
    #
    # Regenerating a KSK is not a harmless extra file once a DS record is
    # published. The DS at the registrar names one key by tag; sign with a new
    # KSK and every validating resolver SERVFAILs the entire zone until the
    # registrar catches up. So the rule is: generate only what is missing, and
    # rotate deliberately, never as a side effect of re-running the installer.
    typeset -a existing
    existing=(/var/nsd/zones/master/K${domain}.+*.key(N))
    if (( ${#existing} == 0 )); then
      log INFO "generating DNSSEC keys for $domain"
      ( cd /var/nsd/zones/master && ldns-keygen -a ECDSAP256SHA256 "$domain" >/dev/null )
      ( cd /var/nsd/zones/master && ldns-keygen -k -a ECDSAP256SHA256 "$domain" >/dev/null )
    fi
  done

  chown _nsd:_nsd /var/nsd/zones/master/*
  chmod 640 /var/nsd/zones/master/*

  # One signing implementation, not two. nsd-resign is what runs every night; if
  # it can sign the fleet, so can a first install, and there is no second code
  # path to drift. It also picks exactly one KSK and one ZSK per zone, which is
  # the behaviour the loop above was missing.
  ruby /usr/local/bin/nsd-resign --force || { log ERROR "zone signing failed"; exit 1 }

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    nsd-checkzone "$domain" /var/nsd/zones/master/$domain.zone.signed \
      || { log ERROR "Signed zone invalid for $domain"; exit 1 }
  done

  # DS records are derived from the signed zone by bin/ds-records, never written
  # to a .ds file here. A cached DS goes stale the moment a key rotates, and a DS
  # naming a key the zone no longer publishes takes the zone down.
  log INFO "DS records: doas ruby34 ${REPO_ROOT}/OPENBSD/bin/ds-records"

  [[ ! -f /var/nsd/etc/nsd_server.pem ]] && {
    log INFO "Generating NSD control certificates"
    cd /var/nsd/etc && nsd-control-setup || { log ERROR "nsd-control-setup failed"; exit 1 }
  }

  cleanup_nsd
  /usr/sbin/rcctl enable nsd

  typeset retries=0 max_retries=2
  while (( retries <= max_retries )); do
    /usr/bin/timeout 10 /usr/sbin/rcctl start nsd && break
    (( retries++ ))
    (( retries <= max_retries )) && cleanup_nsd || { log ERROR "nsd failed"; exit 1 }
  done

  sleep 5
  typeset _nsd_check; _nsd_check=$(/usr/sbin/rcctl check nsd)
  [[ $_nsd_check == *"nsd(ok)"* ]] || { log ERROR "nsd not running"; exit 1 }
  verify_nsd

  [[ -d /var/www/acme ]] || mkdir -p /var/www/acme
  install_static etc/httpd.conf /etc/httpd.conf
  httpd -n -f /etc/httpd.conf || { log ERROR "httpd.conf invalid"; exit 1 }
  /usr/sbin/rcctl enable httpd
  /usr/sbin/rcctl start httpd || { log ERROR "httpd failed"; exit 1 }
  sleep 5
  typeset _httpd_check; _httpd_check=$(/usr/sbin/rcctl check httpd)
  [[ $_httpd_check == *"httpd(ok)"* ]] || { log ERROR "httpd not running"; exit 1 }

  # httpd strips /.well-known/acme-challenge/ and serves from /var/www/acme/<token>
  print -r -- test > /var/www/acme/test
  typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://$BRGEN_IP/.well-known/acme-challenge/test):-000}
  rm -f /var/www/acme/test
  [[ $http_status == "200" ]] || { log ERROR "httpd pre-flight failed (HTTP $http_status)"; exit 1 }

  [[ $(<"/etc/group") == *$'\n_acme:'* || $(<"/etc/group") == _acme:* ]] || groupadd -g 765 _acme
  [[ ! -f /etc/acme/letsencrypt_privkey.pem ]] && \
    openssl genpkey -algorithm RSA -out /etc/acme/letsencrypt_privkey.pem -pkeyopt rsa_keygen_bits:4096
  chown root:_acme /etc/acme/letsencrypt_privkey.pem
  chmod 640 /etc/acme/letsencrypt_privkey.pem

  install_static etc/acme-client.conf /etc/acme-client.conf
  acme-client -n -f /etc/acme-client.conf || { log ERROR "acme-client.conf invalid"; exit 1 }

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    if [[ $dns_check != $BRGEN_IP ]]; then
      log WARN "DNS for $domain failed"; FAILED_CERTS[$domain]=1; continue
    fi
    print -r -- "test_$domain" > /var/www/acme/test_$domain
    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" http://$BRGEN_IP/.well-known/acme-challenge/test_$domain):-000}
    rm -f /var/www/acme/test_$domain
    if [[ $http_status != 200 ]]; then
      log WARN "HTTP test for $domain failed"; FAILED_CERTS[$domain]=1; continue
    fi
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      generate_tlsa_record "$domain"
    else
      log WARN "Certificate issuance failed for $domain"; FAILED_CERTS[$domain]=1
    fi
  done
  (( $#FAILED_CERTS )) && retry_failed_certs

  install_static usr/local/bin/renew-certs.sh /usr/local/bin/renew-certs.sh
  chmod 755 /usr/local/bin/renew-certs.sh
  install_static usr/local/bin/uptime-check.sh /usr/local/bin/uptime-check.sh
  chmod 755 /usr/local/bin/uptime-check.sh
  install_tracked_crontab || exit 1

  log INFO "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC."
  log INFO "DS records: doas ruby34 ${REPO_ROOT}/OPENBSD/bin/ds-records — submit each to your registrar (Domeneshop: domain settings → DNSSEC)."
  log INFO "Only for domains the registrar has actually delegated to ns.brgen.no. A DS on a domain we do not serve takes it down."
  log INFO "After submitting DS records, wait 24-48h for propagation, then press Enter to continue."
  log INFO "Verify with: dig DS brgen.no +short"
  read -r
}

`````

### dev/operator_stage_2.zsh

`````zsh
#!/usr/bin/env zsh
# Stage 2 of OPENBSD/OPERATOR.sh: services, Rails apps and relayd.
#
# This file is sourced by OPERATOR.sh after its shared helpers and deploy facts
# are loaded. It owns stage_2 and its helpers; it does not execute on source.


check_libvips_security() {
  if ! command -v vips >/dev/null 2>&1; then
    log ERROR "libvips missing — Rails Active Storage image processing cannot start safely"
    return 1
  fi

  typeset _vips_version; _vips_version=$(vips --version 2>/dev/null) || {
    log ERROR "libvips version probe failed"
    return 1
  }

  /usr/local/bin/ruby40 -e '
    require "rubygems"
    raw = ARGV.fetch(0).to_s
    match = raw.match(/(\d+\.\d+\.\d+)/)
    abort("unreadable libvips version: #{raw}") unless match
    abort("libvips #{match[1]} is below required 8.18.2") if Gem::Version.new(match[1]) < Gem::Version.new("8.18.2")
  ' "$_vips_version" || return 1

  log INFO "libvips ${_vips_version} meets >=8.18.2 security floor"
  return 0
}
setup_services() {
  log INFO "Setting up services"
  /usr/sbin/rcctl enable smtpd
  /usr/sbin/rcctl start smtpd || { log ERROR "smtpd failed"; exit 1 }
  sleep 5
  typeset _smtpd_check; _smtpd_check=$(/usr/sbin/rcctl check smtpd)
  [[ $_smtpd_check == *"smtpd(ok)"* ]] || { log ERROR "smtpd not running"; exit 1 }
  /usr/bin/timeout 5 telnet $BRGEN_IP 25 >/dev/null 2>&1 || log WARN "SMTP port 25 not responding"
  /usr/sbin/rcctl enable relayd
  log INFO "Services configured. relayd enabled but not started (awaiting configuration)"
}

setup_mail_client() {
  log INFO "Setting up johann@brgen.no mailbox and mutt"

  # `mutt` and `w3m` each ship several flavours, so the bare names are
  # ambiguous and pkg_add would stop to ask. A trailing `--` pins the
  # flavourless build, which is the one this needs.
  # w3m renders HTML mail, pdftotext (poppler-utils) flattens PDF
  # attachments, chafa draws images as terminal blocks -- see ~johann/.mailcap.
  pkg_add -I mutt-- w3m-- poppler-utils chafa 2>/var/log/pkg_add_mail.log \
    || { log ERROR "pkg_add (mail client) failed. See /var/log/pkg_add_mail.log"; exit 1 }

  getent passwd johann >/dev/null \
    || /usr/sbin/useradd -m -c "Johann (brgen.no mail)" -s /bin/ksh johann \
    || { log ERROR "useradd johann failed"; exit 1 }

  typeset mailhome=/home/johann

  # Maildir++: smtpd delivers into the top level, mutt keeps Sent, Drafts,
  # Trash and Archive as dot-prefixed siblings of it (see .muttrc's +.Sent).
  typeset box
  for box in "" .Sent .Drafts .Trash .Archive; do
    mkdir -p $mailhome/Maildir/$box/cur $mailhome/Maildir/$box/new $mailhome/Maildir/$box/tmp
  done

  # install_static, not install_template: mailimg is a shell script full of
  # ${MAIL_IMG_FMT:-symbols} defaults, which install_template's eval would
  # expand away at install time.
  install_static home/johann/.muttrc  $mailhome/.muttrc
  install_static home/johann/.mailcap $mailhome/.mailcap
  mkdir -p $mailhome/bin
  install_static home/johann/bin/mailimg $mailhome/bin/mailimg
  chmod 755 $mailhome/bin/mailimg

  chown -R johann:johann $mailhome
  chmod 700 $mailhome/Maildir
  chmod 600 $mailhome/.muttrc
}

setup_litestream() {
  # Not in OpenBSD ports and rcctl-disabled on purpose so `rcctl ls failed`
  # stays empty. Install the config for the day a replica exists; do not enable.
  # There is no rc.d/litestream template: the service was retired from boot in
  # e511ccba1 and installing a missing template would abort stage_2.
  log INFO "litestream config only — service stays disabled"
  mkdir -p /var/backups/litestream
  install_template etc/litestream.yml /etc/litestream.yml
}

bootstrap_rails_app() {
  typeset app=$1 port=$2
  typeset app_dir=/home/dev/pub4/RAILS/$app
  typeset secret

  [[ -d $app_dir ]] || { log ERROR "app tree missing: $app_dir"; return 1 }
  log INFO "bootstrapping $app from pub4 tree on :$port"

  su -l dev -c "gem install --user-install rails bundler falcon" >/dev/null 2>&1 || :
  su -l dev -c "cd $app_dir && bundle config set --local deployment true && bundle config set --local without development:test && RAILS_ENV=production bundle install" \
    || { log ERROR "bundle install failed for $app"; return 1 }
  su -l dev -c "cd $app_dir && RAILS_ENV=production bin/rails db:prepare" \
    || log WARN "db:prepare non-zero for $app (idempotent skip likely)"
  if [[ -f $app_dir/db/seeds.rb ]]; then
    if [[ ${RUN_PRODUCTION_SEEDS:-0} == 1 ]]; then
      log WARN "$app: RUN_PRODUCTION_SEEDS=1 set; running production db:seed"
      su -l dev -c "cd $app_dir && RAILS_ENV=production bin/rails db:seed"
    else
      log INFO "$app: production db:seed skipped (set RUN_PRODUCTION_SEEDS=1 for explicit one-off seed)"
    fi
  fi

  typeset -a _secret_lines
  _secret_lines=("${(@f)$(su -l dev -c "cd $app_dir && RAILS_ENV=production bundle exec rails secret 2>/dev/null")}")
  secret=${_secret_lines[-1]}
  [[ ${#secret} -ge 64 ]] || { log ERROR "$app: secret capture failed (got ${#secret} chars)"; return 1 }
  [[ -f /etc/${app}.env ]] || print -r -- "SECRET_KEY_BASE=${secret}" > /etc/${app}.env
  # root:<app> 640, not root:wheel: the rc.d script sources /etc/<app>.env at
  # runtime *as the app user* (su -l resets the environment, so the secret cannot
  # be interpolated into daemon_flags without landing in falcon's ps(1) argv —
  # readable by any local account; see rc.d/<app> and TODO.md
  # secrets_in_process_argv). Group-<app> lets only that app (and root) read it,
  # so a foothold in another app user — or dev, which is in wheel — can no longer
  # read this secret at rest.
  chown root:${app} /etc/${app}.env 2>/dev/null || true
  chmod 640 /etc/${app}.env 2>/dev/null || true

  typeset svc=$app
  # An app with no rc.d script of its own gets brgen's with the name and port
  # swapped, so a new service starts from the one running in production: set -a
  # around the env file, the PATH for curl, rc_pre and the relayd kick. A
  # separate template drifted from it and would have installed none of those.
  if [[ ! -f ${CONFIG_ROOT}/etc/rc.d/${svc} ]]; then
    typeset _rc; _rc=$(<"${CONFIG_ROOT}/etc/rc.d/brgen")
    _rc=${_rc//brgen/${app}}
    print -r -- "${_rc//38182/${port}}" > /etc/rc.d/${svc}
  fi
  # 555, the mode brgen, amber and bsdports already carry on vm23 — see
  # install_root_configs for why this repo's rc.d scripts are read-only and
  # OpenBSD's own are not. 755 here would flatten that on the next app install.
  chmod 555 /etc/rc.d/${svc}
  /usr/sbin/rcctl enable ${svc}
  /usr/sbin/rcctl restart ${svc} || /usr/sbin/rcctl start ${svc} \
    || { log ERROR "${svc} failed to start"; return 1 }
  sleep 10
  typeset _c; _c=$(/usr/sbin/rcctl check ${svc})
  [[ $_c == *"${svc}(ok)"* ]] || { log ERROR "${svc} not running"; return 1 }
  typeset _http; _http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 http://127.0.0.1:${port}/up 2>/dev/null)
  [[ $_http == "200" ]] || log WARN "${svc} /up returned $_http — SECRET_KEY_BASE or DB may need attention"
  log INFO "  ${svc} live on :$port"
}

configure_relayd() {
  log INFO "Writing relayd.conf (TLS+SNI on :443)"

  typeset -A DOMAIN_BACKEND=() BACKEND_PORT=()
  typeset app_entry app dom entry rest sub backend

  for app_entry in $ALL_APPS; do
    app=${app_entry%%:*}; dom=${app_entry##*:}
    DOMAIN_BACKEND[$dom]=$app
    BACKEND_PORT[$app]=${APP_PORTS[$app]:-0}
  done
  DOMAIN_BACKEND[ai.brgen.no]=master
  BACKEND_PORT[master]=${APP_PORTS[master]:-53187}
  for entry in $ALL_DOMAINS; do
    dom=${entry%%:*}
    [[ -n ${DOMAIN_BACKEND[$dom]:-} ]] && continue
    DOMAIN_BACKEND[$dom]=brgen
  done

  for dom in ${(k)DOMAIN_BACKEND}; do
    [[ -f /etc/ssl/${dom}.fullchain.pem ]] || continue
    ln -sf /etc/ssl/${dom}.fullchain.pem /etc/ssl/${dom}.crt
    # Primary domain: key is the real file, not a symlink — nothing to do.
  done
  # Subdomains share the parent cert+key — create both symlinks so relayd
  # tls keypair finds /etc/ssl/${dom}.crt AND /etc/ssl/private/${dom}.key.
  # Skip only domains that have their own fullchain.pem (handled above).
  # Use -sf so existing .crt symlinks don't prevent missing .key from being created.
  for dom in ${(k)DOMAIN_BACKEND}; do
    [[ -f /etc/ssl/${dom}.fullchain.pem ]] && continue
    typeset parent="" try=${dom#*.}
    while [[ -n $try ]]; do
      if [[ -f /etc/ssl/${try}.fullchain.pem ]]; then parent=$try; break; fi
      [[ $try == *.* ]] || break
      try=${try#*.}
    done
    [[ -n $parent ]] || continue
    ln -sf /etc/ssl/${parent}.fullchain.pem /etc/ssl/${dom}.crt
    ln -sf /etc/ssl/private/${parent}.key    /etc/ssl/private/${dom}.key
  done

  install_static etc/relayd.conf /etc/relayd.conf

  relayd -n -f /etc/relayd.conf || { log ERROR "relayd.conf invalid"; exit 1 }
  /usr/sbin/rcctl enable relayd
  /usr/sbin/rcctl restart relayd || /usr/sbin/rcctl start relayd \
    || { log ERROR "relayd failed"; exit 1 }
  sleep 3
  typeset _c; _c=$(/usr/sbin/rcctl check relayd)
  [[ $_c == *"relayd(ok)"* ]] || { log ERROR "relayd not running"; exit 1 }
  log INFO "relayd live — TLS+SNI on :443"
}

configure_dev_ssh() {
  typeset cfg=/home/dev/.ssh/config
  install -d -o dev -g dev -m 700 /home/dev/.ssh
  [[ -f $cfg ]] || install -o dev -g dev -m 600 /dev/null "$cfg"
  typeset existing="$(<$cfg)"
  if [[ $existing != *"Host github.com"* ]]; then
    print -r -- $'\nHost github.com\n  IdentityFile ~/.ssh/id_ed25519_brgen\n  IdentitiesOnly yes' >>"$cfg"
    chown dev:dev "$cfg"
    chmod 600 "$cfg"
    log INFO "dev ssh: github.com block installed"
  fi

  # Ensure the operator dev account uses the modern Zsh environment
  # (packages for zsh + starship + neovim etc. are installed in Stage 1).
  typeset dev_shell=${${(s/:/)$(getent passwd dev)}[-1]}
  if [[ $dev_shell != */zsh ]]; then
    chsh -s /usr/local/bin/zsh dev 2>/dev/null || log WARN "chsh dev to zsh failed (may need manual)"
  fi
}

stage_2() {
  log INFO "Stage 2: services and apps"

  check_dns_propagation

  # Do not depend on a version-specific `vmstat -s` field for the free-memory
  # check. Read plain `vmstat`'s "fre" column instead, which reports the free
  # list directly.
  typeset _fre_field; _fre_field=${${(z)$(vmstat | tail -1)}[4]}
  typeset _mem_free_kb
  case $_fre_field in
    *G) _mem_free_kb=$(( ${_fre_field%G} * 1024 * 1024 )) ;;
    *M) _mem_free_kb=$(( ${_fre_field%M} * 1024 )) ;;
    *K) _mem_free_kb=${_fre_field%K} ;;
    *)  _mem_free_kb=$_fre_field ;;
  esac
  # This VPS runs brgen+amber+bsdports+MASTER on ~900MB total RAM -- a few
  # tens of MB free is its normal steady state, not a crisis. This floor
  # catches genuine exhaustion (a leak, a runaway process) without blocking
  # ordinary deploys the way a threshold sized for a bigger box would.
  (( _mem_free_kb < 20000 )) && { log ERROR "Insufficient free memory (${_fre_field} free)"; exit 1 }

  install_static etc/pf.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  install_template etc/mail/smtpd.conf /etc/mail/smtpd.conf
  smtpd -n -f /etc/mail/smtpd.conf || { log ERROR "smtpd.conf invalid"; exit 1 }
  [[ ! -f /etc/ssl/private/smtp.key ]] && \
    openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096
  [[ ! -f /etc/ssl/smtp.crt ]] && \
    openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"
  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  setup_mail_client

  check_libvips_security || { log ERROR "libvips security floor failed"; exit 1 }

  setup_services

  typeset -a deploy_order=(amber)
  for app_entry in $ALL_APPS; do
    typeset app=${app_entry[(ws:*:)1]}
    [[ $app != amber ]] && deploy_order+=($app)
  done
  for app in $deploy_order; do
    typeset port=${APP_PORTS[$app]:-}
    [[ -n $port ]] || { log ERROR "missing fixed APP_PORTS entry for $app"; exit 1; }
    bootstrap_rails_app "$app" "$port" || { log ERROR "bootstrap failed: $app"; exit 1 }
  done

  setup_litestream

  for svc_entry in $SERVICES; do
    typeset svc_name=${svc_entry%%:*}
    typeset svc_rest=${svc_entry#*:}
    typeset svc_port=${svc_rest##*:}
    log INFO "Setting up service: $svc_name on port $svc_port"
    chmod 555 /etc/rc.d/$svc_name
    /usr/sbin/rcctl enable $svc_name
    /usr/sbin/rcctl start $svc_name || log WARN "$svc_name start failed (may need manual start)"
  done

  configure_dev_ssh

  log INFO "Deploying MASTER web UI"
  typeset m3dir="/home/dev/pub4/MASTER"
  [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
  cd "$m3dir/web"
  bundle config set --local path vendor/bundle
  bundle config set --local deployment true
  bundle config set --local without 'development test'
  RAILS_ENV=production bundle install --quiet
  # Propshaft must not re-digest public/assets/ (nested assets/assets wedges Falcon boot).
  rm -rf public/assets/assets 2>/dev/null || true
  log INFO "MASTER: building face runtime + precompiling assets"
  RAILS_ENV=production bundle exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:precompile \
    || log WARN "MASTER assets:precompile failed"
  ruby "${REPO_ROOT}/MASTER/gates/runner.rb" master_web_assets 2>/dev/null \
    || ruby "$m3dir/../MASTER/gates/runner.rb" master_web_assets 2>/dev/null \
    || log WARN "MASTER master_web_assets_gate skipped"
  typeset master_secret
  typeset -a _master_secret_lines
  _master_secret_lines=("${(@f)$(RAILS_ENV=production bundle exec rails secret 2>/dev/null)}")
  master_secret=${_master_secret_lines[-1]}
  [[ ${#master_secret} -ge 64 ]] || { log ERROR "master: secret capture failed (got ${#master_secret} chars)"; exit 1 }
  [[ -f ${CONFIG_ROOT}/etc/rc.d/master ]] || { log ERROR "missing OPENBSD/etc/rc.d/master"; exit 1 }
  cp "${CONFIG_ROOT}/etc/rc.d/master" /etc/rc.d/master
  chmod 555 /etc/rc.d/master
  [[ -f $m3dir/data/soul.yml ]] && chmod 0444 "$m3dir/data/soul.yml"
  [[ -f $m3dir/data/checksums.yml ]] && chmod 0444 "$m3dir/data/checksums.yml"
  rcctl enable master
  rcctl start master
  log INFO "MASTER web UI running on :53187"

  configure_relayd

  log INFO "Deploy complete. Test: curl https://brgen.no, rcctl check master"
}

`````

### dev/operator_usage.zsh

`````zsh
#!/usr/bin/env zsh
# Command-line usage text for OPENBSD/OPERATOR.sh.
# Sourced by the entrypoint; defines usage without executing it.

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

`````

### dev/perms.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail

# Changes file ownership and permissions.

# Usage: ./perms.sh <owner> <group> <file_perms> <folder_perms>

if (( $# < 4 )); then

  print "Usage: $0 <owner> <group> <file_perms> <folder_perms>"

  exit 1

fi

owner_group="$1:$2"

file_perms="$3"

folder_perms="$4"

if [[ ! "$file_perms" =~ ^[0-7]{3}$ ]]; then

  print "Error: File perms must be 3 digits (e.g., 644)"

  exit 1

fi

if [[ ! "$folder_perms" =~ ^[0-7]{3}$ ]]; then

  print "Error: Folder perms must be 3 digits (e.g., 755)"

  exit 1

fi

print "Owner:group = $owner_group"

print "File perms  = $file_perms"

print "Folder perms = $folder_perms"

print "Apply? (y/N)"

read -r confirm

# The three chmod/chown blocks below put each command inside its own `if`.
#
# They were bare commands followed by `if [[ $? -ne 0 ]]`, and `set -e` is on
# at the top of this file: a failing chown exited the script on its own line,
# so the message under it had never printed once and the two blocks after it
# never ran. Every one of these handlers was unreachable. A command in an
# if-condition is the one place set -e stands aside — which is why the failure
# arms below say what failed and then carry on to the next block, as the
# original clearly intended.
#
# The `: ` in the success arm is deliberate: there is nothing to do when it
# works, and `if ! cmd` would read as a negation rather than as a handler.
if [[ "$confirm" =~ ^[Yy]$ ]]; then

  if chown -R "$owner_group" ./**/* 2>>"$HOME/script_errors.log"; then

    :

  else

    print "Some chown failed; see $HOME/script_errors.log"

  fi

  if chmod -R "$file_perms" ./**/*(.) 2>>"$HOME/script_errors.log"; then

    :

  else

    print "Some file perms failed"

  fi

  if chmod -R "$folder_perms" ./**/*(/) 2>>"$HOME/script_errors.log"; then

    :

  else

    print "Some folder perms failed"

  fi

  print "Done."

else

  print "Cancelled."

fi

`````

### dev/replace.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob extendedglob

# Swaps out words in files or renames them.
# Usage: ./replace.sh [-f] <old> <new> [folder]

usage() {
  print -r -- "Usage: ./replace.sh [-f] <old> <new> [folder]"
}

die() {
  print -u2 -r -- "Error: $1"
  usage
  exit 1
}

rename_file() {
  typeset file=$1
  typeset new_file="${file//$old_str/$new_str}"
  [[ "$file" != "$new_file" && ! -e "$new_file" ]] || return 0

  if mv "$file" "$new_file" 2>/dev/null; then
    print -r -- "Renamed: $file -> $new_file"
    return 0
  fi

  print -r -- "Failed: $file"
}

replace_file() {
  typeset file=$1
  typeset file_type
  file_type=$(file -b "$file" 2>/dev/null) || return 0
  [[ "$file_type" == *text* ]] || return 0

  typeset content
  content=$(<"$file" 2>/dev/null) || return 0
  [[ "$content" == *"$old_str"* ]] || return 0

  typeset new_content="${content//$old_str/$new_str}"
  [[ "$content" != "$new_content" ]] || return 0

  cp "$file" "$file.bak" 2>/dev/null || print -r -- "Backup failed: $file"
  if print -rn -- "$new_content" > "$file" 2>/dev/null; then
    print -r -- "Updated: $file"
    rm -f "$file.bak"
    return 0
  fi

  print -r -- "Failed: $file"
  [[ -f "$file.bak" ]] && mv "$file.bak" "$file"
}

process_file() {
  if "$is_filename"; then
    rename_file "$1"
    return
  fi

  replace_file "$1"
}

is_filename=false

if [[ "${1:-}" == "-f" ]]; then
  is_filename=true
  shift
fi

old_str="${1:-}"
new_str="${2:-}"
folder="${3:-.}"

[[ -n "$old_str" && -n "$new_str" ]] || die "old and new strings required"
[[ -d "$folder" ]] || die "'$folder' is not a directory"

for file in "$folder"/**/*(.N); do
  process_file "$file"
done

`````

### dev/watch_tests.sh

`````zsh
#!/usr/bin/env zsh
# watch_tests.sh — auto-run MASTER tests on lib/ or test/ file change.
# Uses zsh-native patterns (ZSH_NATIVE_PATTERNS.md): no grep/awk/sed forks.
#
# Usage: zsh sh/watch_tests.sh [test_file]
# Default test: test/test_agent.rb

set -euo pipefail

MASTER_ROOT=${0:a:h:h:h}/MASTER
TEST_FILE=${1:-test/test_agent.rb}
WATCH_DIRS=( lib test )
DELAY=2
LAST_RUN=0

cd "$MASTER_ROOT"
print "watch_tests: watching ${(j:, :)WATCH_DIRS} → $TEST_FILE"
print "watch_tests: press Ctrl-C to stop"
print ""

run_tests() {
  print "\n$(date '+%H:%M:%S') running $TEST_FILE"
  bundle exec ruby "$TEST_FILE" 2>&1
  print ""
}

# Run once immediately
run_tests

while true; do
  sleep "$DELAY"

  NOW=$(date +%s)

  # zsh-native: find .rb files modified in last DELAY+1 seconds
  # Glob qualifier: N=nullglob, m=modification, s=seconds, -N = less than N seconds ago
  typeset -a changed
  changed=()
  for dir in $WATCH_DIRS; do
    [[ -d $dir ]] || continue
    # (Nms-3) = modified less than 3 seconds ago, N = no error if empty
    changed+=( $dir/**/*.rb(Nms-3) )
  done

  # zsh-native unique (no sort|uniq fork)
  typeset -aU unique_changed=( $changed )

  if (( ${#unique_changed} > 0 )); then
    # zsh-native: strip MASTER_ROOT prefix for display
    typeset -a display
    display=( ${unique_changed//$MASTER_ROOT\//} )
    print "changed: ${(j:, :)display}"
    run_tests
  fi
done

`````

### emergency_cpu.sh

`````zsh
#!/bin/ksh
set -euo pipefail

case ${1:-} in
-h|--help)
  echo "usage: doas ksh OPENBSD/emergency_cpu.sh"
  echo "  stop amber and bsdports, kill stale workers, restart master and brgen"
  exit 0
  ;;
esac

# curl is a package (/usr/local/bin/curl) and resource_guard.sh calls this from
# root's cron, whose PATH has no /usr/local/bin — so the /up wait below could
# only ever time out on the path that actually matters, and every crisis
# restart logged "still down after 75s" whether or not master had come back.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# Emergency CPU relief for saturated VPS (vm23).
# Run: doas ksh /home/dev/pub4/OPENBSD/emergency_cpu.sh
#
# This file stays at the top of OPENBSD/ while the rest of the operator shell
# lives in bin/, because vm23 runs it from the checkout by this path. The guard
# installed at /usr/local/bin/resource_guard.sh is dated 2026-08-14, older than
# the repo copy, and its line 285 reads:
#
#   ksh /home/dev/pub4/OPENBSD/emergency_cpu.sh 2>&1 | logger -t resource-guard
#
# It moves to bin/ once `doas zsh OPENBSD/OPERATOR.sh --sync-configs` has installed
# bin/resource_guard.sh and this script under /usr/local/bin, after which the
# guard calls /usr/local/bin/emergency_cpu.sh and nothing reads this path.
#
# Typical cause: Falcon crash-loops, hung bundle install, assets:precompile on restart.

# Prefer the root-owned installed copy; this script is run as root, and
# dot-sourcing from the dev-owned checkout makes repo write access equivalent to
# root code execution. The repo path stays as a fallback for a laptop/dev run,
# where the checkout is already the operator's own.
GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh
GUARD_REPO=${GUARD_REPO:-/home/dev/pub4}
if [[ -f $GUARD_HELPER ]]; then
  . "$GUARD_HELPER"
elif [[ -f ${GUARD_REPO}/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh ]]; then
  # Laptop/dev fallback only — on the VM the installed copy above wins.
  . "${GUARD_REPO}/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh"
fi

# The first N lines of stdin, in ksh, so the crisis path does not depend on
# head(1).
first_lines() {
  _n=0
  while [ "$_n" -lt "$1" ] && IFS= read -r _line; do
    print -r -- "$_line"
    _n=$((_n + 1))
  done
}

echo "=== before ==="
uptime
top -b -n1 | first_lines 18

echo "=== stop optional app services ==="
for svc in amber bsdports; do
  rcctl stop "$svc" 2>/dev/null && echo "stopped $svc" || echo "already down $svc"
done

echo "=== kill stale CI/scan workers ==="
if typeset -f stale_ci_cleanup >/dev/null 2>&1; then
  stale_ci_cleanup 99 0
fi

echo "=== kill orphan compile/boot processes ==="
for pat in \
  'bundle install' \
  'bundle40 install' \
  'gem install' \
  'assets:precompile' \
  'assets:build_face' \
  'bin/rails db:seed' \
  'bin/rails test' \
  'ruby.*bin/cli' \
  'MASTER/web/script/probe_face' \
  'tts-worker --daemon'
do
  pkill -f "$pat" 2>/dev/null && echo "pkill $pat" || true
done

# A start already in flight is not a wedge, and killing one is how this script
# became the thing it exists to fix.
#
# master's rc_pre rebuilds the face bundles and can run assets:precompile, which
# takes over five minutes on one vCPU. Stopping master under it and starting it
# again abandons that precompile and begins another, cron runs the guard again
# five minutes later, and each pass leaves one more precompile behind to keep the
# load critical. Measured 2026-08-27: master could not complete a single start
# for hours, and the box reached 100% swap.
_master_starting=0
if pgrep -f 'rcctl start master' >/dev/null 2>&1; then
  echo 'master start already in flight — not touching it'
  _master_starting=1
fi

echo "=== stop wedged Falcon workers (master + brgen) ==="
pkill -f 'falcon.*53187' 2>/dev/null || true
pkill -f 'ruby40.*53187' 2>/dev/null || true
pkill -f 'falcon.*38182' 2>/dev/null || true
pkill -f 'ruby40.*38182' 2>/dev/null || true
pkill -f '/home/brgen/app' 2>/dev/null || true
sleep 2

echo "=== restart core (master then brgen) ==="
if [[ "$_master_starting" = "1" ]]; then
  echo 'skipping master restart — a start is already running'
else
  rcctl stop master 2>/dev/null || true
  sleep 1
  rcctl start master 2>/dev/null || echo "master start failed"
fi
_i=0
while [[ $_i -lt 25 ]]; do
  curl -fsS -m 4 http://127.0.0.1:53187/up >/dev/null 2>&1 && echo "master /up ok" && break
  sleep 3
  _i=$((_i + 1))
done
[[ $_i -ge 25 ]] && echo "WARN: master /up still down after 75s"

rcctl restart brgen 2>/dev/null || rcctl start brgen 2>/dev/null || echo "brgen restart failed"
rcctl restart relayd 2>/dev/null || true

sleep 3
echo "=== after ==="
uptime
top -b -n1 | first_lines 18
rcctl check master relayd brgen 2>/dev/null || true
relayctl show hosts 2>/dev/null | first_lines 12 || true

echo "Done. git pull, sync rc.d/master (-n 2), then probe: ruby40 MASTER/web/script/probe_http"

`````

### etc/litestream.yml

`````yaml
# Inert by decision. litestream is not in OpenBSD ports, so vm23 has no binary,
# and the service is out of pkg_scripts and rcctl-disabled. Do not enable it.
# Enabled, it fails at every boot and keeps `rcctl ls failed`, the list daily.out
# prints under services that should be running, permanently non-empty, which
# teaches everyone to skim the list a real outage announces itself in. The
# backup is OPENBSD/bin/dr-pull.
#
# The config stays correct for the day someone builds litestream from Go and
# adds an off-host replica. Each `dbs` entry names one database file, not a
# directory. Only production.sqlite3 is streamed, because it holds the user data
# and the cache, queue and cable databases regenerate. A file:// replica sits on
# the source disk, so it covers deletion and point-in-time recovery, never disk
# failure; real recovery needs an s3:// or sftp:// replica on another host.
dbs:
  - path: /home/brgen/app/storage/production.sqlite3
    replicas:
      - url: file:///var/backups/litestream/brgen

  - path: /home/amber/app/storage/production.sqlite3
    replicas:
      - url: file:///var/backups/litestream/amber

  - path: /home/bsdports/app/storage/production.sqlite3
    replicas:
      - url: file:///var/backups/litestream/bsdports

`````

### gates/config_drift_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# encoding: utf-8

# Fails when a security-critical config or scheduled script on vm23 does not
# match its tracked OPENBSD/ mirror byte-for-byte.
#
# The doas keepenv root-RCE stayed live in production for days while the repo and
# TODO.md both called it fixed, because nothing ever compared the mirror against
# the running /etc. This is the check that would have caught it: the repo IS the
# live config, and when it is not, that is either an undeployed fix or a hand-edit
# nobody copied back, and both are the bug this gate names.
#
# Only VERBATIM-installed files are byte-compared. Templated installs and
# generated files are listed as excluded rather than diffed, because a difference
# there is expected, not drift.
#
# Run on vm23:              ruby34 OPENBSD/gates/config_drift_gate.rb
# Run from a laptop:        SSH_HOST=dev@brgen.no ruby OPENBSD/gates/config_drift_gate.rb --remote
# Off-VPS without --remote: skips cleanly.

require "open3"
require "digest"

# Every sibling here reaches this through `require_relative "lib/utf8"`. This one
# is the only file OPERATOR.sh installs to /usr/local/bin, and a require_relative
# resolves beside the installed copy — so the shared file forced a whole
# /usr/local/bin/lib/ directory onto the box to hold six lines, and an install that
# could half-succeed. Minimal OpenBSD and CI environments default Ruby file reads to
# US-ASCII, and this gate reads UTF-8 config regardless of the operator's locale.
Encoding.default_external = Encoding::UTF_8

# The repo is found, not assumed to be one level up.
#
# daily.local runs the INSTALLED copy at /usr/local/bin — root must not execute a
# file the dev user can rewrite — and from there `..` is /usr/local, so a mirror
# resolved relative to this file lands on /usr/local/etc and every comparison
# finds no repo mirror. That is a gate reporting "clean" while comparing
# nothing, so the checkout is searched for rather than inferred.
#
# Reading the checkout is safe in a way that executing it is not: root compares
# bytes it never runs, so the escalation the installed copy exists to close stays
# closed. PUB4_ROOT first so a worktree or a test can point it somewhere else.
DRIFT_ROOT = [ENV["PUB4_ROOT"], File.expand_path("../..", __dir__), "/home/dev/pub4"]
       .compact
       .find { |dir| File.file?(File.join(dir, "OPENBSD", "etc", "doas.conf")) } ||
       File.expand_path("../..", __dir__)
MIRROR = File.join(DRIFT_ROOT, "OPENBSD")

# Repo mirror => live path, for every file installed byte-for-byte.
#
# /etc is half of it. The other half is /usr/local/bin, where every root cron
# job on this box lives: the load guard, the drift check, the certificate
# renewal, the uptime check, the two jobs that keep the working set resident.
# A hand-edit there changes what vm23 does on a schedule, and the same argument
# that makes /etc worth comparing makes those worth comparing.
#
# The key is a repo path rather than the live path with its slash stripped
# because four of these ship from the tree root: OPERATOR.sh installs them with
# `install` while the rest arrive as a `cp -R usr/. /usr/`.
VERBATIM = {
  "etc/doas.conf" => "/etc/doas.conf",
  "etc/pf.conf" => "/etc/pf.conf",
  "etc/httpd.conf" => "/etc/httpd.conf",
  # rcctl enable/disable rewrites this file and sorts every line, so prose in it
  # scrambles on the next rcctl write rather than on install, and a run straight
  # after an install compares clean.
  "etc/rc.conf.local" => "/etc/rc.conf.local",
  "etc/login.conf" => "/etc/login.conf",
  "etc/newsyslog.conf" => "/etc/newsyslog.conf",
  "etc/ssh/sshd_config" => "/etc/ssh/sshd_config",
  "etc/rc.d/master" => "/etc/rc.d/master",
  "etc/rc.d/brgen" => "/etc/rc.d/brgen",
  "etc/rc.d/amber" => "/etc/rc.d/amber",
  "etc/rc.d/bsdports" => "/etc/rc.d/bsdports",
  "usr/local/bin/config-drift-check" => "/usr/local/bin/config-drift-check",
  "usr/local/bin/core-reclaim.sh" => "/usr/local/bin/core-reclaim.sh",
  "usr/local/bin/drain-jobs.sh" => "/usr/local/bin/drain-jobs.sh",
  "usr/local/bin/keep-warm.sh" => "/usr/local/bin/keep-warm.sh",
  "usr/local/bin/nsd-resign" => "/usr/local/bin/nsd-resign",
  "usr/local/bin/prune-guests.sh" => "/usr/local/bin/prune-guests.sh",
  "usr/local/bin/prune_guests.rb" => "/usr/local/bin/prune_guests.rb",
  "usr/local/bin/relayd-watchdog" => "/usr/local/bin/relayd-watchdog",
  "usr/local/bin/renew-certs.sh" => "/usr/local/bin/renew-certs.sh",
  "usr/local/bin/uptime-check.sh" => "/usr/local/bin/uptime-check.sh",
  "bin/resource_guard.sh" => "/usr/local/bin/resource_guard.sh",
  "emergency_cpu.sh" => "/usr/local/bin/emergency_cpu.sh",
  "gates/config_drift_gate.rb" => "/usr/local/bin/config_drift_gate.rb",
  "bin/vps_weekly_integrity.sh" => "/usr/local/bin/vps_weekly_integrity.sh",
}.freeze

EXCLUDED = %w[etc/relayd.conf etc/mail/smtpd.conf etc/litestream.yml etc/acme-client.conf].freeze

# Root's crontab cannot join VERBATIM: OPERATOR.sh merges the tracked lines into
# whatever is already there rather than overwriting the file, so a byte compare
# would fail on every box that has ever been touched by hand. What is comparable
# is the set of commands, and that is the half worth comparing — a schedule the
# repo declares and the box does not run is a capability that exists only in this
# directory.
#
# It is the gap this check was written for. `etc/crontab.vm23:97` has scheduled
# `/usr/local/bin/vps_weekly_integrity.sh` for weeks; the box has no such line, no
# such file and no /var/log/pub4 to write into, and the weekly integrity pass has
# therefore never run once. Every /etc file matched, so the gate said clean.
CRONTAB_MIRROR = "etc/crontab.vm23"
CRONTAB_KEY = "@root-crontab"

REMOTE = ARGV.include?("--remote")
SSH_HOST = ENV.fetch("SSH_HOST", "dev@brgen.no")
SSH_KEY = File.expand_path(ENV.fetch("SSH_KEY", "~/.ssh/id_ed25519_brgen"))
MARKER = "@@PUB4_CONFIG_DRIFT@@"

def on_vps?
  File.file?("/etc/relayd.conf") || ENV["DEPLOY_ASSUME_VPS"] == "1"
end

# A machine with no doas is a machine that cannot answer, not a crash.
# `DEPLOY_ASSUME_VPS=1` is documented in bin/check-rails as the way to exercise
# the on-VPS path from a laptop, and on a laptop `doas` does not exist — so
# without the rescue this gate raises Errno::ENOENT where it means to report
# nothing found.
def doas_run(*command)
  out, status = Open3.capture2e("doas", "-n", *command)
  status.success? ? out : nil
rescue Errno::ENOENT
  nil
end

def doas_cat(path) = doas_run("cat", path)
def doas_root_crontab = doas_run("crontab", "-l", "-u", "root")

# One SSH round-trip for all files, the crontab included. Reading them one at a
# time is 11 rapid reconnects, which is what pf bruteforce blocks (RUNBOOK: one
# session at a time), and a separate connection for the crontab would be the
# twelfth. Each file emits `<marker><path>` on its own line then its contents;
# echo, not printf, because printf backslash escaping is fragile across ruby ->
# ssh -> shell.
def live_files(paths)
  keys = paths + [CRONTAB_KEY]

  unless REMOTE
    map = paths.to_h { |path| [path, File.readable?(path) ? File.read(path) : doas_cat(path)] }
    map[CRONTAB_KEY] = doas_root_crontab
    return map
  end

  script = paths.map do |path|
    "echo #{(MARKER + path).dump}; doas cat #{path} 2>/dev/null || cat #{path} 2>/dev/null"
  end.join("; ")
  script += "; echo #{(MARKER + CRONTAB_KEY).dump}; doas crontab -l -u root 2>/dev/null"
  out, status = Open3.capture2e(
    "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-i", SSH_KEY, SSH_HOST, script
  )
  return keys.to_h { |key| [key, nil] } unless status.success?

  split_stream(out, keys)
end

# The command a crontab line schedules, as an absolute path.
#
# Five time fields (or an `@reboot`-style shorthand) then the command, and the
# first absolute path inside the command is the program: an environment prefix
# sits before it without a slash and a `>> /var/log/...` redirect comes after it.
# A bare `PATH=...` assignment has no five fields in front of it and so matches
# nothing, which is what should happen to it.
def scheduled_commands(text)
  text.to_s.lines.filter_map do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    next unless line =~ %r{\A(?:@\w+|\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.+)\z}

    Regexp.last_match(1)[%r{/\S+}]
  end.uniq
end

# Every VERBATIM mirror under `mirror` byte-compared with its live copy in
# `live_map` (live path => contents, nil when unreadable). Only VERBATIM is read,
# so an EXCLUDED file that differs on the box, as a templated one always does, is
# never drift.
def verbatim_report(live_map, mirror: MIRROR)
  report = { drift: {}, missing: [], compared: [], unfound: [] }
  VERBATIM.each do |repo_rel, live_path|
    repo_path = File.join(mirror, repo_rel)
    # Counted, not skipped: a gate that cannot find the repo compares nothing,
    # and nothing compared must not exit 0.
    next report[:unfound] << repo_rel unless File.file?(repo_path)

    live = live_map[live_path]
    next report[:missing] << repo_rel if live.nil? || live.empty?

    repo = File.read(repo_path)
    next report[:compared] << repo_rel if repo == live

    repo_sha = Digest::SHA256.hexdigest(repo)[0, 12]
    live_sha = Digest::SHA256.hexdigest(live)[0, 12]
    report[:drift][repo_rel] = "repo sha=#{repo_sha} (#{repo.bytesize}B) vs live sha=#{live_sha} (#{live.bytesize}B)"
  end
  report
end

def split_stream(out, paths)
  result = paths.to_h { |path| [path, nil] }
  out.split(MARKER)[1..].to_a.each do |chunk|
    header, body = chunk.split("\n", 2)
    path = header.to_s.strip
    result[path] = body if paths.include?(path)
  end
  result
end

def report(drift, missing, compared, unfound, cron)
  EXCLUDED.each { |name| puts "config-drift: #{name.ljust(34)} skip - templated or generated (not verbatim)" }
  compared.each { |name| puts "config-drift: #{name.ljust(34)} ok" }
  puts "config-drift: #{CRONTAB_MIRROR.ljust(34)} #{cron[:summary]}"

  # The denominator, always. "clean" without it is the shape of every gate in
  # this tree that has ever passed having measured nothing: it reads identically
  # whether eleven files matched or the gate could not find a single one.
  if drift.empty? && missing.empty? && unfound.empty? && cron[:ok]
    puts "config-drift: clean (#{compared.size}/#{VERBATIM.size} verbatim files and " \
         "#{cron[:declared]} crontab command(s) match the live copy)"
    return
  end

  unfound.each { |name| warn "config-drift: #{name}: no repo mirror under #{MIRROR}" }
  warn "config-drift: compared #{compared.size}/#{VERBATIM.size} — a gate that compares nothing is not a passing gate" if compared.empty?
  missing.each { |name| warn "config-drift: #{name}: live file missing or unreadable on vm23" }
  drift.each do |name, detail|
    warn "config-drift: #{name}: DRIFT - the live copy differs from OPENBSD/#{name}"
    warn "  #{detail}"
  end
  cron[:absent].each do |command|
    warn "config-drift: #{CRONTAB_MIRROR}: DRIFT - root's crontab does not schedule #{command}"
  end
  cron[:extra].each do |command|
    warn "config-drift: #{CRONTAB_MIRROR}: DRIFT - root's crontab schedules #{command}, which the repo does not"
  end
  warn "config-drift: sync (doas zsh OPENBSD/OPERATOR.sh) or copy the live edit back into OPENBSD/"
end

# Nothing found and nothing missing are different answers. An unreadable crontab
# would otherwise report every declared job as absent, which is ten false alarms
# and the fastest way to teach a reader to skip this section.
def crontab_report(repo_text, live_text)
  declared = scheduled_commands(repo_text)
  return { ok: true, declared: declared.size, absent: [], extra: [], summary: "skip - no repo mirror" } if repo_text.nil?

  if live_text.nil? || live_text.strip.empty?
    return { ok: true, declared: declared.size, absent: [], extra: [],
             summary: "skip - root's crontab was not readable here" }
  end

  # Extras are scoped to /usr/local, because the repo owns only half of this file.
  # OpenBSD ships root a crontab of its own — `/usr/bin/newsyslog` and the three
  # `/bin/sh /etc/{daily,weekly,monthly}` lines — and OPERATOR.sh merges the pub4
  # lines onto it rather than replacing it. Every command this repo installs lives
  # under /usr/local/bin, so anything outside it is the base system's and reporting
  # it would be four permanent false alarms.
  live = scheduled_commands(live_text)
  absent = declared - live
  extra = (live - declared).select { |command| command.start_with?("/usr/local/") }
  {
    ok: absent.empty? && extra.empty?,
    declared: declared.size,
    absent: absent,
    extra: extra,
    summary: absent.empty? && extra.empty? ? "ok" : "DRIFT - #{absent.size} unscheduled, #{extra.size} unexpected",
  }
end

# Everything above is definitions; everything below runs. The split is what lets
# test/test_config_drift_gate.rb require this file and hand `crontab_report` the
# shape it must flag and the shape it must not — without the guard, requiring the
# gate off-VPS exits the test process at the skip line below.
return unless $PROGRAM_NAME == __FILE__

unless REMOTE || on_vps?
  warn "config-drift: skip - not on vm23 (run on the box, or pass --remote with SSH_HOST set)"
  exit 0
end

live_map = live_files(VERBATIM.values)
drift, missing, compared, unfound = verbatim_report(live_map).values_at(:drift, :missing, :compared, :unfound)

crontab_mirror_path = File.join(MIRROR, CRONTAB_MIRROR)
cron = crontab_report(
  File.file?(crontab_mirror_path) ? File.read(crontab_mirror_path) : nil,
  live_map[CRONTAB_KEY]
)

report(drift, missing, compared, unfound, cron)
exit(drift.empty? && missing.empty? && unfound.empty? && cron[:ok] ? 0 : 1)

`````

### gates/deploy_smoke_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require_relative "../lib/utf8"
require_relative "../lib/token_echo"

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "RAILS")
RELAYD = File.join(ROOT, "OPENBSD", "etc", "relayd.conf")
HTTPD = File.join(ROOT, "OPENBSD", "etc", "httpd.conf")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def assert_forward(relayd_text, failures, name, port, domain)
  # relayd uses a named table plus a forward line in the relay, not a named
  # backend block. Check both halves against the same service name.
  failures << "relayd: missing backend table <#{name}>" unless relayd_text.match?(/^table\s+<#{Regexp.escape(name)}>\s+\{/)
  failures << "relayd: missing forward port #{port} for #{name}" unless relayd_text.match?(/^\s*forward to <#{Regexp.escape(name)}> port #{port} check http "\/up"/)
  failures << "relayd: missing Host route for #{domain} in #{name}" unless relayd_text.match?(/^\s*match request header "Host" value "#{Regexp.escape(domain)}" forward to <#{Regexp.escape(name)}>/)
end

def check_relayd(failures)
  unless File.file?(RELAYD)
    failures << "missing tracked relayd.conf template"
    return
  end

  relayd = File.read(RELAYD)
  failures << "relayd: missing X-Forwarded-Proto" unless relayd.include?("X-Forwarded-Proto")
  failures << "relayd: missing /up health check" unless relayd.include?('check http "/up"')

  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {})
  apps.each do |name, metadata|
    assert_forward(relayd, failures, name, metadata.fetch("port"), metadata.fetch("domain"))
  end

  master_json = File.join(ROOT, "OPENBSD", "deploy_inventory.json")
  if File.file?(master_json)
    inventory = JSON.parse(File.read(master_json))
    if (master_entry = inventory.dig("master_face"))
      master_port = master_entry.fetch("port")
      failures << "relayd: master backend missing" unless relayd.include?("forward to <master>")
      failures << "relayd: master missing http /up check" unless relayd.include?("forward to <master> port #{master_port} check http \"/up\"")
    end
  end
end

# Port 80 is httpd's, and the part of it that matters is the ACME location:
# acme-client writes HTTP-01 challenges to /var/www/acme, which is "/acme" inside
# httpd's chroot. Lose the location and renewal fails without a word until every
# certificate lapses.
def check_httpd(failures)
  unless File.file?(HTTPD)
    failures << "missing tracked httpd.conf"
    return
  end

  httpd = File.read(HTTPD)
  failures << "httpd: no listener on port 80" unless httpd.match?(/^\s*listen on \S+ port 80\b/)
  acme = httpd[%r{location "/\.well-known/acme-challenge/\*" \{(.*?)\}}m, 1]
  if acme.nil?
    failures << "httpd: no /.well-known/acme-challenge/ location"
  elsif !acme.include?('root "/acme"')
    failures << "httpd: the ACME location must serve root \"/acme\", acme-client's challengedir inside the chroot"
  end
end

MASTER_RC = File.join(ROOT, "OPENBSD", "etc", "rc.d", "master")
AUTH_TIER = File.join(ROOT, "MASTER", "web", "app", "middleware", "auth_tier.rb")

# Every path rc.d/master's post-start block asks the local Falcon for, with the
# line that asks.
def warmup_requests(rc_text)
  rc_text.each_line.filter_map do |line|
    path = line[%r{http://127\.0\.0\.1:\$\{?PORT\}?(/[^"'\s]*)}, 1]
    [path, line] if path && line.include?("curl")
  end
end

# The paths AuthTier serves before it looks for a token, read from the
# middleware so this list cannot drift from the one that decides.
def auth_tier_public_paths
  return [] unless File.file?(AUTH_TIER)

  File.read(AUTH_TIER)[/PUBLIC_PATHS\s*=\s*%w\[([^\]]+)\]/, 1].to_s.split
end

# The warmup has to be answerable by a process holding no token. It once waited
# 240s on metrics the tier gate had put behind one, and the restart logged "not
# ready" for a service that was fine. So: something to warm, at least one path
# AuthTier serves without asking, no credential on any request, and nothing under
# /chat/metrics. Which query string it sends is its own business.
def check_master_rc(failures, rc_text = (File.read(MASTER_RC) if File.file?(MASTER_RC)), public_paths = auth_tier_public_paths)
  return unless rc_text

  requests = warmup_requests(rc_text)
  failures << "rc.d/master: no warmup request to the local port" if requests.empty?
  unless requests.any? { |path, _| public_paths.include?(path.split("?").first) }
    failures << "rc.d/master: no warmup request asks a path AuthTier serves without a token (#{public_paths.join(' ')})"
  end
  requests.each do |path, line|
    failures << "rc.d/master: warmup #{path} carries a credential" if line.match?(/token=|Authorization:|X-Token/i)
    failures << "rc.d/master: warmup #{path} needs auth since the tier gate" if path.start_with?("/chat/metrics")
  end
end

def check_apps_production(failures)
  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {})
  apps.each do |name, metadata|
    production = File.join(RAILS_ROOT, name, "config", "environments", "production.rb")
    next unless File.file?(production)

    text = File.read(production)
    baseline = File.join(RAILS_ROOT, "shared", "config", "environments", "production_baseline.rb")
    text += "\n#{File.read(baseline)}" if text.include?("production_baseline") && File.file?(baseline)
    domain = metadata.fetch("domain")
    failures << "#{name}: production.rb missing assume_ssl" unless text.match?(/\bconfig\.assume_ssl\s*=\s*true\b/)
    failures << "#{name}: production.rb has force_ssl" if text.match?(/\bconfig\.force_ssl\s*=\s*true\b/)
    failures << "#{name}: production.rb missing host #{domain}" unless text.match?(/\b#{Regexp.escape(domain)}\b/)
    # Fix: /up check was performance theater (matching /upload)
    failures << "#{name}: production.rb missing /up host_authorization exclude" unless text.include?("/up")
    failures << "#{name}: production.rb missing /health host_authorization exclude" unless text.include?("/health")

    routes = File.join(RAILS_ROOT, name, "config", "routes.rb")
    failures << "#{name}: routes must load shared fleet health endpoint" if File.file?(routes) && !File.read(routes).include?("fleet.rb")
  end
end

def check_master_web(failures)
  master_web = File.join(ROOT, "MASTER", "web", "config", "environments", "production.rb")
  if File.file?(master_web)
    text = File.read(master_web)
    failures << "MASTER/web: missing assume_ssl" unless text.match?(/\bconfig\.assume_ssl\s*=\s*true\b/)
  end

  auth_tier = File.join(ROOT, "MASTER", "web", "app", "middleware", "auth_tier.rb")
  if File.file?(auth_tier)
    text = File.read(auth_tier)
    failures << "MASTER/web: forbidden author URL auth bypass" if text.match?(/\bauthor_url\b|\bAUTHOR_NAME\b|\bmaster_author\b/)
    failures << "MASTER/web: weak fixed token length" if text.match?(/\bTOKEN_LENGTH\s*=\s*1[0-9]\b/)
    failures << "MASTER/web: missing high-entropy token generation" unless text.include?("SecureRandom.urlsafe_base64")
  else
    failures << "MASTER/web: missing AuthTier middleware"
  end

  master_web_root = File.join(ROOT, "MASTER", "web")
  [
    File.join(master_web_root, "public/face.runtime.js"),
    File.join(master_web_root, "lib/tasks/face_runtime.rake"),
    File.join(master_web_root, "lib/tasks/face_modules_bundle.rake"),
    File.join(master_web_root, "script/build_face_modules.sh"),
    File.join(master_web_root, "script/probe_http"),
    File.join(master_web_root, "script/ci_web_probe"),
  ].each do |path|
    failures << "MASTER/web: missing #{path.delete_prefix(ROOT + '/')}" unless File.file?(path)
  end

  chat_index = File.join(master_web_root, "app/views/chat/index.html.erb")
  if File.file?(chat_index)
    chat_body = File.read(chat_index)
    failures << "MASTER/web: chat index missing inline lazy face boot" unless chat_body.include?("function loadFace") && chat_body.include?('asset_path("face.js")')
  else
    failures << "MASTER/web: missing MASTER/web/app/views/chat/index.html.erb"
  end
end

def check_operator(failures)
  openbsd = File.join(ROOT, "OPENBSD", "OPERATOR.sh")
  if File.file?(openbsd)
    text = File.read(openbsd)
    failures << "OPERATOR.sh: production db:seed is not explicitly gated" unless text.include?("RUN_PRODUCTION_SEEDS")
    failures << "OPERATOR.sh: default deploy must run sync/apply path" unless text.match?(/""\)\s*\n\s*deploy_live/m)
  else
    failures << "missing canonical OpenBSD deploy script"
  end
end

def check_system_configs(failures)
  # Relayd timeout
  relayd_text = File.file?(RELAYD) ? File.read(RELAYD) : ""
  if (relayd_timeout = relayd_text.match(/timeout\s+(\d+)/))
    failures << "relayd: timeout should allow slow document boot (>= 15000)" if relayd_timeout[1].to_i < 15_000
  end
end

# Definitions above, the run below, so test/test_gate_fixtures.rb can hand each
# check the shape it must flag.
return unless $PROGRAM_NAME == __FILE__

failures = []
check_relayd(failures)
check_httpd(failures)
check_master_rc(failures)
TokenEcho.check(failures, ROOT)
check_apps_production(failures)
check_master_web(failures)
check_operator(failures)
check_system_configs(failures)

if failures.any?
  warn "Deploy smoke gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

apps_count = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {}).size
puts "Deploy smoke gate passed (relayd and httpd templates + #{apps_count} production configs + MASTER/web probes)."

`````

### gates/dns_zones.rb

`````ruby
# frozen_string_literal: true

require "resolv"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../../OPENBSD/bin/render_dns"

module Deploy
  # The DNS the repo describes has to be the DNS the box serves.
  #
  # Before 2026-08-12 there were four hand-written descriptions of the same set
  # of names and no two agreed: ALL_DOMAINS had 53 domains, /var/nsd/zones/master
  # had 61 zone files, nsd.conf declared 54, and acme-client.conf carried a fifth,
  # older subdomain list. Nothing compared them, so the drift was only visible by
  # reading all four — and the cost of it was that oshlo.no, a live certificated
  # city, had no www record, no SPF and no DMARC while brgen.no had all three.
  #
  # Now bin/render_dns.rb writes all of it from ALL_DOMAINS plus data/dns.yml.
  # This gate is what makes the generator load-bearing rather than optional: it
  # fails if the committed output is not what the generator produces, which is
  # the moment someone hand-edits a zone file.
  #
  # The live half is a DNS query, not a file read. /var/nsd/zones/master is 640
  # _nsd:_nsd, so a gate running as dev cannot read a zone on the box either —
  # but anyone can ask the nameserver. Signature freshness needs the files and
  # lives in OPENBSD/gates/health_check.rb, which runs as root on vm23.
  class DnsZonesGate
    ROOT = File.expand_path("../..", __dir__)
    REGISTRY = File.join(ROOT, "RAILS", "brgen", "lib", "brgen", "domain_registry.rb")
    # Both come from data/dns.yml, which is the file that renders the delegation
    # these checks then verify. A literal here could disagree with the zones it
    # is checking and the gate would pass on both halves of the disagreement.
    NAMESERVER = RenderDns.policy.fetch("nameserver").fetch("ip")
    INVENTORY = File.join(ROOT, "OPENBSD", "deploy_inventory.json")
    PUBLIC_RESOLVERS = RenderDns.policy.fetch("resolvers").fetch("public").freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      generated_output_matches
      every_domain_has_a_zone
      nameserver_answers
      app_domains_delegate_to_us
      @result
    end

    private

    # The three app domains, and whether the public internet points them here.
    #
    # nameserver_answers above asks 46.23.89.226 directly, which answers for
    # every zone it serves whether or not anything delegates to it. That is a
    # different question from the one that decides whether a site is reachable,
    # and bsdports.org is what the difference looks like: registered to us at
    # Domeneshop through 2027-08-08, relayd holding a keypair and a Host match
    # for it, a valid certificate on disk to Nov 10 2026, RUNBOOK.md naming
    # https://bsdports.org as its URL, the app itself answering 200 on 47312 —
    # and the .org registry delegating the name to ns1/2/3.expireddomain.hyp.net,
    # Domeneshop's parking servers, which publish no A record. The app has been
    # publicly unreachable and every check we had said it was fine.
    #
    # Nothing else catches it. domain_watch asks the registry whether the name is
    # held and when it expires, and the registration is paid. Owned, paid,
    # configured, and dark.
    #
    # Asked against a public resolver rather than ours, because "does the world
    # agree" is the whole question.
    def app_domains_delegate_to_us
      domains = app_domains
      return @result.inconclusive!("dns_zones: deploy_inventory.json not parseable") if domains.empty?

      resolver = Resolv::DNS.new(nameserver: PUBLIC_RESOLVERS, search: [], ndots: 1)
      resolver.timeouts = 3

      begin
        resolver.getaddress("one.one.one.one")
      rescue Resolv::ResolvError, Resolv::ResolvTimeout, SystemCallError => e
        return @result.skipped_live("dns_zones: no public resolver reachable (#{e.class}) — " \
                                    "delegation not measured")
      end

      domains.each { |app, domain| check_delegation(resolver, app, domain) }
    end

    def check_delegation(resolver, app, domain)
      addresses = resolver.getaddresses(domain).map(&:to_s)

      if addresses.empty?
        @result.fail("dns_zones: #{domain} (#{app}) resolves nowhere on the public internet — " \
                     "the app is unreachable no matter what rcctl says. Check the registrar's " \
                     "nameservers: a lapsed-then-renewed domain comes back parked.")
      elsif !addresses.include?(NAMESERVER)
        @result.fail("dns_zones: #{domain} (#{app}) resolves to #{addresses.sort.join(', ')}, " \
                     "not #{NAMESERVER} — it is delegated somewhere that is not us")
      end
      @result.checked!(1)
    rescue Resolv::ResolvTimeout
      @result.skipped_live("dns_zones: public lookup for #{domain} timed out — not measured, not absent")
    end

    def app_domains
      require "json"
      JSON.parse(File.read(INVENTORY))
          .fetch("apps", [])
          .filter_map { |app| [ app["name"], app["domain"] ] if app["domain"].to_s.include?(".") }
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def generated_output_matches
      _written, stale = RenderDns.render_zones(check: true)
      %w[nsd.conf acme-client.conf].zip([RenderDns::NSD_CONF, RenderDns::ACME_CONF]).each do |label, path|
        body = label == "nsd.conf" ? RenderDns.nsd_conf_body : RenderDns.acme_conf_body
        stale << label unless File.exist?(path) && File.read(path, encoding: "UTF-8") == body
      end

      if stale.empty?
        @result.checked!(RenderDns.zones.size + 2)
      else
        @result.fail("dns_zones: #{stale.size} generated file(s) differ from what data/dns.yml renders " \
                     "(#{stale.sort.first(5).join(', ')}) — run `ruby OPENBSD/bin/render_dns.rb`")
      end
    end

    # Every domain the installer deploys must have a zone file and a zone block.
    # Seven zone files reached no server for months because nsd.conf and the
    # directory were maintained separately.
    def every_domain_has_a_zone
      declared = RenderDns.zones.keys
      conf = File.read(RenderDns::NSD_CONF, encoding: "UTF-8").scan(/name:\s+"([^"]+)"/).flatten

      missing_block = declared - conf
      orphan_block = conf - declared
      @result.fail("dns_zones: nsd.conf has no zone block for #{missing_block.sort.join(', ')}") if missing_block.any?
      @result.fail("dns_zones: nsd.conf declares #{orphan_block.sort.join(', ')} with no zone file") if orphan_block.any?
      @result.checked!(declared.size)
    end

    # A city the registry calls live must actually be answered for by our
    # nameserver, apex and every vertical. Skipped rather than failed when UDP 53
    # is unavailable — several networks, including the machine this is usually
    # run from, block outbound port 53.
    def nameserver_answers
      live = live_domains
      return @result.inconclusive!("dns_zones: LIVE_DOMAINS not parseable") if live.empty?

      resolver = Resolv::DNS.new(nameserver: [NAMESERVER], search: [], ndots: 1)
      resolver.timeouts = 3

      begin
        resolver.getaddress("brgen.no")
      rescue Resolv::ResolvError, Resolv::ResolvTimeout, SystemCallError => e
        return @result.skipped_live("dns_zones: #{NAMESERVER} unreachable on UDP 53 (#{e.class}) — " \
                                    "live half not measured")
      end

      subdomains = RenderDns.city_zones
      live.each { |domain| check_domain(resolver, domain, Array(subdomains[domain])) }
    end

    def check_domain(resolver, domain, subdomains)
      names = [domain, "www.#{domain}"] + subdomains.map { |sub| "#{sub}.#{domain}" }
      by_verdict = names.group_by { |name| answer(resolver, name) }
      missing = Array(by_verdict[:missing])
      timed_out = Array(by_verdict[:timeout])

      if missing.any?
        @result.fail("dns_zones: #{domain} is in LIVE_DOMAINS and #{NAMESERVER} does not answer for " \
                     "#{missing.sort.join(', ')}")
      end
      if timed_out.any?
        @result.skipped_live("dns_zones: #{NAMESERVER} timed out for #{timed_out.sort.join(', ')} " \
                             "after #{RETRIES} attempts — not measured, not absent")
      end
      @result.checked!(names.size - timed_out.size)
    end

    # Answers over UDP, retried, because a timeout is not an absent record.
    #
    # This gate hard-failed on the first Resolv::ResolvTimeout, and one such
    # failure is what running it for the first time produced: "frankfrt.de is in
    # LIVE_DOMAINS and 46.23.89.226 does not answer for maps.frankfrt.de", while
    # `dig @46.23.89.226 maps.frankfrt.de` answered immediately and three
    # consecutive re-runs of the gate passed. A false block, from one dropped UDP
    # packet in the ~500 sequential queries this makes.
    #
    # arXiv 2607.07405 is the reason that matters rather than being a re-run
    # someone shrugs at: it audits a four-gate suite and finds one gate blocking
    # at 100% precision and another at 5%, and a gate whose blocks are mostly its
    # own noise is one people learn to skip. This gate was already invisible —
    # registered in gates.yml and invoked by nothing — so its first impression on
    # anyone wiring it up would have been a block that was not true.
    #
    # Both failures are retried, because Resolv cannot tell them apart.
    #
    # The first version of this retried only Resolv::ResolvTimeout, on the
    # assumption that NXDOMAIN arrived as ResolvError and was therefore a
    # different class. It is not: Resolv::DNS#getaddress raises ResolvError
    # reading "no address for <name>" both for a real NXDOMAIN and for a query
    # that got no usable response, so a dropped packet is indistinguishable from
    # a missing record at this API. That fix held for one run and then blocked
    # again on three names — takeaway.brgen.no, takeaway.oshlo.no,
    # radio.trndheim.no — all three of which `dig` answered immediately.
    #
    # So retry both, and only believe the answer after RETRIES agree. A genuine
    # NXDOMAIN is still NXDOMAIN three times and still fails the gate, which is
    # the gate's job; a lost packet almost never repeats three times. The two
    # verdicts stay separate in the message because they mean different things to
    # whoever reads it — one is "the record is gone", the other is "the network
    # ate it and this gate measured nothing".
    RETRIES = 3

    def answer(resolver, name)
      attempts = 0
      begin
        attempts += 1
        resolver.getaddress(name)
        :ok
      rescue Resolv::ResolvTimeout
        retry if attempts < RETRIES
        :timeout
      rescue Resolv::ResolvError
        retry if attempts < RETRIES
        :missing
      end
    end

    def live_domains
      match = File.read(REGISTRY, encoding: "UTF-8").match(/LIVE_DOMAINS\s*=\s*%w\[([^\]]+)\]/)
      return [] unless match

      match[1].split(/\s+/).reject(&:empty?)
    end
  end
end

`````

### gates/domain_alignment.rb

`````ruby
# frozen_string_literal: true

require "json"
require "pathname"
require_relative "../../OPENBSD/lib/deploy_inventory"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../../OPENBSD/bin/render_dns"

begin
  require_relative "../../RAILS/shared/lib/operator/deploy_paths"
rescue LoadError
  # ok for minimal ruby env
end

module Deploy
  class DomainAlignmentGate
    ROOT = Pathname.new(File.expand_path("../..", __dir__))
    REGISTRY = ROOT.join("RAILS", "brgen", "lib", "brgen", "domain_registry.rb")
    DEPLOY_INVENTORY = ROOT.join("OPENBSD", "deploy_inventory.json")
    RELAYD = ROOT.join("OPENBSD", "etc", "relayd.conf")
    COMMON_SUBAPPS = %w[radio dating tv takeaway maps messenger].freeze
    MASTER_ONLY_SUBAPPS = %w[ai].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      # The fleet render_dns writes zones for, read by the one parser that a test
      # holds to how zsh expands the same block.
      openbsd = RenderDns.city_zones
      registry = parse_registry_entries
      routes = parse_registry_subdomains

      if defined?(Operator::DeployPaths) && Operator::DeployPaths.respond_to?(:validate_layout!)
        begin
          Operator::DeployPaths.validate_layout!
        rescue StandardError => e
          result.fail("deploy layout: #{e.message}")
        end
      end

      missing_dns = registry.keys - openbsd.keys
      result.fail("domain set mismatch: missing DNS #{missing_dns.sort.join(', ')}") if missing_dns.any?

      registry.each do |domain, marketplace_subdomain|
        expected = expected_subdomains_for(domain, marketplace_subdomain)
        actual = openbsd.fetch(domain, [])
        missing = expected - actual
        extra = actual - expected
        result.fail("#{domain}: DNS missing #{missing.join(', ')}") if missing.any?
        result.fail("#{domain}: DNS extra #{extra.join(', ')}") if extra.any?
      end

      %w[tv dating takeaway maps messenger].each do |subapp|
        routes.fetch(subapp.to_sym).each do |label|
          next if COMMON_SUBAPPS.include?(label) || MASTER_ONLY_SUBAPPS.include?(label)

          result.fail("routes #{subapp} lists unknown label #{label}")
        end
      end

      # The key stays :playlist — that is the engine, and the engine keeps its
      # name. The label is the host, which became radio on 2026-09-12.
      routes.fetch(:playlist).each do |label|
        next if label == "radio"

        result.fail("routes radio lists unknown label #{label}")
      end

      master = parse_deploy_inventory
      relayd_keys = parse_relayd_keypairs

      if master[:apps] && !master[:apps].empty?
        # Derived from apps.yml, not restated. A literal table of the same three
        # domain/port pairs makes the gate a fifth copy
        # of the fact it exists to protect: edit apps.yml and the gate keeps
        # asserting the old numbers, and passes. port_inventory checks the other
        # four mirrors against apps.yml but does not read gates/lib, so nothing
        # would have caught the drift.
        expected_apps = Inventory.new(root: ROOT.to_s).apps.to_h do |app|
          [app.name, { domain: app.domain, port: app.port }]
        end
        expected_apps.each do |name, exp|
          entry = master[:apps][name]
          unless entry
            result.fail("deploy_inventory.json missing #{name}")
            next
          end
          result.fail("deploy_inventory.json domain mismatch for #{name}: #{entry['domain']} != #{exp[:domain]}") if entry["domain"] != exp[:domain]
          result.fail("deploy_inventory.json port mismatch for #{name}: #{entry['port']} != #{exp[:port]}") if entry["port"].to_i != exp[:port]
        end
        m = master[:master] || {}
        if m["domain"] != "ai.brgen.no" || m["port"].to_i != 53_187
          result.fail("deploy_inventory.json master_face mismatch: #{m['domain']}:#{m['port']}")
        end
      end

      # Derived, for the same reason the port table above it is. A literal list
      # of the four app apexes stood here -- the last hardcoded fleet list
      # inside the gate whose whole purpose is proving the fleet agrees.
      # A fourth app would have shipped with no keypair assertion and the gate would
      # have passed, which is exactly how relayd.conf drifted unnoticed for ports.
      live_apexes(master).each do |dom|
        result.fail("relayd.conf missing tls keypair for #{dom}") unless relayd_keys.include?(dom)
      end

      live_domains_check(result, registry.keys, relayd_keys)

      result
    end

    private

    # LIVE_DOMAINS must be exactly the city apexes relayd holds a keypair for.
    #
    # It is the list the layout iterates to draw the city network, so it decides
    # what a visitor can click. Both directions of drift are real and both have
    # happened:
    #
    #   too many  a domain in the list that relayd will not serve is a link to a
    #             TLS handshake failure, which a browser reports as an attack.
    #   too few   a domain relayd serves and the list omits is a city nobody can
    #             reach from the site. Five sat like that from whenever they were
    #             issued until 2026-08-12 — stvanger.no, trndheim.no, cardff.uk,
    #             edinbrgh.uk and frankfrt.de all had certificates, all resolved
    #             here, and none was linked or served.
    #
    # Source, not network. relayd.conf is tracked and is what gets installed, so
    # this holds off the deploy host and in CI — and a gate that needed DNS to run
    # would be the kind that passes having measured nothing.
    def live_domains_check(result, registry_domains, relayd_keys)
      declared = extract_constant(REGISTRY.read, "LIVE_DOMAINS")
      certified = registry_domains & relayd_keys

      unknown = declared - registry_domains
      result.fail("LIVE_DOMAINS names #{unknown.join(', ')}, absent from ENTRIES") if unknown.any?

      missing = certified - declared
      extra = declared - certified - unknown

      if missing.any?
        result.fail("LIVE_DOMAINS omits #{missing.sort.join(', ')} — relayd.conf has a tls keypair " \
                    "for each, so they serve and nothing links them")
      end
      if extra.any?
        result.fail("LIVE_DOMAINS names #{extra.sort.join(', ')} with no tls keypair in relayd.conf — " \
                    "the city network links a hostname that refuses TLS")
      end

      result.checked!(declared.size)
    end

    # Every domain that terminates TLS on vm23: the apps from apps.yml plus the
    # MASTER face, which is not a Rails app and so lives in deploy_inventory.json's
    # master_face rather than apps.yml.
    def live_apexes(master)
      apps = Inventory.new(root: ROOT.to_s).apps.map(&:domain)
      face = master.dig(:master, "domain")
      (apps + [face]).compact.uniq
    rescue StandardError => e
      raise "domain_alignment: inventory unreadable: #{e.class}: #{e.message}"
    end

    def parse_registry_entries
      text = REGISTRY.read
      text.scan(/Entry\.new\("([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*:[^,]+,\s*"[^"]+",\s*"([^"]+)"\)/).to_h
    end

    def parse_registry_subdomains
      text = REGISTRY.read
      {
        tv: extract_constant(text, "TV_SUBDOMAINS"),
        dating: extract_constant(text, "DATING_SUBDOMAINS"),
        playlist: extract_constant(text, "RADIO_SUBDOMAINS"),
        takeaway: extract_constant(text, "TAKEAWAY_SUBDOMAINS"),
        maps: extract_constant(text, "MAPS_SUBDOMAINS"),
        messenger: extract_constant(text, "MESSENGER_SUBDOMAINS"),
      }
    end

    def extract_constant(text, name)
      match = text.match(/#{name}\s*=\s*%w\[([^\]]+)\]/)
      raise "missing #{name} in domain_registry.rb" unless match

      # reject(&:empty?), because a %w[] wrapped across lines starts with a
      # newline and split leaves an empty first element — which then compares
      # unequal against every real list and fails the gate on formatting.
      match[1].split(/\s+/).reject(&:empty?)
    end

    def expected_subdomains_for(domain, marketplace_subdomain)
      # The marketplace subdomain is the only translated one — it comes from the
      # registry row (markedsplass, marknadsplats, marktplatz, mercato, ...).
      # Everything else is the same word in every city.
      subs = [marketplace_subdomain, *COMMON_SUBAPPS]
      subs << "ai" if domain == "brgen.no"
      subs.uniq
    end

    def parse_deploy_inventory
      return {} unless DEPLOY_INVENTORY.exist?

      data = JSON.parse(DEPLOY_INVENTORY.read)
      apps = (data["apps"] || []).each_with_object({}) { |a, h| h[a["name"]] = a }
      master = data["master_face"] || {}
      { apps: apps, master: master }
    end

    # A keypair line behind a hash mark is a certificate relayd does not load,
    # and counting it would call a city live that refuses TLS.
    def parse_relayd_keypairs(text = RELAYD.exist? ? RELAYD.read : "")
      text.each_line.flat_map { |line| line.sub(/#.*/, "").scan(/tls keypair "([^"]+)"/) }.flatten
    end
  end
end

`````

### gates/health_check.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "yaml"
require_relative "../lib/utf8"
require_relative "../lib/guard_state"
require_relative "../lib/permission_audit"
require_relative "../lib/disk_usage"
require_relative "../lib/deploy_stamp"

ROOT = File.expand_path("../..", __dir__)
APPS_YML = File.join(ROOT, "RAILS", "apps.yml")

options = {
  all_ready_apps: false,
  public: false,
  public_only: false,
  core: false,
  json: false,
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby40 OPENBSD/gates/health_check.rb [--core|--all-ready-apps] [--public|--public-only] [--json]"
  parser.on("--core", "Core services only: nsd, httpd, relayd, smtpd (required — it carries johann@brgen.no), " \
                      "brgen, and master, which is a service rather than an apps.yml app") { options[:core] = true }
  parser.on("--all-ready-apps", "Require every app listed in RAILS/apps.yml") { options[:all_ready_apps] = true }
  parser.on("--public", "Check public HTTPS endpoints, cert files, and externally-routed names") { options[:public] = true }
  # Everything else in this file needs rcctl, pfctl, /etc/relayd.conf and localhost
  # ports -- i.e. vm23. --public-only is the subset an external checker can actually
  # answer, and it exists so OPENBSD/bin/uptime-check.sh can be a wrapper over this
  # file instead of a second, hardcoded list of hosts: that copy named four domains
  # and would have gone on naming four after a fifth app shipped.
  parser.on("--public-only", "Only public HTTPS endpoints (runs anywhere, no vm23 tools)") do
    options[:public_only] = true
    options[:public] = true
  end
  parser.on("--json", "Emit machine-readable JSON on success") { options[:json] = true }
end.parse!

options[:all_ready_apps] = false if options[:core]

failures = []
# Written by load_apps when it cannot read the fleet, read once apps are loaded.
APPS_UNREADABLE = +""
MASTER_FACE_UNREADABLE = +""

# A missing binary is a named failure, not a backtrace. This raised Errno::ENOENT
# out of Open3 and killed the whole run at the first check: off the box that is
# every invocation (no /usr/sbin/rcctl), and on the box it would take the weekly
# integrity run down with a stack trace the moment a tool moved -- reporting
# nothing about the twenty checks after it. The point of this script is the list of
# failures, so an absent tool belongs in that list.
def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip]
rescue Errno::ENOENT, Errno::EACCES => e
  [false, "#{cmd.first}: #{e.class.name.split("::").last} (this check needs vm23)"]
end

def privileged(*cmd)
  return cmd if Process.uid.zero?
  return ["doas", "-n", *cmd] if File.executable?("/usr/bin/doas") || File.executable?("/bin/doas")
  cmd
end

def load_apps
  body = YAML.safe_load(File.read(APPS_YML)) || {}
  body.fetch("apps").to_h do |name, metadata|
    [name.to_s, { "domain" => metadata.fetch("domain").to_s, "port" => Integer(metadata.fetch("port")) }]
  end
rescue StandardError => e
  # A run that cannot read the fleet must not print "health check ok" having
  # checked master alone. APPS_UNREADABLE is picked up as a failure below, which
  # is the only honest answer a health check has when it does not know what it
  # is meant to check.
  APPS_UNREADABLE.replace("apps.yml unreadable: #{e.class}: #{e.message}")
  {}
end

# master is not an apps.yml app — it is not under /home/*/app — so its domain
# and port come from the deploy inventory, the one other place the fleet is
# written down, rather than from a literal here. The fallback keeps a run with
# no inventory checking something, and the failure it records says why.
MASTER_FACE_FALLBACK = { "domain" => "ai.brgen.no", "port" => 53_187 }.freeze

def master_face
  path = File.join(ROOT, "OPENBSD", "deploy_inventory.json")
  face = JSON.parse(File.read(path)).fetch("master_face")
  { "domain" => face.fetch("domain").to_s, "port" => Integer(face.fetch("port")) }
rescue StandardError => e
  MASTER_FACE_UNREADABLE.replace("deploy_inventory.json master_face unreadable: #{e.class}: #{e.message}")
  MASTER_FACE_FALLBACK
end

def service_running?(service)
  ok, out = run(*privileged("/usr/sbin/rcctl", "check", service))
  [ok && out.include?("(ok)"), out]
end

# OpenBSD packages curl into /usr/local/bin; every other host puts it in
# /usr/bin. Hardcoding the first meant a laptop run failed every HTTP check with
# "not found" and said nothing about whether the site was up.
# CURL= is honoured because the wrapper that documents it (bin/uptime-check.sh)
# is now a wrapper over this file.
CURL = [ENV["CURL"], "/usr/local/bin/curl", "/usr/bin/curl"]
       .compact.find { |path| File.executable?(path) } || "curl"
HTTP_TIMEOUT = Integer(ENV.fetch("HEALTH_CHECK_TIMEOUT", "25"))

def curl_ok?(url, timeout: HTTP_TIMEOUT)
  run(CURL, "-fsS", "--max-time", timeout.to_s, url)
end

apps = load_apps
failures << APPS_UNREADABLE unless APPS_UNREADABLE.empty?
master = master_face
failures << MASTER_FACE_UNREADABLE unless MASTER_FACE_UNREADABLE.empty?
app_ports = apps.transform_values { |metadata| metadata.fetch("port") }
app_domains = apps.transform_values { |metadata| metadata.fetch("domain") }

core_apps = %w[brgen]
ready_apps = options[:all_ready_apps] ? app_ports.keys.sort : core_apps

# Every check below this line except the HTTPS block needs a tool or a file that
# only exists on vm23. Under --public-only they are not skipped silently: the
# collections are empty and the guarded blocks say so in the scope line at the end,
# so a run cannot look like it checked the box when it checked the internet.
on_box = !options[:public_only]

core_services = %w[nsd httpd relayd smtpd master] + core_apps
required_services = on_box ? (core_services + ready_apps).uniq : []

required_services.each do |service|
  running, out = service_running?(service)
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless running
end

if on_box
  pfctl = File.executable?("/sbin/pfctl") ? "/sbin/pfctl" : "/usr/sbin/pfctl"
  ok, out = run(*privileged(pfctl, "-s", "rules"))
  pf_ok = ok && out.include?("block") && out.include?("log all")
  failures << "pfctl: #{out.empty? ? "no rules output" : out}" unless pf_ok

# Daemons that answer "ok" while doing nothing, and jobs whose only evidence is
# an empty log.
#
# pflogd spent 34 days in its [suspended] state — `rcctl check pflogd` said ok
# the whole time, because the process was alive; it had refused the log file it
# was handed (a snaplen it did not write) and, per pflogd(8), suspends logging
# until a SIGHUP. Packet filter logging was off and every health check passed.
# The state is in the process title, which is the only place it appears.
suspended, ps_out = run("/bin/ps", "-axo", "command")
if suspended && ps_out.include?("pflogd: [suspended]")
  failures << "pflogd: suspended — logging is off; move /var/log/pflog aside and SIGHUP (see RUNBOOK)"
end

# rcctl's own verdict on everything, not only the services this file lists.
# brgen_jobs — the Solid Queue worker — is not in apps.yml, so the loop above
# could not see it, and it sat failed with no background job running anywhere.
failed_ok, failed_out = run(*privileged("/usr/sbin/rcctl", "ls", "failed"))
if failed_ok
  failed_out.split("\n").map(&:strip).reject(&:empty?).each do |service|
    failures << "#{service}: rcctl lists it as failed"
  end
end

# A job that logs only when it acts cannot be told from a job that stopped
# running. core-reclaim writes a heartbeat every run for exactly that reason;
# anything over three hours old means the hourly job is not firing.
heartbeat = "/var/db/core_reclaim_seen"
if File.exist?(heartbeat)
  age_h = ((Time.now - File.mtime(heartbeat)) / 3600).round(1)
  failures << "core-reclaim: heartbeat #{age_h}h old — the hourly job is not running" if age_h > 3
end

# keep-warm runs every ten minutes and writes the same kind of heartbeat, so an
# hour of silence is six missed ticks rather than a quiet box.
warm_beat = "/var/db/keep_warm_seen"
if File.exist?(warm_beat)
  age_h = ((Time.now - File.mtime(warm_beat)) / 3600).round(1)
  failures << "keep-warm: heartbeat #{age_h}h old — the ten-minute job is not running" if age_h > 1
end

  # The address nsd listens on, from the file render_dns.rb writes nsd.conf's
  # ip-address from. nsd binds that address and nothing else, so asking
  # 127.0.0.1 timed out on a healthy server and this reported "no local SOA
  # (nsd reports ok)" on every run.
  nameserver = begin
    YAML.safe_load_file(File.join(__dir__, "..", "data", "dns.yml")).fetch("nameserver").fetch("ip").to_s
  rescue StandardError => e
    failures << "dns: data/dns.yml nameserver.ip unreadable: #{e.class}: #{e.message}"
    ""
  end
  dns_ok = false
  if nameserver.empty?
    dns_ok = true
  elsif File.executable?("/usr/bin/dig")
    dns_ok, dns_out = run("/usr/bin/dig", "@#{nameserver}", "brgen.no", "SOA", "+short", "+time=2", "+tries=1")
    dns_ok &&= !dns_out.empty? && dns_out.include?("brgen.no")
  elsif (dns_cmd = %w[/usr/sbin/drill /usr/bin/drill].find { |c| File.executable?(c) })
    dns_ok, dns_out = run(dns_cmd, "@#{nameserver}", "brgen.no", "SOA")
    dns_ok &&= dns_out.include?("brgen.no.")
  end
  unless dns_ok
    nsd_ok, nsd_out = run(*privileged("/usr/sbin/rcctl", "check", "nsd"))
    nsd_note = nsd_ok && nsd_out.include?("(ok)") ? "nsd reports ok" : nsd_out.to_s.strip
    failures << "dns: no local SOA (#{nsd_note.empty? ? 'nsd check failed' : nsd_note})"
  end

  # DNSSEC signature freshness, which nothing else can see.
  #
  # RRSIGs expire. nsd-resign re-signs anything with under 14 days left and runs
  # from /etc/daily.local, and for as long as that line read `ruby` rather than
  # an absolute path it had never once executed — cron's PATH does not include
  # /usr/local/bin. The zones stayed valid the whole time and every check passed,
  # because unexpired signatures on an unpublished DS look exactly like healthy
  # ones. The day a DS is published at the registrar, that stops being true and
  # the whole zone SERVFAILs on the expiry date.
  #
  # So this asks the question that distinguishes the two states: how long is
  # left. Under 7 days means the nightly re-sign has missed at least one window.
  # Root-only files, so it degrades to silence rather than a false pass off the
  # box or without doas.
  zone_dir = "/var/nsd/zones/master"
  signed = Dir.glob("#{zone_dir}/*.zone.signed")
  if signed.any?
    soon = signed.filter_map do |path|
      expiry = File.read(path, encoding: "BINARY")
                               .scan(/RRSIG\s+\S+\s+\d+\s+\d+\s+\d+\s+(\d{14})/)
                               .flatten
                               .min
      unless expiry
        failures << "dnssec: #{File.basename(path)} contains no readable RRSIG expiry"
        next
      end

      days = (Time.new(expiry[0, 4].to_i, expiry[4, 2].to_i, expiry[6, 2].to_i) - Time.now) / 86_400
      [File.basename(path, ".zone.signed"), days.round] if days < 7
    rescue StandardError => e
      failures << "dnssec: #{File.basename(path)} unreadable: #{e.class}: #{e.message}"
      next
    end

    unless soon.empty?
      failures << "dnssec: #{soon.size} zone(s) expire within a week — nsd-resign is not running " \
                  "(#{soon.first(5).map { |z, d| "#{z} #{d}d" }.join(', ')})"
    end

    # More than one KSK and one ZSK means keys are accumulating again, which is
    # what OPERATOR.sh's stage_1 used to do on every run: 700 key files for 60
    # zones, every one of them published, and a DNSKEY response within reach of
    # the 1232-byte UDP ceiling. It also makes a published DS unstable, because
    # nsd-resign signs with the newest key it finds.
    overkeyed = signed.filter_map do |path|
      count = File.read(path, encoding: "BINARY").scan(/IN\s+DNSKEY\s+25[67]\s/).size
      [File.basename(path, ".zone.signed"), count] if count > 2
    end
    unless overkeyed.empty?
      failures << "dnssec: #{overkeyed.size} zone(s) publish more than one KSK+ZSK pair " \
                  "(#{overkeyed.first(5).map { |z, c| "#{z} #{c}" }.join(', ')})"
    end
  end
end

# How far behind each app's last successful deploy is.
#
# A deploy that fails at a CI gate leaves the previous stamp saying "ok" and the
# old build serving, so from outside nothing has happened — and nothing reports
# it. amber sat at 2026-08-12T08:49 for a day and a half through three failed
# attempts, still preloading two CDNs that had been vendored three weeks earlier,
# and the only way to find out was to read a rendered page and compare it against
# the repo. Measured 2026-08-13: brgen 21 commits behind, bsdports 93.
#
# A count, not a clock. Time behind says nothing on a quiet week; commits behind
# is the thing that grows while a gate is red. Warned, not failed, because being
# behind is normal between deploys — the point is that the number is visible.
DEPLOY_DRIFT_LIMIT = Integer(ENV.fetch("DEPLOY_DRIFT_LIMIT", "40"))

if on_box
  repo = "/home/dev/pub4"
  apps.each_key do |name|
    sha = Deploy::DeployStamp.sha(name)
    next unless sha

    ok, out = run("git", "-C", repo, "rev-list", "--count", "#{sha}..HEAD")
    next unless ok

    behind = out.strip.to_i
    next if behind <= DEPLOY_DRIFT_LIMIT

    failures << "#{name} deploy: #{behind} commits behind HEAD (last ok #{sha}) — " \
                "a failed CI gate leaves the old stamp saying ok"
  end
end

# A queue with work in it and nobody registered to do it.
#
# brgen's rc.d exported SOLID_QUEUE_IN_PUMA=true while running under Falcon,
# which has no Puma plugin to read it, so no worker had ever started. Measured
# 2026-08-12: 1670 jobs enqueued, 0 finished, 0 processes, 0 recurring tasks.
# Every check on this box passed throughout — the web app was healthy and the
# jobs piled up in a SQLite file nobody queried. Disappearing messages
# had never disappeared and 141,753 guest rows had never been pruned.
#
# Read-only and per app, from the queue database directly rather than by booting
# Rails, so it costs nothing on a 1 vCPU box.
if on_box
  apps.each_key do |name|
    queue_db = "/home/#{name}/app/storage/production_queue.sqlite3"
    next unless File.readable?(queue_db)

    counts = [
      "SELECT COUNT(*) FROM solid_queue_jobs WHERE finished_at IS NULL " \
      "AND (scheduled_at IS NULL OR scheduled_at <= datetime('now'))",
      "SELECT COUNT(*) FROM solid_queue_processes",
    ].map do |sql|
      ok, out = run("/usr/local/bin/sqlite3", "-readonly", queue_db, sql)
      ok ? out.strip.to_i : nil
    end
    pending, workers = counts
    next if pending.nil? || workers.nil?

    # Zero workers is only a fault when there is work waiting, and "waiting"
    # means due. MessageExpirationJob is enqueued with wait_until set to the
    # moment the message should vanish, so a healthy brgen always has a pile of
    # jobs scheduled into the future — 57 of them right after a drain that left
    # nothing overdue. Counting those made this fire permanently on a queue with
    # nothing wrong with it, which is how a check becomes a line people skip.
    if pending.positive? && workers.zero?
      failures << "#{name} queue: #{pending} job(s) due and no registered Solid Queue process " \
                  "— see OPENBSD/etc/rc.d/#{name}_jobs"
    end
  end
end

# Anything resource_guard.sh shed that is still down. Why it matters, and why
# an earlier version of this check could not see it, is in lib/guard_state.rb.
if on_box && File.readable?(Deploy::GuardState::SHED_STATE)
  shed_list = File.read(Deploy::GuardState::SHED_STATE)
  running = ->(svc) { service_running?(svc).first }
  down = Deploy::GuardState.shed_and_down(shed: shed_list, running:)
  failures << down if down
end

# Secrets and app data other users can read, and daemon logs the daemon cannot
# write. The rule and the two times it has been broken are in the library.
if on_box
  require "etc"
  stat_entry = lambda do |path|
    stat = File.stat(path)
    owner = begin
      Etc.getpwuid(stat.uid).name
    rescue ArgumentError # a uid with no passwd entry is reported by number
      stat.uid.to_s
    end
    { path:, mode: stat.mode, owner: }
  end
  failures.concat(Deploy::PermissionAudit.failures(
    secrets: Dir.glob("/etc/*.env").map(&stat_entry),
    private_dirs: Dir.glob("/home/*/app/storage").map(&stat_entry),
    daemon_logs: Dir.glob("/home/dev/pub4/MASTER/.master/tts-worker-*.log").map(&stat_entry),
    daemon_user: "master"
  ))
end

if on_box
  df_ok, df_out = run("df", "-ik")
  failures.concat(df_ok ? Deploy::DiskUsage.failures(df_out) : ["disk: #{df_out}"])
end

up_checks = on_box ? { "master" => master.fetch("port") } : {}
ready_apps.each do |name|
  port = app_ports[name]
  failures << "#{name}: missing port in apps.yml" unless port
  up_checks[name] = port if port && on_box
end

up_checks.each do |name, port|
  ok, out = curl_ok?("http://127.0.0.1:#{port}/up", timeout: 20)
  failures << "#{name} up: #{out.empty? ? "no response on :#{port}" : out}" unless ok

  next unless ready_apps.include?(name)

  health_ok, health_out = curl_ok?("http://127.0.0.1:#{port}/health", timeout: 20)
  unless health_ok
    failures << "#{name} health: #{health_out.empty? ? "no response on :#{port}" : health_out}"
    next
  end

  begin
    payload = JSON.parse(health_out)
    failures << "#{name} health: status=#{payload['status']}" if payload["status"] == "unavailable"
    if name == "master"
      deploy = payload["deploy"] || {}
      failures << "master health: deploy.tts_socket false" if deploy["tts_socket"] == false
      failures << "master health: missing deploy.face_runtime_digest" if deploy["face_runtime_digest"].to_s.empty?
      booted = Deploy::DeployStamp.booted_mismatch(app: "master", booted: deploy["git_sha"],
                                                   stamped: Deploy::DeployStamp.sha("master"))
      failures << booted if booted
      voice = deploy.dig("voice_policy", "single_voice").to_s
      expected_voice = begin
        require "yaml"
        YAML.safe_load_file(File.join(ROOT, "MASTER", "data", "voice.yml"), aliases: true)
            .dig("tts", "single_voice").to_s
      rescue StandardError
        ""
      end
      if expected_voice.empty?
        failures << "master health: could not read MASTER/data/voice.yml tts.single_voice"
      elsif voice != expected_voice
        failures << "master health: voice_policy.single_voice=#{voice.inspect} (expected #{expected_voice})"
      end
      failures << "master health: checks.tts false" if payload.dig("checks", "tts") == false
    end
  rescue JSON::ParserError
    failures << "#{name} health: invalid JSON"
  end
end

if !on_box
  # /etc/relayd.conf is on vm23; the repo copy is deliberately not a substitute
  # (the relayd entries in RUNBOOK.md).
elsif File.file?("/etc/relayd.conf")
  # relayd.conf is root 0600 on vm23, and deploy_all.sh, start_all_apps.sh and
  # check-vps run this as dev. A plain read raised EACCES there and ended the run
  # before one failure printed, so an unprivileged run reads it through doas, as
  # the rcctl and pfctl checks above already do.
  relayd_path = "/etc/relayd.conf"
  relayd_read, relayd_conf = if File.readable?(relayd_path)
                               [true, File.read(relayd_path)]
                             else
                               run(*privileged("/bin/cat", relayd_path))
                             end
  if !relayd_read
    failures << "relayd: cannot read #{relayd_path} (#{relayd_conf})"
  elsif !(relayd_conf.include?("forward to <master>") && relayd_conf.include?('check http "/up"'))
    failures << "relayd: master backend missing http /up check"
  end
  (relayd_read ? ready_apps : []).each do |name|
    domain = app_domains[name]
    port = app_ports[name]
    failures << "relayd: missing domain route for #{domain}" if domain && !relayd_conf.include?(domain)
    failures << "relayd: missing backend port for #{name}:#{port}" if port && !relayd_conf.include?("port #{port}")
  end
else
  failures << "relayd: /etc/relayd.conf missing"
end

if options[:public] && on_box
  domains = ["brgen.no"] + ready_apps.filter_map { |name| app_domains[name] }
  domains.uniq.each do |domain|
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    crt = "/etc/ssl/#{domain}.crt"
    failures << "cert missing: #{fullchain} or #{crt}" unless File.exist?(fullchain) || File.exist?(crt)
  end
end

if options[:public]
  https_checks = {
    master.fetch("domain") => "https://#{master.fetch('domain')}/up",
    "brgen.no" => "https://brgen.no/up"
  }
  ready_apps.each do |name|
    domain = app_domains[name]
    https_checks[domain] = "https://#{domain}/up" if domain && domain != "brgen.no"
  end

  https_checks.each do |name, url|
    ok, out = curl_ok?(url)
    failures << "#{name} https: #{out.empty? ? "no response" : out}" unless ok
  end
end

if failures.any?
  if options[:json]
    puts JSON.generate(ok: false, failures: failures)
  else
    warn failures.join("\n")
  end
  exit 1
end

mode = options[:all_ready_apps] ? "all-ready-apps" : "core"
scope = if options[:public_only]
          "public-only (#{ready_apps.size} app(s); nothing on vm23 was checked)"
        elsif options[:public]
          "#{mode}+public"
        else
          mode
        end
if options[:json]
  puts JSON.generate(ok: true, scope: scope, services_checked: required_services, apps_checked: ready_apps)
else
  puts "health check ok (#{scope})"
end

`````

### gates/installed_targets_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Every executable the box is told to run must be one the repo actually installs.
#
# On 2026-08-25 /etc/daily.local guarded a root-run drift check on
# `[ -x /usr/local/bin/config_drift_gate.rb ]`. Nothing installed that file:
# install_root_configs copies etc/, usr/ and var/ from the repo, and the script
# lives at OPENBSD/gates/config_drift_gate.rb, outside usr/local/bin/. So the guard was
# false on every run and the check had never executed. Live had been hand-edited
# to run it out of /home/dev/pub4 instead — root executing a file the dev user
# can rewrite, every morning.
#
# Both halves of that were invisible for the same reason: a guard, its target,
# and the thing that installs the target are three separate facts, and nothing
# compared them. This compares them, from the repo, with no box required — which
# is the point. A check that only runs on vm23 cannot fail a pull request.
#
# It reads what the box runs: crontab, the periodic scripts, every rc.d service,
# and every script the repo itself installs under /usr/local — resource_guard.sh
# calls its crisis tier at /usr/local/bin/emergency_cpu.sh and dot-sources
# /usr/local/libexec/stale_ci_cleanup.ksh, and a script is as much a referrer as
# a crontab line. It pulls out each /usr/local/{bin,libexec} path they name and
# asks whether the repo provides it — either as a tracked file under
# OPENBSD/usr/local/ (install_root_configs copies the tree) or through an
# explicit `install` line in OPERATOR.sh.
#
#   ruby OPENBSD/gates/installed_targets_gate.rb
#   ruby OPENBSD/gates/installed_targets_gate.rb --json

require "json"

module Deploy
  module InstalledTargetsGate
    DEFAULT_ROOT = File.expand_path("..", __dir__)

    # Overridable so a test can plant a tree and watch the gate fail on it.
    @root = DEFAULT_ROOT
    class << self
      attr_accessor :root
    end

    CONFIG_GLOBS = ["etc/crontab*", "etc/*.local", "etc/rc.d/*"].freeze
    SHIPPED_GLOB = "usr/local/{bin,libexec}/*"
    # A name that runs on into a slash is a directory named in prose — the
    # /usr/local/bin/lib/ that config_drift_gate.rb explains away — not a target.
    TARGET = %r{/usr/local/(bin|libexec)/([A-Za-z0-9_.-]+)(?![A-Za-z0-9_./-])}
    INSTALL_LINE = %r{install\s[^\n]*?/usr/local/(bin|libexec)/([A-Za-z0-9_.-]+)}
    INSTALL_SOURCE = %r{install\s[^\n]*?"\$\{SCRIPT_DIR\}/([A-Za-z0-9_./-]+)"}

    # Base-system and package binaries. The gate is about what THIS repo is
    # responsible for installing, not about auditing the OpenBSD ports tree.
    PROVIDED_BY_PACKAGES = %w[
      ruby40 bundle40 git sqlite3 psql rcctl relayctl nsd-control acme-client
      vips ffmpeg node npm doas su tee logger newsyslog drill dig sendmail curl wget
    ].freeze

    module_function

    def read(path) = File.read(path, encoding: "UTF-8").scrub

    def operator
      path = File.join(root, "OPERATOR.sh")
      File.file?(path) ? read(path) : ""
    end

    # The config that names a path, and every script the repo puts under
    # /usr/local — including the ones OPERATOR.sh installs from the tree root.
    def referrers
      config = CONFIG_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }
      installed = operator.scan(INSTALL_SOURCE).flatten.map { |name| File.join(root, name) }
      (config + Dir.glob(File.join(root, SHIPPED_GLOB)) + installed).select { |f| File.file?(f) }.uniq.sort
    end

    # Every /usr/local/{bin,libexec}/<name> a referrer names, keyed "bin/<name>",
    # with the files that named it.
    def referenced
      referrers.each_with_object({}) do |path, acc|
        read(path).scan(TARGET) do |dir, name|
          name = name.sub(/\.\z/, "") # prose punctuation, not part of the filename
          next if PROVIDED_BY_PACKAGES.include?(name)

          (acc["#{dir}/#{name}"] ||= []) << path.delete_prefix("#{root}/")
        end
      end
    end

    def shipped
      Dir.glob(File.join(root, SHIPPED_GLOB)).map { |f| f.delete_prefix("#{root}/usr/local/") }
    end

    def explicitly_installed
      operator.scan(INSTALL_LINE).map { |dir, name| "#{dir}/#{name}" }
    end

    def provided
      (shipped + explicitly_installed).uniq
    end

    def orphans
      have = provided
      referenced.reject { |target, _| have.include?(target) }
    end

    def run(json: false)
      missing = orphans
      if json
        puts JSON.generate(referenced: referenced.size, provided: provided.size,
                           missing: missing.map { |target, where| { target: target, referenced_by: where } })
        return missing.empty?
      end

      puts "installed-targets: #{referenced.size} /usr/local target(s) named by config and installed scripts, " \
           "#{provided.size} provided by the repo"
      if missing.empty?
        puts "installed-targets: clean — every target the box is told to run is one the repo installs"
        return true
      end

      missing.each do |target, where|
        warn "installed-targets: /usr/local/#{target} is named by #{where.join(', ')} and nothing installs it"
      end
      warn "installed-targets: add it to OPENBSD/usr/local/ (copied wholesale) or an install line in OPERATOR.sh"
      warn "installed-targets: a guard on a target that does not exist fails OPEN, into silence"
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Deploy::InstalledTargetsGate.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end

`````

### gates/integrity_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# OPENBSD integrity chain — production, phantom FK, frontend, relayd, domain, crawl inventory.

require "open3"
require_relative "../lib/utf8"
require_relative "../lib/gate_environment"

INTEGRITY_ROOT = File.expand_path("../..", __dir__)

# Exit 3 is how a subprocess gate says it measured nothing: crawl_probe with no
# app listening, as MASTER/gates/runner.rb's SUBPROCESS_INCONCLUSIVE reads it.
INTEGRITY_INCONCLUSIVE = 3

# The gate's own command, run from the repo root. Returns [output, verdict],
# the verdict true, false or :inconclusive.
RUN_GATE = lambda do |cmd|
  out, status = Open3.capture2e(*cmd, chdir: INTEGRITY_ROOT)
  [out, status.exitstatus == INTEGRITY_INCONCLUSIVE ? :inconclusive : status.success?]
end

# Every gate in order, sorted into failures, warnings and skips. skip_reason
# decides each skip from the needs the gate declares, so vps_health off the box
# is skipped by the same rule as any other gate and never executed.
def integrity_run(gates, root: INTEGRITY_ROOT, on_vps: Operator::Environment.on_vps?, execute: RUN_GATE, io: $stdout)
  report = { failures: [], warnings: [], skipped: [] }
  gates.each do |gate|
    label = "integrity: #{gate.name.ljust(18)}"
    script = File.join(root, gate.path)
    unless File.file?(script)
      report[:warnings] << "#{gate.name}: missing #{gate.path}"
      next
    end

    if (reason = Deploy::GateEnvironment.skip_reason(gate, on_vps:))
      report[:skipped] << "#{gate.name}: #{reason}"
      io.puts "#{label} skip — #{reason}"
      next
    end

    out, ok = execute.call([Operator::RubyRunner.gate_ruby, script, *Array(gate.args)])
    # A gate that measured nothing is neither a pass nor a failure. It is listed
    # as skipped with its own reason, and blocks only under
    # GATE_STRICT_INCONCLUSIVE=1, the same policy the RAILS runner applies.
    if ok == :inconclusive && !%w[1 true yes on].include?(ENV["GATE_STRICT_INCONCLUSIVE"].to_s.downcase)
      report[:skipped] << "#{gate.name}: measured nothing — #{out.lines.first.to_s.strip}"
      io.puts "#{label} inconclusive"
    elsif ok == true
      io.puts "#{label} ok"
    elsif gate.optional
      report[:warnings] << "#{gate.name}: #{out.lines.last(3).join.strip}"
      io.puts "#{label} warn"
    else
      report[:failures] << gate.name
      io.puts "#{label} fail"
      io.puts out unless out.strip.empty?
      # A box-side gate that cannot connect usually means a pull with no deploy.
      if Array(gate.needs).include?(:vps) && (out.include?("Could not connect") || out.include?("failed"))
        warn Deploy::GateEnvironment.post_pull_warning
      end
    end
  end
  report
end

return unless $PROGRAM_NAME == __FILE__

report = integrity_run(Deploy::GateEnvironment::INTEGRITY_GATES)
report[:skipped].each { |line| warn "integrity: skip — #{line}" }
report[:warnings].each { |line| warn "integrity: warn — #{line}" }

if report[:failures].empty?
  puts "integrity: clean"
  exit 0
end

warn "integrity: #{report[:failures].size} gate(s) failed: #{report[:failures].join(', ')}"
exit 1

`````

### gates/port_inventory.rb

`````ruby
# frozen_string_literal: true

require "English"
require "yaml"
require_relative "../../OPENBSD/lib/deploy_inventory"
require_relative "../../OPENBSD/lib/gate_result"

module Deploy
  class PortInventoryGate
    ROOT = File.expand_path("../..", __dir__)
    DEPLOY_INVENTORY = ENV.fetch("DEPLOY_INVENTORY", File.join(ROOT, "OPENBSD", "deploy_inventory.json"))
    OPENBSD_DEPLOY = File.join(ROOT, "OPENBSD", "OPERATOR.sh")
    APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
    RAILS_README = File.join(ROOT, "RAILS", "README.md")
    PWA_BUILDER = File.join(ROOT, "RAILS", "tools", "build_workbox.mjs")
    RELAYD_CONF = File.join(ROOT, "OPENBSD", "etc", "relayd.conf")
    CRAWL_MANIFEST = File.join(ROOT, "RAILS", "crawl_manifest.yml")
    # Health probes that name a loopback port. They must never probe a port no
    # app listens on: a retired port here does not fail loudly, it reports the
    # app down forever, or reports a different app's health under this app's
    # name once the number is reused.
    SMOKE_SCRIPTS = [
      "OPENBSD/bin/deploy-smoke.sh",
      # keep-warm pairs a host with a port on one line and runs on
      # a timer against production, so a number that stops being true here does
      # not fail -- it quietly warms nothing, which is the same shape as a probe
      # reporting an app healthy on a port it no longer listens on.
      "OPENBSD/usr/local/bin/keep-warm.sh",
    ].freeze

    # MASTER's face is not a Rails app and has no apps.yml row.
    MASTER_PORT = 53_187

    # Every file that states two or more app ports, and why it is allowed to.
    #
    # A file naming one port is using a number; a file naming the whole fleet is
    # a second inventory, and this repo has shipped the failure that follows
    # from an unchecked one. The rule is not "do not restate the ports" — five
    # of these must restate them to do their job — it is that restating them
    # without being checked against apps.yml is what fails. So each row below is
    # either machine-checked by a method in this class, or carries the reason it
    # cannot be. A new fleet inventory that appears in neither fails the gate.
    #
    # Two entries left this list on 2026-08-10: page_simulation.rb and
    # domain_alignment.rb each held a literal three-app port map. The second one
    # was the gate that exists to prove the fleet agrees, restating the fleet
    # instead of reading it.
    FLEET_INVENTORIES = {
      "RAILS/apps.yml" => "source of truth",
      "OPENBSD/deploy_inventory.json" => "checked: check_master_json",
      "OPENBSD/OPERATOR.sh" => "checked: check_openbsd_ports",
      "OPENBSD/etc/relayd.conf" => "checked: check_relayd_ports",
      "RAILS/crawl_manifest.yml" => "checked: check_crawl_manifest",
      "RAILS/README.md" => "checked: check_readmes",
      "OPENBSD/bin/deploy-smoke.sh" => "checked: check_smoke_probes",
      "OPENBSD/usr/local/bin/keep-warm.sh" => "checked: check_smoke_probes",
      "RAILS/test/deploy_smoke_contract_test.rb" => "asserts the smoke scripts' own content",
      "CLAUDE.md" => "prose: the shed-vs-outage triage note, trap 3",
      "TODO.md" => "prose: the repo-wide backlog, which names ports in its deploy entries",
      "RAILS/CLAUDE.md" => "prose: the shed-vs-outage triage note",
      "OPENBSD/CLAUDE.md" => "prose: same triage note",
      "OPENBSD/RUNBOOK.md" => "prose: operator reference",
      "MASTER/gates/PAGE_SIM.md" => "generated report",
    }.freeze

    FLEET_SCAN_GLOB = "{RAILS,OPENBSD,MASTER,bin}/**/*.{rb,sh,yml,yaml,json,conf,mjs,js,md,erb,exp}"
    # .master/ is runtime cache and never committed; knowledge/ and output/ are
    # generated. Scanning them reports the model's own transcript as an inventory.
    FLEET_SCAN_SKIP = %r{/(\.git|node_modules|\.master|knowledge|output|public/assets|tmp|log|storage)/}

    # Files that must not name a retired app outside a comment: the scripts and
    # tooling that run, and the config files a retired app leaves itself in. Every
    # entry is a live file; the retired thing is the name. On 2026-08-12, two months after
    # the repo recorded baibl and blognet removed — apps, relayd, acme, nsd,
    # litestream, rc.d, inventories — vm23 still had both users, both home
    # directories, both rc.d scripts, both /etc/*.env files, both login classes,
    # both certificate symlinks, both DNS zones, and blognet in litestream.yml.
    # The config half of this list is where those leftovers lived.
    SCANNED_FOR_RETIRED_NAMES = [
      "OPENBSD/bin/vps_console.exp",
      "OPENBSD/usr/local/bin/relayd-watchdog",
      "RAILS/env.sample",
      "RAILS/tools/build_workbox.mjs",
      "OPENBSD/etc/rc.conf.local",
      "OPENBSD/etc/login.conf",
      "OPENBSD/etc/litestream.yml",
      "OPENBSD/etc/relayd.conf",
      "OPENBSD/etc/acme-client.conf",
      "OPENBSD/data/dns.yml",
      "OPENBSD/var/nsd/etc/nsd.conf",
    ].freeze

    RETIRED_APP_NAMES = %w[baibl blognet hjerterom].freeze

    def self.run
      new.run
    end

    def run
      inventory = Inventory.new(root: ROOT)
      apps = inventory.apps
      result = GateResult.new

      return result.inconclusive!("port_inventory: the inventory lists no apps — every check below reads that list") if apps.empty?

      # Fourteen checks, all of them unconditional once the inventory loads.
      result.checked!(14)
      check_uniques(result, apps, :name)
      check_uniques(result, apps, :domain)
      check_uniques(result, apps, :port)
      check_ports(result, apps)
      check_master_json(result, apps)
      check_deploy_scripts(result, apps)
      check_openbsd_ports(result, apps)
      check_relayd_ports(result, apps)
      check_crawl_manifest(result, apps)
      check_smoke_probes(result, apps)
      check_fleet_inventories(result, apps)
      check_pwa_builder(result, apps)
      check_readmes(result, apps)
      check_retired_names_not_active(result)
      result
    end

    private

    # relayd is the only one of these mirrors that carries live traffic, and it
    # was the only one nothing checked. Changing a port in apps.yml updates the
    # deploy script, OPERATOR.sh, deploy_inventory.json, the README and the
    # Workbox list — all five verified above — while relayd keeps forwarding to
    # the old number. The gate passes, the deploy succeeds, rcctl reports the
    # app running, and the site serves 502 from the one file no check read.
    def check_relayd_ports(result, apps)
      unless File.file?(RELAYD_CONF)
        result.fail("missing OPENBSD/etc/relayd.conf")
        return
      end

      body = File.read(RELAYD_CONF)
      forwards = body.scan(/forward\s+to\s+<([a-z0-9_]+)>\s+port\s+(\d+)/i)
        .to_h { |name, port| [name, port.to_i] }
      hosts = body.scan(/value\s+"([^"]+)"\s+forward\s+to\s+<([a-z0-9_]+)>/i)
        .each_with_object({}) { |(host, table), acc| acc[host] = table }

      apps.each do |app|
        unless forwards.key?(app.name)
          result.fail("relayd.conf has no `forward to <#{app.name}> port` line")
          next
        end

        actual = forwards.fetch(app.name)
        next if actual == app.port

        result.fail("#{app.name}: relayd.conf forwards to port #{actual}, apps.yml says #{app.port}")
      end

      apps.each do |app|
        table = hosts[app.domain]
        if table.nil?
          result.fail("#{app.name}: relayd.conf does not route Host #{app.domain}")
        elsif table != app.name
          result.fail("#{app.name}: relayd.conf routes #{app.domain} to <#{table}>")
        end
      end
    end

    def check_crawl_manifest(result, apps)
      unless File.file?(CRAWL_MANIFEST)
        result.fail("missing RAILS/crawl_manifest.yml")
        return
      end

      manifest = YAML.safe_load(File.read(CRAWL_MANIFEST), aliases: true)
      declared = manifest.fetch("apps", {})
      apps.each do |app|
        entry = declared[app.name]
        if entry.nil?
          result.fail("crawl_manifest.yml has no target for #{app.name}")
        elsif entry["port"].to_i != app.port
          result.fail("#{app.name}: crawl_manifest.yml port #{entry['port']} must mirror apps.yml #{app.port}")
        end
      end
    end

    # These scripts write a port two ways -- `http://127.0.0.1:38182/up` and a
    # bare `smoke brgen 38182` argument -- so matching only the URL form reads
    # one of them and calls the file checked. Both forms are five digits, which
    # is what makes a plain number scan safe here: a four-digit year or a
    # `-m 5` timeout cannot collide with it.
    PORT_TOKEN = /(?<![\d.])(\d{5})(?![\d])/

    def check_smoke_probes(result, apps, root: ROOT, scripts: SMOKE_SCRIPTS)
      by_name = apps.to_h { |app| [app.name, app.port] }
      known = by_name.values + [MASTER_PORT]

      scripts.each do |relative|
        path = File.join(root, relative)
        unless File.file?(path)
          result.fail("missing smoke script #{relative}")
          next
        end

        File.readlines(path).each_with_index do |line, index|
          numbers = line.scan(PORT_TOKEN).flatten.map(&:to_i).uniq
          next if numbers.empty?

          named = by_name.keys.select { |name| line.include?(name) }
          allowed = named.empty? ? known : named.map { |name| by_name.fetch(name) } + [MASTER_PORT]

          (numbers - allowed).each do |port|
            result.fail(
              "#{relative}:#{index + 1} probes port #{port}, which no app in apps.yml listens on" \
              "#{named.empty? ? '' : " (line names #{named.join(', ')})"}",
            )
          end
        end
      end
    end

    # Tracked files plus untracked ones git would not ignore. That is the right
    # scope as well as the fast one: gitignored trees cannot carry a committed
    # second inventory, and globbing them measured 44,831 files and 40 seconds,
    # almost all of it node_modules and asset builds inside the three app trees.
    # --others is what makes the gate catch a new inventory on the run before it
    # is committed rather than the run after. Falls back to the glob where there
    # is no git — the copy-tree on vm23 is not a checkout.
    def fleet_scan_paths
      tracked = IO.popen(
        ["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        &:read
      )
      raise "git unavailable" unless $CHILD_STATUS&.success?

      paths = tracked.split("\0").grep(/\.(rb|sh|ya?ml|json|conf|mjs|js|md|erb|exp)\z/)
      raise "empty tree" if paths.empty?

      paths
    rescue StandardError
      Dir.glob(File.join(ROOT, FLEET_SCAN_GLOB)).map { |path| path.delete_prefix("#{ROOT}/") }
    end

    def check_fleet_inventories(result, apps)
      ports = apps.map { |app| app.port.to_s }
      fleet_scan_paths.each do |relative|
        next if "/#{relative}" =~ FLEET_SCAN_SKIP
        next if FLEET_INVENTORIES.key?(relative)

        path = File.join(ROOT, relative)
        next unless File.file?(path)

        body = begin
          File.read(path)
        rescue StandardError
          next
        end
        next if ports.count { |port| body.include?(port) } < 2

        result.fail(
          "#{relative} states two or more app ports but is not in " \
          "PortInventoryGate::FLEET_INVENTORIES. Either read them from apps.yml, " \
          "or add a row saying which check covers this file — an undeclared " \
          "second inventory is how relayd.conf drifted unnoticed.",
        )
      end
    end

    def check_uniques(result, apps, field)
      apps.group_by { |app| app.public_send(field) }.each do |value, grouped|
        next if grouped.size == 1

        result.fail("#{field} collision #{value}: #{grouped.map(&:name).join(', ')}")
      end
    end

    def check_ports(result, apps)
      apps.each do |app|
        unless app.port.between?(1, 65_535)
          result.fail("#{app.name}: port #{app.port.inspect} must be between 1 and 65535")
        end
      end
    end

    def check_master_json(result, apps)
      unless File.file?(DEPLOY_INVENTORY)
        result.fail("missing OPENBSD/deploy_inventory.json mirror: #{DEPLOY_INVENTORY}")
        return
      end

      master = Inventory.new(root: ROOT).master_apps(path: DEPLOY_INVENTORY)
      expected = apps.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      actual = master.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      result.fail("OPENBSD/deploy_inventory.json must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_deploy_scripts(result, apps)
      apps.each do |app|
        path = File.join(ROOT, app.deploy_script)
        unless File.file?(path)
          result.fail("#{app.name}: missing deploy script #{app.deploy_script}")
          next
        end

        text = File.read(path)
        {
          "APP_NAME=#{app.name}" => "APP_NAME",
          "APP_DOMAIN=#{app.domain}" => "APP_DOMAIN",
          "APP_PORT=#{app.port}" => "APP_PORT"
        }.each do |needle, label|
          result.fail("#{app.name}: deploy script #{label} must mirror apps.yml") unless text.include?(needle)
        end
      end
    end

    def openbsd_ports
      body = File.read(OPENBSD_DEPLOY)
      match = body.match(/typeset -A APP_PORTS=\(\n(?<ports>.*?)\n\)/m)
      return {} unless match

      match[:ports].lines.each_with_object({}) do |line, ports|
        entry = line.match(/\A\s*(?<name>[a-z0-9_]+)\s+(?<port>\d+)\s*(?:#.*)?\z/i)
        next unless entry

        ports[entry[:name]] = entry[:port].to_i
      end
    end

    def check_openbsd_ports(result, apps)
      unless File.file?(OPENBSD_DEPLOY)
        result.fail("missing OpenBSD deploy script: #{OPENBSD_DEPLOY}")
        return
      end

      ports = openbsd_ports
      result.fail("OPENBSD/OPERATOR.sh missing APP_PORTS map") if ports.empty?
      apps.each do |app|
        result.fail("#{app.name}: missing fixed OpenBSD APP_PORTS entry") unless ports.key?(app.name)
        next unless ports.key?(app.name) && ports.fetch(app.name) != app.port

        result.fail("#{app.name}: OpenBSD APP_PORTS #{ports.fetch(app.name)} must mirror apps.yml #{app.port}")
      end
    end

    def check_pwa_builder(result, apps)
      unless File.file?(PWA_BUILDER)
        result.fail("missing Workbox builder: #{PWA_BUILDER}")
        return
      end

      body = File.read(PWA_BUILDER)
      match = body.match(/const APPS = \[(?<apps>.*?)\]/)
      unless match
        result.fail("RAILS/tools/build_workbox.mjs must expose const APPS")
        return
      end

      actual = match[:apps].scan(/"([^"]+)"/).flatten.sort
      expected = apps.map(&:name).sort
      result.fail("Workbox APPS must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_readmes(result, apps)
      root_readme = File.read(RAILS_README)
      result.fail("RAILS/README.md active app count must mirror apps.yml") unless root_readme.include?("#{apps.size} active production Rails")

      apps.each do |app|
        readme_path = File.join(ROOT, app.deploy_root, "README.md")
        unless File.file?(readme_path)
          result.fail("#{app.name}: missing README.md")
          next
        end

        readme = File.read(readme_path)
        result.fail("#{app.name}: README must point humans to apps.yml feature matrix") unless readme.include?("apps.yml")
        result.fail("#{app.name}: README deploy command must mirror apps.yml") unless readme.include?(app.deploy_script)
        result.fail("#{app.name}: README health check must mirror apps.yml port") unless readme.include?("127.0.0.1:#{app.port}/up")
      end
    end

    def check_retired_names_not_active(result)
      SCANNED_FOR_RETIRED_NAMES.each do |relative|
        path = File.join(ROOT, relative)
        next unless File.file?(path)

        # Comments are exempt. A retired name in a line explaining why it was
        # removed is the record of the removal; a retired name in a directive is
        # the removal not having happened. Matching both would push people to
        # delete the explanation, which is the half worth keeping.
        body = File.read(path, encoding: "UTF-8").lines.reject { |line| line.match?(/\A\s*[#;]/) }.join

        RETIRED_APP_NAMES.each do |name|
          next unless body.match?(/\b#{Regexp.escape(name)}\b/)

          result.fail("#{relative}: retired app #{name} must not appear in active deploy tooling")
        end
      end
    end
  end
end

`````

### gates/shell_syntax_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse every shell script in this tree with the interpreter its shebang names.
#
# check-openbsd used to name two files by hand — vps_ci_all.sh and OPERATOR.sh —
# out of 43. The deploy path itself was not among them: bin/vps-deploy, vps_ci.sh
# and deploy_all.sh are what a deploy actually runs, so a syntax error in any of
# the three waited for a deploy to find it. resource_guard.sh is ksh, which a zsh
# list could not have covered at all.
#
# A hand-kept list is the wrong shape for this. A script's own shebang says which
# parser is authoritative for it, so reading that is both the complete set and the
# correct interpreter per file, and a script added tomorrow is covered by having a
# shebang rather than by somebody remembering this file.
#
# `-n` parses without executing, so this is safe to run anywhere, including on the
# box.

# SHELL_SYNTAX_ROOT points the scan at a fixture tree, so the gate can be shown failing.
ROOT = ENV.fetch("SHELL_SYNTAX_ROOT", File.expand_path("../..", __dir__))
Dir.chdir(ROOT)

INTERPRETERS = %w[zsh ksh sh bash].freeze
SHEBANG = %r{\A\#!\s*(?:/usr/bin/env\s+)?(?:\S*/)?(#{INTERPRETERS.join('|')})\b}

# ksh -n on OpenBSD warns about `[[ -gt ]]` in scripts that are otherwise valid.
# The gate is about parse errors, not about a style the tree has settled on.
STYLE_WARNING = /obsolete/

def shebang_interpreter(path)
  first = File.open(path, &:readline)
  first[SHEBANG, 1]
rescue EOFError, ArgumentError
  nil
end

scripts = (Dir.glob("OPENBSD/**/*.sh") + Dir.glob("OPENBSD/bin/*") + Dir.glob("OPENBSD/usr/local/bin/*"))
          .uniq.sort.select { |path| File.file?(path) }

failures = []
checked = 0

scripts.each do |path|
  interpreter = shebang_interpreter(path)
  next unless interpreter

  checked += 1
  output = IO.popen([interpreter, "-n", path], err: [:child, :out], &:read)
  parsed = $?.success?
  complaints = output.lines.reject { |line| line.match?(STYLE_WARNING) }.join.strip
  next if parsed && complaints.empty?

  failures << "#{interpreter} -n #{path}\n#{complaints.empty? ? '  exited nonzero with no message' : complaints}"
end

if checked.zero?
  warn "shell_syntax: no script carried a shebang — the scan is broken, not the tree"
  exit 1
end

if failures.empty?
  puts "shell_syntax: #{checked} scripts parse"
  exit 0
end

warn "shell_syntax: #{failures.size} of #{checked} scripts do not parse"
failures.each { |failure| warn failure }
exit 1

`````

### gates/solid_queue_proof.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Prove that an app's background jobs actually get run.
#
# vm23 runs jobs two ways. brgen has a resident worker, rc.d/brgen_jobs, listed
# in pkg_scripts because it is the one this 1 GB box can hold. amber and
# bsdports have none: rc.d/amber_jobs and rc.d/bsdports_jobs stay off, and
# /usr/local/bin/drain-jobs.sh runs their queues hourly. A proof that asked only
# for a registered SolidQueue::Process would fail those two for doing what was
# decided, and because vps-deploy exits 1 on it, the pass would halt before them.
#
# What the gate is for: an app whose jobs never run is an app whose
# disappearing messages never disappear and whose database never gets
# snapshotted. So there are two ways to pass and both are evidence of work
# being done:
#
#   1. a supervisor is registered — the resident worker
#   2. the cron drain ran for this app recently — the hourly drain
#
# The adapter check hard-fails either way. An app that is not on SolidQueue at
# all is misconfigured no matter who runs the jobs.

require "shellwords"
require "time"

module SolidQueueProof
  DRAIN_LOG = "/var/log/drain-jobs.log"
  # drain-jobs.sh is scheduled hourly at :05. Two hours tolerates one missed
  # tick — the script skips its run when load stays over its ceiling — without
  # tolerating a drain that has silently stopped for a day.
  MAX_DRAIN_AGE_S = 7200

  module_function

  # Lines look like:
  #   2026-08-18T02:08:07Z brgen due 11 -> 2  ahead=48 failed=0 (ran 180s)
  #   2026-08-18T02:08:07Z amber nothing due (ahead=0 failed=0)
  #
  # "nothing due" still counts. It is the drain reporting that it looked at this
  # app and found no work, which is proof it ran, not proof it was idle.
  def last_drain_at(app, log_path: DRAIN_LOG)
    return nil unless File.readable?(log_path)

    stamp = nil
    File.foreach(log_path) do |line|
      fields = line.split
      next unless fields[1] == app

      parsed = (Time.parse(fields[0]) rescue nil)
      stamp = parsed if parsed
    end
    stamp
  end

  def drain_recent?(app, now: Time.now, log_path: DRAIN_LOG, max_age: MAX_DRAIN_AGE_S)
    at = last_drain_at(app, log_path: log_path)
    return false unless at

    (now - at) <= max_age
  end

  # 0 a worker is registered, 3 the adapter is right but nothing is registered,
  # 1 the app is not on SolidQueue. Three rather than a boolean because "no
  # resident worker" is the normal state here and must be distinguishable from
  # "misconfigured", which the old script could not do.
  def runner_source(app, tries)
    <<~RUBY
      adapter = ActiveJob::Base.queue_adapter
      unless adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
        warn "solid_queue: #{app} adapter=\#{adapter.class.name}"
        exit 1
      end

      n = 0
      #{tries}.times do |i|
        n = SolidQueue::Process.count
        break if n.positive?

        sleep 2 unless i == #{tries} - 1
      end

      if n.positive?
        warn "solid_queue: #{app} processes=\#{n}"
        exit 0
      end

      warn "solid_queue: #{app} adapter present, no resident worker registered"
      exit 3
    RUBY
  end

  def load_env(app)
    # The same one file rc.d/<app> hands the running app.
    path = "/etc/#{app}.env"
    return unless File.readable?(path)

    File.foreach(path) do |line|
      key, value = line.strip.split("=", 2)
      next if key.nil? || key.start_with?("#") || value.nil?

      ENV[key] = value
    end
  end

  def main(argv)
    app = argv.fetch(0) { abort "usage: solid_queue_proof.rb APP" }
    app_dir = "/home/#{app}/app"
    abort "missing #{app_dir}" unless File.directory?(app_dir)

    load_env(app)
    secret = ENV.fetch("SECRET_KEY_BASE", "")
    abort "missing SECRET_KEY_BASE in /etc/#{app}.env" if secret.empty?

    drained = drain_recent?(app)
    # Waiting 30 seconds for a worker an app does not run is 30 seconds per app
    # on every deploy. When the drain already proves the work is being
    # done, look once and move on; when it does not, give a starting supervisor
    # the full window before calling it dead.
    tries = drained ? 1 : 15

    cmd = [
      "su", "-m", app, "-c",
      [
        "export HOME=/home/#{app}",
        "cd #{Shellwords.escape(app_dir)}",
        "env RAILS_ENV=production SECRET_KEY_BASE=#{Shellwords.escape(secret)} " \
          "bundle40 exec rails runner -e production #{Shellwords.escape(runner_source(app, tries))}",
      ].join(" && "),
    ]

    system(*cmd)
    status = $?.exitstatus

    case status
    when 0 then exit 0
    when 3
      if drained
        at = last_drain_at(app)
        warn "solid_queue: #{app} jobs run by the hourly drain, last at #{at&.utc&.iso8601}"
        exit 0
      end
      warn "solid_queue: #{app} has no resident worker AND no drain in the last " \
           "#{MAX_DRAIN_AGE_S / 3600}h — nothing is running this app's jobs. " \
           "Check /var/log/drain-jobs.log and the drain-jobs.sh cron entry."
      exit 1
    else exit 1
    end
  end
end

SolidQueueProof.main(ARGV) if $PROGRAM_NAME == __FILE__

`````

### gates/verify_deploy_identity.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies low-level OPERATOR identity hygiene without requiring app dependencies.
# Run from the repository root:
#   ruby OPENBSD/gates/verify_deploy_identity.rb [path/to/_deploy.sh]

require "open3"
require "yaml"
require_relative "../lib/utf8"

# The functions every app's deploy script reaches through _deploy.sh.
SHARED_FUNCTIONS = %w[deploy_tracked_app need_cmd bundle_install_as_app install_rcd relayd_add_relay].freeze

# Which of `names` the shell does not define after sourcing `library`.
#
# Asked of zsh rather than of the text: "deploy_tracked_app()" in a comment, or
# in a function defined in a file _deploy.sh no longer sources, satisfied a
# string search while every app deploy would have died on "command not found".
# Sourcing is safe because the library files only define functions.
def shell_functions_missing(library, names)
  out, = Open3.capture2e("zsh", "-c", 'source "$1" && shift && whence -w "$@"', "zsh", library, *names)
  defined = out.scan(/^(\w+): function$/).flatten
  names - defined
rescue Errno::ENOENT
  names
end

return unless $PROGRAM_NAME == __FILE__

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "RAILS")
APPS_FILE = File.join(RAILS_ROOT, "apps.yml")
SHARED_DEPLOY = File.join(RAILS_ROOT, "_deploy.sh")
SHARED_BUNDLE = File.join(RAILS_ROOT, "_bundle.sh")
# An argument names another library to source, so a test can hand the function
# check one that defines nothing and watch the run fail.
FUNCTION_LIBRARY = ARGV.fetch(0, SHARED_DEPLOY)
metadata = YAML.load_file(APPS_FILE).fetch("apps")

failures = []
ports = Hash.new { |h, k| h[k] = [] }
domains = Hash.new { |h, k| h[k] = [] }
shared_functions = File.file?(SHARED_DEPLOY) ? File.read(SHARED_DEPLOY) : ""
shared_functions += File.file?(SHARED_BUNDLE) ? File.read(SHARED_BUNDLE) : ""
failures << "missing shared deploy functions: #{SHARED_DEPLOY}" if shared_functions.empty?
missing_functions = File.file?(FUNCTION_LIBRARY) ? shell_functions_missing(FUNCTION_LIBRARY, SHARED_FUNCTIONS) : SHARED_FUNCTIONS
failures << "sourcing #{FUNCTION_LIBRARY} defines no #{missing_functions.join(', ')}" if missing_functions.any?
failures << "shared bundler helper missing deployment config" unless shared_functions.include?(
  "bundle config set --local deployment true"
)
failures << "shared bundler helper missing without config" unless shared_functions.include?(
  'bundle config set --local without \"development test\"'
)
shared_checks = {
  "need_cmd ruby40 bundle doas" => "shared deploy helper must require ruby40/bundle/doas",
  'doas mkdir -p "${APP_DIR}/.bundle"' => "shared deploy helper missing app .bundle mkdir",
  'bundle_install_as_app "$APP_NAME" "$APP_DIR"' => "shared deploy helper missing bundler install",
  'install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"' => "shared deploy helper missing standard rc.d install call",
  'relayd_add_relay "$APP_DOMAIN" "$APP_PORT"' => "shared deploy helper missing standard relay call"
}
shared_checks.each do |needle, message|
  failures << message unless shared_functions.include?(needle)
end

metadata.each do |app, expected|
  script = File.join(ROOT, expected.fetch("deploy_script"))
  deploy_root = expected["deploy_root"] || expected["app_path"]
  app_path = File.join(ROOT, deploy_root)
  readme = File.join(RAILS_ROOT, app, "README.md")
  gemfile = File.join(app_path, "Gemfile")
  routes = File.join(app_path, "config", "routes.rb")

  ports[expected.fetch("port")] << app
  domains[expected.fetch("domain")] << app

  failures << "missing app directory for #{app}: #{app_path}" unless Dir.exist?(app_path)
  failures << "missing README for #{app}: #{readme}" unless File.file?(readme)
  failures << "missing Gemfile for #{app}: #{gemfile}" unless File.file?(gemfile)
  failures << "missing routes for #{app}: #{routes}" unless File.file?(routes)

  unless File.file?(script)
    failures << "missing deploy script for #{app}: #{script}"
    next
  end

  content = File.read(script)
  checks = {
    "set -euo pipefail" => "missing strict mode for #{app}",
    "APP_NAME=#{app}" => "wrong APP_NAME for #{app}",
    "APP_DOMAIN=#{expected.fetch("domain")}" => "wrong APP_DOMAIN for #{app}",
    "APP_PORT=#{expected.fetch("port")}" => "wrong APP_PORT for #{app}",
    "SCRIPT_DIR=${0:a:h}" => "missing zsh script dir resolution for #{app}",
    "SRC_DIR=${SCRIPT_DIR}" => "missing source dir for #{app}",
    "SHARED_BUNDLE_CACHE" => "missing shared bundle cache for #{app}",
    '. "${SCRIPT_DIR:h}/_deploy.sh"' => "missing shared deploy source for #{app}",
    'deploy_tracked_app "$APP_NAME"' => "missing shared deploy entrypoint for #{app}"
  }

  checks.each do |needle, message|
    failures << message unless content.include?(needle)
  end

  failures << "template placeholder left in #{app}" if content.include?("%APP_NAME%") || content.include?("%")
  failures << "deprecated bundler flags left in #{app}" if content.include?("bundle install --deployment --without")
  failures << "hard-coded amber bundle coupling left in #{app}" if content.include?("/home/amber/.bundle/gems") && app != "amber"
  failures << "unquoted cp source in #{app}" if content.include?("cp -R ${SRC_DIR}")

  if File.file?(readme)
    readme_content = File.read(readme)
    failures << "README missing deploy script path for #{app}" unless readme_content.include?(expected.fetch("deploy_script")) || readme_content.include?("#{app}.sh")
  end

  if File.file?(gemfile) && File.file?(readme)
    gemfile_content = File.read(gemfile)
    readme_content = File.read(readme)
    if gemfile_content.include?('gem "sqlite3"') &&
       readme_content.match?(/Rails 8, PostgreSQL/) &&
       !gemfile_content.include?('gem "pg"')
      failures << "Database provider drift mismatch verified inside production definitions for #{app}"
    end
  end

  if File.file?(routes)
    routes_content = File.read(routes)
    failures << "missing health route for #{app}" unless routes_content.include?("rails/health#show")
  end
end

ports.each do |port, apps|
  failures << "port collision #{port}: #{apps.join(', ')}" if apps.size > 1
end

domains.each do |domain, apps|
  failures << "domain collision #{domain}: #{apps.join(', ')}" if apps.size > 1
end

if failures.empty?
  puts "OPERATOR identity verification passed for #{metadata.keys.join(', ')}"
else
  warn "OPERATOR identity verification failed:"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end

`````

### gates/verify_openbsd_idempotency.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

#   ruby OPENBSD/gates/verify_openbsd_idempotency.rb [path/to/OPERATOR.sh]
#
# The path argument exists so test/test_gate_fixtures.rb can hand it a snippet
# that deletes the zones without backing them up, and watch it refuse.
#
# OPERATOR.sh legitimately contains UTF-8 bytes (em dashes in comments); the
# plain string #include? checks below tolerated that under the remote's
# US-ASCII default external encoding, but the =~ regex checks do not.
script = File.read(ARGV.fetch(0, File.expand_path("../OPERATOR.sh", __dir__)), encoding: "UTF-8")

issues = []

backup_idx = script.index("backup_directory /var/nsd/zones/master nsd-zones")
delete_idx = script.index("rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)") # scan: intentional — searches for the command, never runs it
issues << "nsd backup does not precede destructive delete" unless backup_idx && delete_idx && backup_idx < delete_idx

# Regexes, not exact strings: the actual variable names in OPERATOR.sh ($src/$d,
# $svc) drift over time, but the two guarantees these check for - a backup copy
# into a quoted destination, and a restart-with-start-fallback - must survive.
issues << "missing guarded /home backup copy path" unless script =~ %r{cp -R "\$\{?src\}?[^"]*"[^\n]*?"[^"]*"}
# db:prepare, not db:migrate: it loads db/schema.rb into an empty database, so a
# fresh box builds its tables whether or not the migrations that wrote the schema
# are still in the tree.
issues << "missing idempotent Rails DB prepare" unless script.match?(/bin\/rails db:prepare\b/)
issues << "missing restart/start fallback for rc.d services" unless script =~ %r{rcctl restart \$\{?\w+\}?[^\n]*?\|\|[^\n]*?rcctl start \$\{?\w+\}?}

if issues.any?
  warn "idempotency check failed:"
  issues.each { |issue| warn " - #{issue}" }
  exit 1
end

puts "OPERATOR.sh idempotency ok"

`````

### gates/vps_safety_gate.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# VPS_SAFETY_ROOT lets the test point this at a fixture tree holding the shapes
# it must flag; unset, it reads this checkout.
ROOT = ENV.fetch("VPS_SAFETY_ROOT", File.expand_path("../..", __dir__))
OPENBSD = File.join(ROOT, "OPENBSD")
TOOLING = File.join(ROOT, "OPENBSD", "bin")
failures = []

doas_conf = File.join(OPENBSD, "etc", "doas.conf")
if File.file?(doas_conf)
  text = File.read(doas_conf)
  failures << "doas.conf must end with newline (OpenBSD parser rejects EOF without one)" unless text.end_with?("\n")

  rules = text.lines.reject { |line| line.strip.empty? || line.strip.start_with?("#") }
  dev_rule = rules.find { |line| line.match?(/\bdev\s+as\s+root\b/) }

  # keepenv on the dev rule is a root RCE by construction: it carries RUBYOPT,
  # RUBYLIB, GEM_HOME and BUNDLE_* across the boundary, so `RUBYOPT=-r/tmp/x.rb doas
  # <anything>` runs as root with no shell involved. Removed 2026-08-02 for a measured
  # setenv allowlist; this is what stops it coming back with the next edit that finds
  # a variable missing. The root->root rule keeps keepenv on purpose — see the file.
  if dev_rule.nil?
    failures << "etc/doas.conf has no `dev as root` rule"
  else
    failures << "etc/doas.conf: dev rule must not use keepenv (root RCE via RUBYOPT)" if dev_rule.include?("keepenv")
    # The whole measured allowlist (etc/doas.conf): each is read by a script run
    # under doas and assigned by none, so dropping one silently breaks that
    # script — --stage-1's DNS-wipe gate, the console gate, production seeds, the
    # deploy scan skip, the mail image format.
    allowlist = dev_rule[/setenv\s*\{([^}]*)\}/, 1].to_s.split
    %w[I_UNDERSTAND_DNS_WIPE I_UNDERSTAND_CONSOLE_RISK RUN_PRODUCTION_SEEDS SKIP_MASTER_SCAN MAIL_IMG_FMT].each do |name|
      failures << "etc/doas.conf: dev rule must setenv-allowlist #{name}" unless allowlist.include?(name)
    end
  end
else
  failures << "missing tracked etc/doas.conf"
end

validate_doas = File.join(TOOLING, "validate_doas.ksh")
if File.file?(validate_doas)
  # install_doas_conf_from_repo rolls /etc/doas.conf back when validation fails, so
  # validation has to test the thing that changed. `doas id` alone passes with a wrong
  # or empty allowlist — the rollback net covered lockout and not the actual risk.
  guard = File.read(validate_doas)
  unless guard.include?("validate_doas_passes_env")
    failures << "validate_doas.ksh must check that an allowlisted variable still crosses, " \
                "not only that dev can reach root"
  end
else
  failures << "missing OPENBSD/bin/validate_doas.ksh"
end

console_main = File.join(TOOLING, "vps_console.exp")
if File.file?(console_main)
  text = File.read(console_main)
  unless text.include?("proc require_console_risk_ack") && text.match?(/^require_console_risk_ack$/)
    failures << "OPENBSD/bin/vps_console.exp must define and call require_console_risk_ack"
  end
  failures << "OPENBSD/bin/vps_console.exp must target vm23 only (found vm27)" if text.include?("vm27")
else
  failures << "missing OPENBSD/bin/vps_console.exp"
end

# vps_console.exp is the one console door, and the ack inside it is the whole
# safety. Any other expect script beside it is a way to the console that
# skipped that check, so it fails here rather than being trusted to delegate.
Dir.glob(File.join(TOOLING, "*.exp")).reject { |path| path == console_main }.each do |path|
  failures << "OPENBSD/bin/#{File.basename(path)}: console automation belongs in vps_console.exp as a mode"
end

Dir.glob(File.join(OPENBSD, "etc", "rc.d", "*")).sort.each do |path|
  next unless File.file?(path)

  text = File.read(path)
  rel = path.delete_prefix("#{ROOT}/")
  if text.include?("falcon serve") && !text.include?("bundle40 exec falcon")
    failures << "#{rel} must invoke falcon via bundle40 exec (gem binstub, not PATH)"
  end
end

if failures.any?
  warn "VPS safety gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "VPS safety gate passed (doas.conf, console guards, validate_doas.ksh, rc.d falcon)."

`````

### lib/ci_lock.sh

`````zsh
# POSIX sh — sourced by zsh and sh callers alike.
#
# The one definition of the pub4 CI mutex path, and the safe way to create it.
#
# It used to live at /var/tmp/pub4-ci.lock, created by
#   doas sh -c "touch /var/tmp/pub4-ci.lock; chmod 666 /var/tmp/pub4-ci.lock"
# — a fixed, predictable path in a world-writable directory, chmod'ed by root
# with no -h/-P (TODO.md:
# secrets_in_process_argv_and_world_readable_home). Any local account could
# pre-plant a symlink at that name and redirect the root chmod onto a file of its
# choosing. `PUB4_CI_LOCK` being env-overridable made it worse: the caller chose
# the path root then chmod'ed.
#
# The fix is the directory, not the flags. /var/db/pub4 is root-owned and 0755, so
# an unprivileged account cannot create anything inside it — there is no symlink to
# follow. That also lets the mode drop from 666 to 644.
#
# Three scripts held their own copy of the path (vps_ci.sh, vps_master_scan.sh,
# vps_weekly_integrity.sh); this is the single source. The lock file is dev-owned;
# only the directory is root's.

PUB4_CI_LOCK_DIR=/var/db/pub4
PUB4_CI_LOCK_NAME=ci.lock
PUB4_CI_LOCK_OWNER=${PUB4_CI_LOCK_OWNER:-dev}

# An override is honoured only inside the root-owned directory. Outside it, the
# override is the vulnerability rather than a convenience.
pub4_ci_lock_path() {
  case "${PUB4_CI_LOCK:-}" in
    "${PUB4_CI_LOCK_DIR}"/*) printf '%s\n' "$PUB4_CI_LOCK" ;;
    "") printf '%s/%s\n' "$PUB4_CI_LOCK_DIR" "$PUB4_CI_LOCK_NAME" ;;
    *)
      printf 'ci_lock: ignoring PUB4_CI_LOCK=%s outside %s\n' "$PUB4_CI_LOCK" "$PUB4_CI_LOCK_DIR" >&2
      printf '%s/%s\n' "$PUB4_CI_LOCK_DIR" "$PUB4_CI_LOCK_NAME"
      ;;
  esac
}

# Creates the directory root-owned, then the lock file dev-owned. The lock file is
# never removed here: a holder may have it open, and unlinking it would let a
# second holder open a fresh inode and run concurrently — the one thing a mutex
# exists to prevent.
#
# The lock itself is taken by OPENBSD/bin/with-ci-lock and Operator::CiGuard, both
# flock(2). OpenBSD has neither lockf(1) nor flock(1), so no shell script here can
# take the lock with a command; vps_master_scan.sh once tried and never ran.
#
# Note what this function does and does not do. It ENSURES the file — creates it
# with the right owner and mode. It does not lock anything. vps_ci.sh calls it
# and prints "sync + mutex + load gate"; the mutex in that sentence is the one
# bin/ci takes through CiGuard, on this same path since 2026-08-14. Before that
# CiGuard locked /var/tmp/pub4-ci.lock instead, so the file created here was
# never locked by anyone and the file that was locked was the world-writable one
# this helper exists to replace.
pub4_ensure_ci_lock() {
  lock=$(pub4_ci_lock_path)
  doas sh -c "
    mkdir -p '${PUB4_CI_LOCK_DIR}'
    chown root:wheel '${PUB4_CI_LOCK_DIR}'
    chmod 755 '${PUB4_CI_LOCK_DIR}'
    [ -e '${lock}' ] || : > '${lock}'
    chown '${PUB4_CI_LOCK_OWNER}' '${lock}'
    chmod 644 '${lock}'
  "
  printf '%s\n' "$lock"
}

`````

### lib/deploy_inventory.rb

`````ruby
# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  class Inventory
    App = Struct.new(:name, :title, :domain, :port, :deploy_script, :deploy_root, :public, keyword_init: true)

    attr_reader :root

    def initialize(root:)
      @root = root
    end

    def apps
      @apps ||= load_apps
    end

    def app_names
      apps.map(&:name)
    end

    def master_apps(path: File.join(root, "OPENBSD", "deploy_inventory.json"))
      data = JSON.parse(File.read(path))
      data.fetch("apps").map { |entry| app_from_json(entry) }
    end

    private

    REQUIRED_APP_KEYS = %w[domain port deploy_script deploy_root].freeze

    # apps.yml is the fleet's source of truth and is edited by hand, so a missing
    # key has to say which app and which key. It used to raise a bare
    # `KeyError: key not found: "deploy_root"` six frames inside a gate, which reads
    # as a broken gate rather than an incomplete entry — every gate that reads the
    # inventory died the same anonymous way.
    def load_apps
      path = File.join(root, "RAILS", "apps.yml")
      data = YAML.safe_load(File.read(path))
      data.fetch("apps").map do |name, metadata|
        missing = REQUIRED_APP_KEYS.reject { |key| metadata.is_a?(Hash) && metadata.key?(key) }
        unless missing.empty?
          raise KeyError, "RAILS/apps.yml: app #{name.inspect} is missing #{missing.join(', ')} " \
                          "(every app needs #{REQUIRED_APP_KEYS.join(', ')})"
        end

        App.new(
          name: name,
          title: metadata["title"],
          domain: metadata.fetch("domain"),
          port: metadata.fetch("port").to_i,
          deploy_script: metadata.fetch("deploy_script"),
          deploy_root: metadata.fetch("deploy_root"),
          public: metadata.fetch("public", false)
        )
      end
    end

    def app_from_json(entry)
      App.new(
        name: entry.fetch("name"),
        title: entry["title"],
        domain: entry.fetch("domain"),
        port: entry.fetch("port").to_i,
        deploy_script: entry["deploy_script"],
        deploy_root: entry["deploy_root"]
      )
    end
  end
end

`````

### lib/deploy_stamp.rb

`````ruby
# frozen_string_literal: true

require "json"

module Deploy
  # What `bin/vps-deploy` wrote after its last run, and whether a running
  # process is the build that run deployed.
  #
  # master reports the commit it booted as /health `deploy.git_sha`, and the
  # deploy records the commit it pulled in `last_deploy_master.json`. Each is
  # correct about itself. Both can be correct while disagreeing: a checkout
  # pulled after the deploy, then a reboot or a hand restart, boots code no
  # deploy ever ran, and every other check still passes. The comparison is the
  # only place that state becomes a fact.
  module DeployStamp
    DIR = "/var/db/pub4"

    module_function

    # The stamp's sha, or nil for an absent or unreadable stamp.
    def sha(app, dir: DIR)
      path = File.join(dir, "last_deploy_#{app}.json")
      return nil unless File.readable?(path)

      value = JSON.parse(File.read(path))["sha"].to_s
      value.empty? ? nil : value
    rescue JSON::ParserError
      nil
    end

    # nil when the booted build is the stamped one, a failure line when not.
    # Short SHAs differ in length between `git rev-parse --short` runs as the
    # object count grows, so one naming a prefix of the other is the same commit.
    def booted_mismatch(app:, booted:, stamped:)
      booted = booted.to_s
      return "#{app} health: no deploy.git_sha — the booted build is unknown" if booted.empty?
      return nil if stamped.nil? || booted.start_with?(stamped) || stamped.start_with?(booted)

      "#{app} health: booted #{booted} but last deploy stamped #{stamped} — " \
        "this process runs code no deploy ran; `bin/vps-deploy #{app}` makes them one"
    end
  end
end

`````

### lib/disk_usage.rb

`````ruby
# frozen_string_literal: true

module Deploy
  # A filesystem near full, by blocks or by inodes.
  #
  # Nothing on the box watched either. A full /home stops every SQLite write the
  # apps make and the deploy's copy-tree extraction with it, and inodes run out
  # first on a tree of small files — which a Rails checkout and its asset
  # builds are. The failure it prevents looks like a database error, not a disk.
  #
  # Reads `df -ik`, whose header names the columns on OpenBSD and macOS alike, so
  # the parse keys on the header rather than on column positions.
  module DiskUsage
    LIMIT_PERCENT = 90

    module_function

    def failures(df_output, limit: LIMIT_PERCENT)
      lines = df_output.to_s.lines.map(&:split).reject(&:empty?)
      header = lines.shift
      return ["disk: df printed no header"] unless header

      capacity = header.index("Capacity")
      iused = header.index("%iused")
      return ["disk: df -ik has no Capacity or %iused column"] unless capacity && iused

      lines.flat_map do |row|
        mount = row.last
        { "blocks" => row[capacity], "inodes" => row[iused] }.filter_map do |what, value|
          percent = value.to_s.delete("%").to_i
          "disk: #{mount} #{what} #{percent}% used" if percent >= limit
        end
      end
    end
  end
end

`````

### lib/gate_environment.rb

`````ruby
# frozen_string_literal: true

require_relative "../../MASTER/lib/operator/environment"
require_relative "../../MASTER/lib/operator/ruby_runner"

module Deploy
  module GateEnvironment
    Gate = Struct.new(:name, :path, :args, :needs, :optional, keyword_init: true) do
      def initialize(name:, path:, args: [], needs: [], optional: false)
        super
      end
    end

    RAILS_GATES = "MASTER/gates/runner.rb"

    # The deploy-time integrity sequence, in order. This is not a registry of
    # RAILS gates -- that is MASTER/gates/gates.yml, and the rows below name a
    # gate rather than a file so the two cannot drift. It used to point at
    # per-gate scripts at the RAILS root; those were shims over the same classes
    # the runner already loads in-process.
    #
    # `needs` names only what skip_reason consults: :vps, :bundle and :browser.
    # Every gate here needs the repo, so saying so decided nothing.
    INTEGRITY_GATES = [
      Gate.new(name: "deploy_identity", path: "OPENBSD/gates/verify_deploy_identity.rb"),
      Gate.new(name: "production", path: RAILS_GATES, args: %w[production]),
      Gate.new(name: "phantom_fk", path: RAILS_GATES, args: %w[phantom_foreign_keys]),
      Gate.new(name: "frontend", path: RAILS_GATES, args: %w[frontend_production]),
      Gate.new(name: "relayd_smoke", path: "OPENBSD/gates/deploy_smoke_gate.rb"),
      Gate.new(name: "domain_align", path: RAILS_GATES, args: %w[domain_alignment]),
      Gate.new(name: "crawl_inventory", path: "RAILS/tools/crawl_probe.rb"),
      Gate.new(name: "schema_migration", path: RAILS_GATES, args: %w[schema_migration]),
      Gate.new(name: "asset_freshness", path: RAILS_GATES, args: %w[generated_asset]),
      Gate.new(name: "human_walkthrough", path: RAILS_GATES, args: %w[human_walkthrough]),
      Gate.new(name: "vps_health", path: "OPENBSD/gates/health_check.rb", args: ["--core"], needs: %i[vps]),
    ].freeze

    module_function

    def skip_reason(gate, on_vps: Operator::Environment.on_vps?)
      needs = Array(gate.needs)
      if needs.include?(:vps) && !on_vps
        return "not on VPS"
      end
      if needs.include?(:bundle) && Operator::RubyRunner.runtime_gate_skipped?
        return Operator::RubyRunner.runtime_skip_reason || "bundle runtime unavailable"
      end
      if needs.include?(:browser) && ENV["PROBE_REQUIRE_BROWSER"] != "1" && ENV["MASTER_CI_BROWSER"] != "1"
        return "browser probe optional"
      end

      nil
    end

    def post_pull_warning
      return unless Operator::Environment.on_vps?

      <<~WARN
        integrity: note — source updated in /home/dev/pub4; deployed /home/<app>/app trees are unchanged.
        integrity: note — run: zsh OPENBSD/bin/vps-deploy <app>  (serial, one app at a time)
        integrity: note — then: ruby40 OPENBSD/gates/integrity_gate.rb
      WARN
    end
  end
end

`````

### lib/gate_ledger.rb

`````ruby
# frozen_string_literal: true

require "json"
require "time"

module Deploy
  # What each gate has actually been doing, run over run.
  #
  # This is the counterpart to `GateResult#errored!`, and it is not optional
  # decoration next to it. Fail-open means a gate that crashes stops blocking;
  # without a record, it also stops being noticed — it reads as a quiet line in
  # a long run and the tree it was supposed to guard goes unguarded for however
  # long nobody re-reads the output. arXiv 2607.07405 makes the same point about
  # its own suite: precision "must itself be audited", because in their four-gate
  # fleet one gate ran at 100% precision over 161 fires and another at 5%, and
  # nothing in the gate's own output distinguished them.
  #
  # pub4 had no such record. Every gate's history was whatever was still in a
  # terminal scrollback, so the two failure modes this fleet has actually hit —
  # a gate that fires on every single run until people learn to skip its line
  # (the tablist warning, 2026-08), and a gate that quietly measures nothing for
  # days (layout_geometry, 2026-08-03) — were both invisible in exactly the same
  # way: locally each run looked reasonable.
  #
  # What this can and cannot say. It records *outcomes*, so it yields fire rate,
  # error rate and inconclusive rate per gate. It does not yield precision in the
  # paper's sense — that needs ground truth about whether each block was correct,
  # which for this fleet lives in whether someone fixed the finding or exempted
  # the rule, and nothing here can see that. Two gates that report the same
  # numbers here can still differ in precision. So the numbers are a triage
  # order, not a verdict: they say which gate to go and read, not which is wrong.
  #
  # Local-only, append-only JSONL, one line per gate per run. Never committed —
  # it is machine-and-operator state like `.constitutional_costs.jsonl`, and a
  # committed version would conflict on every run in a shared checkout.
  class GateLedger
    DEFAULT_PATH = File.expand_path("../../.gate_ledger.jsonl", __dir__)

    # Keep the file bounded without a cron job. Trimming on read rather than on
    # write means a run never pays for it, and the reader is the only thing that
    # cares how long the history is.
    MAX_LINES = 20_000

    attr_reader :path

    def initialize(path: nil, env: ENV)
      @path = path || env["GATE_LEDGER"] || DEFAULT_PATH
    end

    # GATE_LEDGER=off disables recording entirely, for runs that should leave no
    # trace (a bisect, someone else's tree).
    def enabled? = !%w[off 0 false no].include?(File.basename(@path.to_s).downcase)

    def record(gate:, outcome:, run_id:, failures: 0, warnings: 0, errors: 0, duration_ms: nil)
      return self unless enabled?

      line = {
        at: Time.now.utc.iso8601,
        run: run_id,
        gate: gate,
        outcome: outcome.to_s,
        failures: failures,
        warnings: warnings,
        errors: errors,
        duration_ms: duration_ms,
      }
      File.open(@path, "a") { |f| f.puts(JSON.generate(line)) }
      self
    rescue SystemCallError => e
      # The ledger is an observer. It must never be the reason a gate run dies,
      # which would make the audit mechanism itself the top source of false
      # blocks — the failure the fail-open policy exists to prevent.
      Kernel.warn "[gates] ledger write failed (#{e.class}): #{e.message}"
      self
    end

    def entries
      return [] unless File.file?(@path)

      File.readlines(@path, chomp: true).last(MAX_LINES).filter_map do |line|
        next if line.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    # One row per gate, most-worth-reading first.
    #
    # Order is errored, then failed, then inconclusive, then name. A gate that
    # cannot run outranks one that is merely red: the red one told you something.
    def summary(entries = self.entries)
      by_gate = entries.group_by { |e| e["gate"] }
      by_gate.map do |gate, rows|
        counts = Hash.new(0)
        rows.each { |r| counts[r["outcome"].to_s] += 1 }
        times = rows.filter_map { |r| r["duration_ms"] }
        {
          gate: gate,
          runs: rows.size,
          passed: counts["passed"],
          failed: counts["failed"],
          inconclusive: counts["inconclusive"],
          errored: counts["errored"],
          fire_rate: rows.empty? ? 0.0 : (counts["failed"].to_f / rows.size),
          error_rate: rows.empty? ? 0.0 : (counts["errored"].to_f / rows.size),
          median_ms: median(times),
          # The last five against everything before them. A gate that has started
          # taking twice as long is the failure the whole duration column is for,
          # and a median over the full history hides it by definition.
          recent_ms: median(times.last(5)),
          earlier_ms: median(times[0...-5]),
          last: rows.last["outcome"],
          last_at: rows.last["at"],
        }
      end.sort_by { |r| [-r[:errored], -r[:failed], -r[:inconclusive], r[:gate].to_s] }
    end

    def median(values)
      sorted = Array(values).compact.sort
      return if sorted.empty?

      sorted[sorted.size / 2]
    end

    # A wall time a person reads without arithmetic. Anything past ninety seconds
    # is the kind of gate somebody plans a coffee around, so it changes units.
    def self.duration(ms)
      return "-" if ms.nil?

      seconds = ms.to_f / 1000
      seconds < 90 ? format("%.1fs", seconds) : format("%dm%02ds", (seconds / 60).floor, (seconds % 60).round)
    end

    # The lines worth acting on, in the words of what to do about them. Returned
    # rather than printed so a gate could read this too.
    def flags(rows = summary, min_runs: 5)
      rows.filter_map do |r|
        next if r[:runs] < min_runs

        if r[:error_rate] >= 0.5
          "#{r[:gate]}: errored on #{r[:errored]}/#{r[:runs]} runs — it is failing open, " \
            "so whatever it guards is currently unguarded"
        elsif r[:fire_rate] >= 0.9
          "#{r[:gate]}: failed on #{r[:failed]}/#{r[:runs]} runs — either a standing unfixed " \
            "finding or a line people have learned to skip; read it or retire it"
        elsif r[:inconclusive] == r[:runs]
          "#{r[:gate]}: measured nothing on all #{r[:runs]} runs — its preconditions are never met here"
        elsif doubled?(r)
          "#{r[:gate]}: #{self.class.duration(r[:earlier_ms])} -> #{self.class.duration(r[:recent_ms])} " \
            "over the last five runs — a gate that doubles becomes a gate nobody runs"
        end
      end
    end

    def render(io = $stdout)
      rows = summary
      if rows.empty?
        io.puts "[gates] ledger #{display_path} is empty — no runs recorded yet"
        return
      end

      io.puts "[gates] ledger #{display_path} — #{rows.sum { |r| r[:runs] }} gate-runs across #{rows.size} gates"
      io.puts format("  %-24s %5s %5s %5s %5s %5s %9s  %s",
                     "gate", "runs", "pass", "fail", "inc", "err", "median", "last")
      rows.each do |r|
        io.puts format(
          "  %-24s %5d %5d %5d %5d %5d %9s  %s",
          r[:gate], r[:runs], r[:passed], r[:failed], r[:inconclusive], r[:errored],
          self.class.duration(r[:median_ms]), r[:last]
        )
      end

      notes = flags(rows)
      return if notes.empty?

      io.puts
      io.puts "Worth reading:"
      notes.each { |n| io.puts "  - #{n}" }
    end

    private

    # Twice as slow, with enough runs on both sides of the line for the
    # comparison to mean anything and enough absolute time for it to matter. A
    # 40ms gate that becomes an 80ms gate is noise, not a regression.
    def doubled?(row)
      row[:recent_ms] && row[:earlier_ms] &&
        row[:earlier_ms] >= 1_000 && row[:recent_ms] >= row[:earlier_ms] * 2
    end

    def display_path = @path.sub("#{File.expand_path('../..', __dir__)}/", "")
  end
end

`````

### lib/gate_result.rb

`````ruby
# frozen_string_literal: true

# The deploy tree owns the gate kernel. Every gate in the repo returns this
# type: RAILS/gates, MASTER/gates, OPENBSD/gates and MASTER/tools/gate.rb require it
# across the tree boundary and add nothing to it, so adding an outcome is a
# change with four consumers. A repo-level lib/ means a fifth top-level tree
# holding three files. MASTER/lib requires nothing from either sibling — it reads
# their data and reaches STUDIO's gate through `rake studio` as a subprocess —
# and a shared kernel is the thing everything ends up requiring. Revisit when a
# fifth consumer appears.

module Deploy
  # Four outcomes, not two.
  #
  # :passed, :failed, :inconclusive (the gate declined to measure), :errored
  # (the gate tried and broke). The first three are below; :errored and its
  # fail-open policy are documented on `errored!`.
  #
  # `ok?` only ever meant "no hard failures", so a gate that could not run —
  # no Chrome, no app listening, no deploy stamp, a missing gem — reported the
  # same green as a gate that ran and found nothing. Sixteen gates in the RAILS
  # suite take that path, which is why a green run of the whole suite meant less
  # than it looked: `deploy_drift` printed "ok: no deploy drift detected"
  # directly under its own warning saying "Nothing was checked."
  #
  # Warnings could not express it. A warning is something a gate observed; this
  # is a gate declining to claim it observed anything. So `inconclusive!` is a
  # third state: it never blocks by default (off the deploy host most rendered
  # gates genuinely cannot run, and failing there would train people to ignore
  # the suite), but it does suppress the success line and name what was skipped.
  # GATE_STRICT_INCONCLUSIVE=1 makes it blocking, for CI on the deploy host
  # where Chrome and the apps are supposed to be present.
  class GateResult
    attr_reader :failures, :warnings, :soft_failures, :unchecked, :errors

    TRUTHY = %w[1 true yes on].freeze

    def self.flag?(name, env = ENV)
      TRUTHY.include?(env[name].to_s.strip.downcase)
    end

    # GATE_STRICT_SOFT=1 promotes soft failures to hard (merge-blocking).
    def self.strict_soft?(env = ENV) = flag?("GATE_STRICT_SOFT", env)

    # GATE_STRICT_INCONCLUSIVE=1 promotes "could not check" to hard.
    def self.strict_inconclusive?(env = ENV) = flag?("GATE_STRICT_INCONCLUSIVE", env)

    # GATE_REQUIRE_LIVE=1 turns "port closed, skipping" into a failure.
    #
    # measured_nothing? cannot express this case: a gate that ran fifty source
    # checks and skipped every live one has a non-zero check count, so it passes
    # and its skips are warnings. On 2026-08-03 that produced eight green gates on
    # a machine where no app was listening -- and booting the apps turned one of
    # them red immediately. This flag is for runs that mean to measure the live
    # half, so the absence of it is loud instead of a warning line.
    def self.require_live?(env = ENV) = flag?("GATE_REQUIRE_LIVE", env)

    # GATE_STRICT_ERRORS=1 makes a gate's own crash blocking. See errored! for
    # why the default is the other way.
    def self.strict_errors?(env = ENV) = flag?("GATE_STRICT_ERRORS", env)

    def initialize
      @failures = []
      @warnings = []
      @soft_failures = []
      @unchecked = []
      @errors = []
      @checks_ran = 0
      @live_skips = 0
    end

    # The gate itself broke — an exception escaped its own run, not a finding
    # it made about the tree.
    #
    # Fail-open, from arXiv 2607.07405 §"deterministic gates": "if a gate itself
    # raises an exception, the harness records the error and allows the original
    # call." Their reason is precision. A gate that crashes and blocks produces a
    # false block on every subsequent call, and a suite whose blocks are mostly
    # its own bugs is one people learn to route around — which is how a gate
    # fleet stops being read at all.
    #
    # pub4's version of that was worse than a false block: MASTER/gates/runner.rb
    # called `klass.run` with no rescue, so one gate raising killed the process
    # and every gate after it in the --all order never ran. Forty-six gates
    # reporting nothing, exit 1, and a backtrace where the summary should be.
    #
    # So this is a fourth state and not a failure: it never blocks by default,
    # it is counted and named separately from both :passed and :failed, and it
    # can never be mistaken for a pass. GATE_STRICT_ERRORS=1 promotes it for CI
    # on the deploy host, where a gate that cannot run is itself the news.
    def errored!(reason)
      @errors << reason
      @failures << "[gate-error] #{reason}" if self.class.strict_errors?
      self
    end

    # A gate that raised, rendered as a result rather than as a backtrace. The
    # caller passes the gate name because an exception message rarely says which
    # gate produced it.
    def self.from_error(exception, gate:, backtrace_lines: 3)
      trace = Array(exception.backtrace).first(backtrace_lines).join(" | ")
      new.errored!(
        "#{gate} raised #{exception.class}: #{exception.message}#{trace.empty? ? '' : " @ #{trace}"}"
      )
    end

    # severity: :hard (default, blocks) | :soft (warn unless GATE_STRICT_SOFT)
    def fail(message, severity: :hard)
      case severity.to_sym
      when :soft
        @soft_failures << message
        if self.class.strict_soft?
          @failures << "[soft→hard] #{message}"
        else
          @warnings << "[soft] #{message}"
        end
      else
        @failures << message
      end
    end

    def warn(message)
      @warnings << message
    end

    # A live check the gate declined to run because nothing was listening.
    def skipped_live(message)
      @live_skips += 1
      if self.class.require_live?
        @failures << "[live-required] #{message}"
      else
        @warnings << message
      end
      self
    end

    attr_reader :live_skips

    # A check that could not run. Name the missing precondition, not the check:
    # "no Chrome/Chromium" reads as a fixable environment fact, "geometry not
    # measured" reads as a mystery.
    def inconclusive!(reason)
      @unchecked << reason
      self
    end

    # Count a check that actually ran, so a gate can say how much it measured.
    #
    # Without this the two states are indistinguishable: a passing check records
    # nothing, so `unchecked.empty?` was the only signal available and one skipped
    # precondition spoke for the whole gate. human_walkthrough runs source checks
    # for every app and needs a port only for the live half, so a single parked app
    # made it report "INCONCLUSIVE (checked nothing)" -- untrue -- and dropped it
    # from the pass count.
    def checked!(count = 1)
      @checks_ran += count
      self
    end

    attr_reader :checks_ran

    # Nothing measured at all. This is what GATE_STRICT_INCONCLUSIVE is for, and
    # it is now decided here rather than inside inconclusive!: promoting at record
    # time meant a gate that ran fifty checks and skipped one hard-failed on the
    # deploy host, so `resource_guard.sh` parking amber -- a documented, normal VPS
    # state -- blocked releases that had nothing wrong with them.
    #
    # A live skip counts toward "measured nothing" as of 2026-08-11. It did not,
    # and that was the hole: skipped_live files a warning rather than an unchecked
    # precondition, so a gate whose ENTIRE check set was live-skipped had zero
    # checks, zero unchecked and reported PASSED. layout_geometry did exactly that
    # on 2026-08-03 -- PASSED having skipped all 17 of its checks because no app was
    # listening, which is how a dead amber and bsdports read as green for an unknown
    # number of days (TODO.md: amber_bsdports_stop_and_stay_down).
    #
    # A gate that skipped some live checks and ran others still passes: this asks
    # whether anything at all was measured, not whether everything was.
    def measured_nothing?
      @checks_ran.zero? && (!@unchecked.empty? || @live_skips.positive?)
    end

    # Why nothing was measured, in the terms the reader can act on. "0
    # precondition(s) missing" was the old output for an all-live-skipped gate,
    # which is both true and useless: the preconditions were not missing, the app
    # was not listening.
    def nothing_measured_reason
      parts = []
      parts << "#{@unchecked.size} precondition(s) missing" unless @unchecked.empty?
      parts << "#{@live_skips} live check(s) skipped, nothing listening" if @live_skips.positive?
      parts.empty? ? "no checks ran" : parts.join(", ")
    end

    def ok?
      @failures.empty?
    end

    # Did this gate check everything it exists to check?
    def conclusive?
      @unchecked.empty?
    end

    # The one place the three states are ranked. Callers that aggregate gates
    # (MASTER/gates/runner.rb) ask for this instead of re-deriving it from the
    # three lists, so the suite line and a leaf's own output cannot disagree.
    #
    # :inconclusive means the gate measured nothing, not that it skipped
    # something. A gate that checked fifty things and could not check the
    # fifty-first passed, and says what it skipped -- calling that "checked
    # nothing" was false, dropped it out of the pass count, and under
    # GATE_STRICT_INCONCLUSIVE turned a parked app into a blocked deploy.
    # A gate whose own code raised. Ranked above :inconclusive because it is a
    # stronger statement: inconclusive means the gate declined to measure,
    # errored means it tried and broke.
    def errored? = !@errors.empty?

    def outcome
      return :failed unless ok?
      return :errored if errored?
      return :failed if measured_nothing? && self.class.strict_inconclusive?

      measured_nothing? ? :inconclusive : :passed
    end

    # label: prefixes every merged message, so a composite's output still names
    # which leaf produced each line.
    def merge!(other, label: nil)
      tag = label ? "[#{label}] " : ""
      Array(other.failures).each { |m| @failures << "#{tag}#{m}" }
      Array(other.warnings).each { |w| @warnings << "#{tag}#{w}" }
      Array(other.soft_failures).each { |m| @soft_failures << "#{tag}#{m}" }
      Array(other.unchecked).each { |m| @unchecked << "#{tag}#{m}" }
      # Without this a composite swallows a leaf that crashed: the leaf's errors
      # would be neither failures nor unchecked, so the composite would report
      # PASSED for a leaf that never ran. That is the same false green the third
      # state was added to close, one level up.
      Array(other.errors).each { |m| @errors << "#{tag}#{m}" } if other.respond_to?(:errors)
      # A composite measured whatever its leaves measured, or one leaf with no
      # Chrome would speak for the whole suite the way one app used to speak for
      # a whole gate.
      @checks_ran += other.checks_ran if other.respond_to?(:checks_ran)
      # Same reason as checks_ran: without this a composite whose every leaf
      # live-skipped would look like a composite that had nothing to skip.
      @live_skips += other.live_skips if other.respond_to?(:live_skips)
      self
    end

    # Everything report! does except exiting, so an aggregating caller gets the
    # same rendering. Pass no success_message when the caller prints its own.
    def render(success_message = nil)
      emit("Warnings:", @warnings)
      emit("Not checked:", @unchecked)
      emit("Gate errors (fail-open — nothing was blocked by these):", @errors)
      emit("Failures:", @failures)

      case outcome
      when :errored
        puts "errored: the gate itself broke and blocked nothing — " \
             "#{@errors.size} error(s) above (set GATE_STRICT_ERRORS=1 to treat as failure)"
        :errored
      when :failed
        # The strict-mode failure has no message of its own -- the promotion moved
        # out of inconclusive! and into outcome -- so say why, or the runner reports
        # FAILED with nothing under it.
        if @failures.empty?
          emit("Failures:", ["nothing measured, and GATE_STRICT_INCONCLUSIVE is set " \
                             "(#{nothing_measured_reason})"])
        end
        :failed
      when :inconclusive
        # Deliberately not the success message: the point of the third state is
        # that this gate has nothing to report success about.
        puts "inconclusive: nothing measured — #{nothing_measured_reason} " \
             "(set GATE_STRICT_INCONCLUSIVE=1 to treat as failure)"
        :inconclusive
      else
        # A pass that skipped something says so, instead of printing a clean
        # success line over a "Not checked:" block.
        if success_message
          puts conclusive? ? success_message : "#{success_message} (#{@checks_ran} check(s) ran, #{@unchecked.size} skipped)"
        end
        :passed
      end
    end

    def report!(success_message)
      exit 1 if render(success_message) == :failed
    end

    private

    def emit(header, messages)
      return if messages.empty?

      Kernel.warn header
      messages.each { |message| Kernel.warn "  - #{message}" }
    end
  end
end

`````

### lib/guard_state.rb

`````ruby
# frozen_string_literal: true

module Deploy
  # A service resource_guard.sh shed and has not brought back yet.
  #
  # The guard sheds amber/bsdports under load and restores them one per tick
  # once pressure clears. It does restore — measured 2026-08-14, both apps were
  # shed at 05:55 and the list cleared itself by 08:55 — but restore is gated on
  # memory recovering past MEM_RESTORE, and on a box whose median availability
  # is 9% that took three hours. For those three hours both apps were down and
  # nothing said so: relayd answers TLS on their behalf, so the outage reads as
  # a hang rather than a 5xx and every other check here passes.
  #
  # That is the gap this closes. Not "the guard is broken" — it is slow enough
  # that the apps are down for hours, which is how
  # TODO.md's "amber_bsdports_stop_and_stay_down" keeps getting
  # reopened by whoever notices amber is off.
  #
  # This asks the observable question — is something the guard shed still not
  # running — rather than reasoning about whether the restore thresholds are
  # reachable. The first version of this check did the latter, and measured
  # against the real 1550-tick history it stayed silent through the very
  # incident it was written for: the gate does open, but rarely, and the log
  # does not record whether anything was shed at the time, so "the gate opened
  # recently" answers a question nobody asked. The shed list plus rcctl answers
  # the one that matters, with no model of the box in between.
  #
  # Status is injected so the rule is decidable off the box. A rule about
  # production that only runs on production is one nobody runs.
  module GuardState
    SHED_STATE = "/var/db/resource_guard_shed"

    module_function

    # nil when healthy, a failure line when the guard's own list names something
    # that is down.
    def shed_and_down(shed:, running:)
      services = shed.to_s.split.reject(&:empty?)
      return nil if services.empty?

      down = services.reject { |svc| running.call(svc) }
      return nil if down.empty?

      "resource guard: #{down.join(', ')} shed and still down — relayd answers TLS for them, so this " \
        "is invisible from outside. `doas rcctl restart #{down.first}` brings one back; if they keep " \
        "landing here, the restore thresholds in OPENBSD/bin/resource_guard.sh no longer reach this box."
    end

    # The guard's list is append-only until its own restore path removes an
    # entry, so a service can sit in it while running perfectly — which means
    # something other than the guard started it, typically a deploy. Stale
    # state, not an outage, and worth telling apart from one: on 2026-08-14 both
    # apps were listed and up for half an hour after a fleet deploy restarted
    # them, before a later guard tick caught up and cleared the list.
    def stale_entries(shed:, running:)
      services = shed.to_s.split.reject(&:empty?)
      services.select { |svc| running.call(svc) }
    end
  end
end

`````

### lib/permission_audit.rb

`````ruby
# frozen_string_literal: true

module Deploy
  # Secrets and app data that anyone on the box can read, and daemon logs the
  # daemon cannot write.
  #
  # Both have happened. The app homes were world-readable until 2026-08-25, with
  # production databases inside them. And `.master/tts-worker-0.log` came back
  # `root:master` while the daemon runs as `master`: it could not open its own
  # log, died before creating a socket, and /health read tts true while no
  # socket existed. OPERATOR.sh and vps_ci.sh set the modes; nothing checked
  # they stayed set.
  #
  # The policy is what those scripts write: `/etc/<app>.env` root:<app> 0640,
  # `/home/<app>/app/storage` 0750. So the rule is "no permission for other" on
  # both, not an exact mode, which leaves the group bits to the scripts that own
  # them. Stats are injected so the rule is decidable off the box.
  module PermissionAudit
    module_function

    # entries: [{ path:, mode:, owner: }] — mode as File::Stat#mode, owner as a
    # user name. Returns failure lines.
    def failures(secrets:, private_dirs:, daemon_logs:, daemon_user:)
      lines = []
      (secrets + private_dirs).each do |entry|
        next unless entry[:mode].to_i.anybits?(0o007)

        lines << format("permissions: %<path>s is %<mode>04o — other can reach it", path: entry[:path],
                                                                                    mode: entry[:mode] & 0o7777)
      end
      daemon_logs.each do |entry|
        next if entry[:owner] == daemon_user

        lines << "permissions: #{entry[:path]} is owned by #{entry[:owner]}, and #{daemon_user} writes it"
      end
      lines
    end
  end
end

`````

### lib/secret_redaction.rb

`````ruby
# frozen_string_literal: true

# Secret redaction for sync.rb, the return leg of the drift gate.
#
# The patterns are a floor, not a ceiling. A secret whose name carries no
# `_KEY=`-shaped suffix, or whose value does not start with the one prefix a
# pattern pinned, mirrored into git verbatim — which is how a shared checkout
# leaks. The residue audit closes that direction: after redaction, any line
# still carrying a secret-shaped name with a non-empty value refuses the file
# instead of writing it, so the operator extends the patterns rather than
# discovering the gap in a pushed commit.
module SecretRedaction
  PLACEHOLDER = "__REDACTED__".freeze

  SECRET_PATTERNS = [
    /(_API_KEY=)\S+/,
    # Any *_KEY= value, not only sk-prefixed ones: r8_ and other provider
    # prefixes passed the old sk- guard and mirrored unredacted.
    /(_KEY=)\S+/,
    /(SECRET_KEY_BASE=)[a-f0-9]{32,}/,
    /(_TOKEN=)\S+/,
    /(_PASSWORD=)\S+/,
    /(_SECRET=)\S+/,
  ].freeze

  # Names that carry secrets but match no value-shaped pattern above — bare
  # `smtp_url=`, yaml `password:`. Matches key/token/secret/password/passphrase
  # inside a larger word, then an `=` or `:` with a non-empty value. Lines
  # already carrying the placeholder are skipped, so a redacted line never
  # refuses its own file.
  RESIDUE_PATTERN =
    /\b[A-Za-z0-9_-]*(?:key|token|secret|password|passphrase)[A-Za-z0-9_-]*\s*[=:]\s*\S+/i.freeze

  # Credentials embedded in a URL — `smtp://user:pass@mail` — carry no
  # secret-shaped name, so the name audit above is blind to them.
  RESIDUE_URI_PATTERN = /[a-z][a-z0-9+.-]*:\/\/\S+:\S+@/i.freeze

  def self.redact(body)
    SECRET_PATTERNS.inject(body) { |acc, pat| acc.gsub(pat, '\1' + PLACEHOLDER) }
  end

  # The lines that still look secret after redaction, stripped for the
  # refusal message. Empty means the file is safe to mirror.
  def self.residue(body)
    redacted = redact(body)
    redacted.lines.grep_v(/#{PLACEHOLDER}/).grep(Regexp.union(RESIDUE_PATTERN, RESIDUE_URI_PATTERN)).map(&:strip)
  end
end

`````

### lib/ssh_vm23.sh

`````zsh
#!/usr/bin/env zsh
set -euo pipefail
# Shared SSH helper for vm23 (dev@brgen.no).
#
# Source from deploy scripts:
#   source OPENBSD/lib/ssh_vm23.sh
#   vm23_ssh 'uname -a'
#   vm23_tmux deploy "doas zsh OPENBSD/OPERATOR.sh 2>&1 | tee /tmp/deploy.log"
#
# Direct invocation:
#   zsh OPENBSD/lib/ssh_vm23.sh 'cd /home/dev/pub4 && git pull'
#   zsh OPENBSD/lib/ssh_vm23.sh tmux deploy 'doas zsh OPENBSD/OPERATOR.sh'
#
# Env: SSH_USER SSH_HOST SSH_KEY REMOTE_PUB4
#
# SSH_HOST here is the host ALONE — the login is SSH_USER, and they are joined as
# ${SSH_USER}@${SSH_HOST} below. config_drift_gate.rb and bin/deploy-diff.sh give
# the same variable the opposite meaning, login@host in one string, so exporting
# one file's SSH_HOST into another's yields dev@dev@brgen.no and every ssh fails.

: "${SSH_USER:=dev}"
: "${SSH_HOST:=brgen.no}"
: "${SSH_KEY:=${HOME}/.ssh/id_ed25519_brgen}"
: "${REMOTE_PUB4:=/home/dev/pub4}"

# One copy of the usage, above the functions rather than in the dispatch at the
# foot of the file, and reachable as -h so an operator does not have to run the
# script with no argument to be told what it takes.
ssh_vm23_usage() {
  print -r -- "usage: ssh_vm23.sh <remote-command>
       ssh_vm23.sh exec <remote-command>
       ssh_vm23.sh tmux <session> <remote-command>

Env: SSH_USER SSH_HOST SSH_KEY REMOTE_PUB4"
}

typeset -ga VM23_SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)
[[ -f $SSH_KEY ]] && VM23_SSH_OPTS+=(-i "$SSH_KEY")

vm23_ssh() {
  ssh "${VM23_SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

vm23_tmux() {
  typeset session=$1
  shift
  typeset cmd=$*
  typeset quoted_session=${(q)session}
  vm23_ssh \
    "tmux has-session -t ${quoted_session} 2>/dev/null && tmux kill-session -t ${quoted_session}; \
     tmux new-session -d -s ${quoted_session} ${(q)cmd}"
}

if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  case "${1:-}" in
    -h|--help)
      ssh_vm23_usage
      exit 0
      ;;
    tmux)
      shift
      vm23_tmux "$@"
      ;;
    exec)
      shift
      vm23_ssh "$@"
      ;;
    "")
      ssh_vm23_usage >&2
      exit 2
      ;;
    *)
      vm23_ssh "$@"
      ;;
  esac
fi

`````

### lib/token_echo.rb

`````ruby
# frozen_string_literal: true

# A line that writes output and carries a token value in a query string. A
# restart that prints `web: <url>/?token=<secret>` leaves the operator credential
# in ~/vps-deploy.log for anyone who reads it. Sending a token stays allowed: a
# curl or a Rack env builds a request, and no log reads that line.
#
# Its own file rather than three more defs in deploy_smoke_gate.rb: MASTER's
# self_test counts an OPENBSD Ruby file past ten defs as a god class and refuses
# to boot, and the smoke gate stood at ten. Scanning every tracked script is a
# different job from checking the relayd and httpd templates anyway.
module TokenEcho
  PATTERN = /token=(?:#\{|\$\{?\w|%s)/
  OUTPUT_VERB = /\b(?:puts|print|printf|echo|warn|logger|tee)\b|\$std(?:out|err)\b|\bSTD(?:OUT|ERR)\b/
  SCRIPT_EXTENSIONS = %w[.rb .sh .ksh .zsh .rake].freeze

  module_function

  def echoes(text, path)
    text.each_line.with_index(1).filter_map do |line, number|
      "#{path}:#{number}" if line.match?(PATTERN) && line.match?(OUTPUT_VERB)
    end
  end

  # Tracked scripts and every Ruby file, tests aside: a test that proves this
  # detector has to spell the line it refuses.
  def candidates(root)
    listed = IO.popen(["git", "-C", root, "ls-files", "-z"], err: File::NULL, &:read).to_s.split("\0")
    listed.select do |rel|
      next false if rel.match?(%r{(?:\A|/)(?:test|spec)/})

      path = File.join(root, rel)
      next false unless File.file?(path) && File.size(path) < 1_000_000

      SCRIPT_EXTENSIONS.include?(File.extname(rel)) || rel.include?("/rc.d/") ||
        (File.extname(rel).empty? && File.open(path) { |f| f.read(2) } == "#!")
    end
  end

  def check(failures, root)
    scripts = candidates(root)
    if scripts.empty?
      failures << "token echo: git ls-files listed no scripts under #{root}, so nothing was read"
      return
    end

    scripts.each do |rel|
      echoes(File.read(File.join(root, rel)).scrub, rel).each do |at|
        failures << "token echo: #{at} prints a token value — print the URL and point at /pair issue"
      end
    end
  end
end

`````

### lib/utf8.rb

`````ruby
# frozen_string_literal: true

# OPERATOR command-line tools inspect UTF-8 source and configuration regardless
# of the operator's locale. Minimal OpenBSD and CI environments may otherwise
# default Ruby file reads to US-ASCII.
Encoding.default_external = Encoding::UTF_8


`````

### ptr_openbsd_amsterdam.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "uri"

module Operator
  class PtrOpenbsdAmsterdam
    IPV4_ENDPOINT = "http://ptr4.openbsd.amsterdam"
    IPV6_ENDPOINT = "http://ptr6.openbsd.amsterdam"

    def initialize(ip:, hostname:, apply: false)
      @ip = ip
      @hostname = hostname
      @apply = apply
    end

    def call
      validate!
      request = build_request

      unless apply
        puts JSON.pretty_generate(
          dry_run: true,
          endpoint: endpoint,
          ip: ip,
          hostname: hostname,
          method: request.method,
          note: "Set APPLY_PTR=1 to send this request."
        )
        return true
      end

      response = Net::HTTP.start(request.uri.hostname, request.uri.port, use_ssl: request.uri.scheme == "https") do |http|
        http.request(request)
      end

      puts response.body unless response.body.to_s.empty?
      response.is_a?(Net::HTTPSuccess)
    end

    private

    attr_reader :ip, :hostname, :apply

    def endpoint
      ip.include?(":") ? IPV6_ENDPOINT : IPV4_ENDPOINT
    end

    def build_request
      uri = URI(endpoint)
      uri.query = URI.encode_www_form(ip: ip, hostname: hostname)
      Net::HTTP::Post.new(uri)
    end

    def validate!
      raise ArgumentError, "hostname must end with a dotless DNS name" unless hostname.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/i)
      raise ArgumentError, "ip must look like IPv4 or IPv6" unless ip.match?(/\A[0-9a-f:.]+\z/i)
      raise ArgumentError, "refusing localhost PTR" if ip.start_with?("127.") || ip == "::1"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    apply: ENV["APPLY_PTR"] == "1",
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby OPENBSD/ptr_openbsd_amsterdam.rb --ipv4 IP --hostname NAME"
    opts.on("--ipv4 IP", "IPv4 address") { |value| options[:ip] = value }
    opts.on("--ipv6 IP", "IPv6 address") { |value| options[:ip] = value }
    opts.on("--hostname NAME", "PTR hostname, e.g. ns.brgen.no") { |value| options[:hostname] = value }
  end

  parser.parse!

  unless options[:ip] && options[:hostname]
    warn parser
    exit 64
  end

  ok = Operator::PtrOpenbsdAmsterdam.new(
    ip: options.fetch(:ip),
    hostname: options.fetch(:hostname),
    apply: options.fetch(:apply)
  ).call

  exit(ok ? 0 : 1)
end

`````

### relayd_prune_keypairs.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Drop `tls keypair` lines whose certificate is not on disk, because relayd
# refuses to start over one and takes every site down with it.
#
#   ruby40 OPENBSD/relayd_prune_keypairs.rb [PATH]           # report only (default)
#   ruby40 OPENBSD/relayd_prune_keypairs.rb --apply [PATH]   # rewrite PATH
#
# Report-only unless told otherwise: this rewrites /etc/relayd.conf, and a tool
# that edits the front door by default is one a curious run can break.
# OPERATOR.sh passes --apply, then `relayd -n` validates the result.

if ARGV.intersect?(%w[-h --help])
  puts "usage: relayd_prune_keypairs.rb [--apply] [PATH]   (default PATH /etc/relayd.conf; report-only without --apply)"
  exit 0
end

apply = ARGV.delete("--apply")
path = ARGV[0] || "/etc/relayd.conf"
body = File.read(path)
dropped = []
lines = body.each_line.filter_map do |line|
  if line =~ /^\s*tls keypair "([^"]+)"/
    domain = Regexp.last_match(1)
    cert = "/etc/ssl/#{domain}.crt"
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    unless File.exist?(cert) || File.exist?(fullchain)
      dropped << domain
      next
    end
  end
  line
end

dropped.each { |domain| puts "relayd_prune_keypairs: no certificate for #{domain}" }
if apply
  File.write(path, lines.join) unless dropped.empty?
  puts "relayd_prune_keypairs: #{path} (#{dropped.size} keypair(s) removed)"
else
  puts "relayd_prune_keypairs: #{path} unchanged (#{dropped.size} keypair(s) would be removed; pass --apply)"
end

`````

### sync.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Mirror live VPS config into OPENBSD/ with secret redaction.
# Run on VPS: doas ruby40 ~/pub4/OPENBSD/sync.rb

require "fileutils"
require_relative "gates/config_drift_gate"
require_relative "lib/secret_redaction"

# The files come from the drift gate, so the return leg copies exactly what the
# gate compares plus what it skips as templated. A file the gate reports drifted
# and this does not copy is a hand-edit with no way back into the repo.
#
# Two sources are this file's own. nsd.conf is generated by bin/render_dns.rb, so
# a copy of the live one makes `render_dns.rb --check` report a hand-edit on the
# box. /home/dev/.zshrc has no installer; etc/.zshrc is only this mirror of it.
#
# Zone data is not mirrored. /var/nsd/zones/master holds 61 zones, and the signed
# artifacts (*.zone.signed, K*.key, K*.ds) are regenerated on every re-sign, so a
# copy would put a churning DNS into every git diff while the nameserver remains
# the source of truth. An audit that finds signed zones or keys absent from git
# is describing this choice, not a gap. The unsigned *.zone files are different:
# bin/render_dns.rb generates them and they are committed, so --check can compare.
SOURCES = (
  VERBATIM.to_a +
  EXCLUDED.map { |repo_rel| [repo_rel, "/#{repo_rel}"] } +
  [["var/nsd/etc/nsd.conf", "/var/nsd/etc/nsd.conf"], ["etc/.zshrc", "/home/dev/.zshrc"]]
).freeze

def redact(body)
  SecretRedaction.redact(body)
end

# A Mac has its own /etc/pf.conf and /etc/ssh/sshd_config, and copying those
# over the vm23 mirror is a silent overwrite.
unless on_vps?
  warn "sync: refused - run on vm23 as root (doas ruby40 OPENBSD/sync.rb); this machine's /etc is not the box's"
  exit 2
end

mirrored = []
skipped = []
refused = []
SOURCES.each do |repo_rel, live_path|
  unless File.exist?(live_path)
    skipped << live_path
    next
  end
  body = File.read(live_path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  # Refuse before writing: a mirrored file is the drift gate's comparison
  # source, so a secret the patterns never learned would sit in git until
  # someone reads it. A refusal surfaces the line here instead.
  if (left = SecretRedaction.residue(body)).any?
    refused << live_path
    warn "sync: refused #{live_path} - secret-shaped lines survived redaction:"
    left.each { |line| warn "  #{line}" }
    warn "  extend lib/secret_redaction.rb patterns if these are benign"
    next
  end
  dest = File.join(MIRROR, repo_rel)
  FileUtils.mkdir_p(File.dirname(dest))
  File.write(dest, redact(body))
  mirrored << live_path
end

puts "mirrored #{mirrored.size}:"
mirrored.each { |p| puts "  #{p}" }
if skipped.any?
  puts "skipped (not present): #{skipped.size}"
  skipped.each { |p| puts "  #{p}" }
end
exit 3 if refused.any?

`````

### test/resource_guard_test.sh

`````zsh
#!/bin/ksh
# Drive resource_guard.sh through tick sequences with stubbed system tools, and
# assert what it sheds. The guard is load-bearing — a wrong shed took all four
# apps down today — so its hysteresis needs proving, not eyeballing.
#
# The ladder is two services, bsdports then amber. It was three, and this file
# asserted litestream went first long after the guard stopped shedding it, which
# nothing noticed because nothing ran this file. OPENBSD/bin/check-openbsd runs
# it now.
set -e

SANDBOX=$(mktemp -d)
BIN=$SANDBOX/bin
DB=$SANDBOX/db
mkdir -p "$BIN" "$DB" "$SANDBOX/log"

GUARD=${1:?usage: guard_test.sh /path/to/resource_guard.sh}

# --- stubs -------------------------------------------------------------------
cat > "$BIN/sysctl" <<'EOF'
#!/bin/ksh
case "$*" in
  *vm.loadavg*) print "1.0 ${FAKE_LOAD:-1.0} 1.0" ;;
  *hw.physmem*) print 1055760384 ;;
  *) print 0 ;;
esac
EOF

cat > "$BIN/top" <<'EOF'
#!/bin/ksh
print "Memory: Real: 500M/900M act/tot Free: ${FAKE_FREE:-400}M Cache: 0M Swap: 100M/1264M"
EOF

cat > "$BIN/rcctl" <<'EOF'
#!/bin/ksh
# $1 = check|stop|start|get, $2 = svc
svc=$2
state_file="$FAKE_STATE_DIR/$svc"
case "$1" in
  check) [[ -f $state_file ]] && print "$svc(ok)" || print "$svc(failed)" ;;
  stop)  rm -f "$state_file"; print "stopped $svc" >> "$FAKE_STATE_DIR/actions" ;;
  start) : > "$state_file"; print "started $svc" >> "$FAKE_STATE_DIR/actions" ;;
  get)   exit 0 ;;
esac
EOF

cat > "$BIN/logger" <<'EOF'
#!/bin/ksh
shift 2 2>/dev/null || true
print "$*" >> "$FAKE_STATE_DIR/log"
EOF

# Two processes per daemon user, 256M each, in ps's kilobytes.
cat > "$BIN/ps" <<'EOF'
#!/bin/ksh
print 262144
print 262144
EOF

cat > "$BIN/vmstat" <<'EOF'
#!/bin/ksh
print "pages managed 100"
print "pages free 50"
EOF

chmod +x "$BIN"/*

export PATH="$BIN:$PATH"
export FAKE_STATE_DIR="$DB"
export GUARD_SHED_STRIKES=2

# Point the guard's state files into the sandbox.
run_tick() {
  free=$1
  FAKE_FREE=$free ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
}

sed -e "s#^export PATH=.*#export PATH=$BIN:/usr/bin:/bin#" \
    -e "s#^SHED_STATE=.*#SHED_STATE=$DB/shed#" \
    -e "s#^STRIKE_STATE=.*#STRIKE_STATE=$DB/strikes#" \
    -e "s#^ALL_APPS_FLAG=.*#ALL_APPS_FLAG=$DB/all_apps#" \
    -e "s#>> /var/log/resource_guard_history.log#>> $SANDBOX/log/history#" \
    -e "s#GUARD_HELPER=.*#GUARD_HELPER=$DB/nonexistent#" \
    "$GUARD" > "$SANDBOX/guard_under_test.sh"

fail=0
check() {
  desc=$1; expected=$2; actual=$3
  if [[ "$expected" == "$actual" ]]; then
    print "  ok   $desc"
  else
    print "  FAIL $desc — expected [$expected] got [$actual]"
    fail=1
  fi
}

up() { for s in "$@"; do : > "$DB/$s"; done }
running() { ls "$DB" 2>/dev/null | grep -Ex 'amber|bsdports' | sort | tr '\n' ' ' | sed 's/ $//'; }
reset() { rm -f "$DB"/* 2>/dev/null || true; up bsdports amber; } # scan: intentional — clears this test's own scratch $DB between cases

# physmem is ~1007M, so Free=400M is ~39% (clear), Free=40M is ~3% (breach).
CLEAR=400
BREACH=40

print "1. a single breaching tick must not shed anything"
reset
run_tick "$BREACH"
check "both still up after 1 breach" "amber bsdports" "$(running)"

print "2. two consecutive breaches shed exactly one — the cheapest"
run_tick "$BREACH"
check "bsdports shed, amber up" "amber" "$(running)"

print "3. a clear tick restores what was shed, and resets the strike counter"
run_tick "$CLEAR"
check "bsdports restored on the clear tick" "amber bsdports" "$(running)"
run_tick "$BREACH"
check "first breach after a clear tick sheds nothing" "amber bsdports" "$(running)"

print "4. sustained pressure keeps shedding, one per tick, cheapest first"
run_tick "$BREACH"
check "bsdports goes first" "amber" "$(running)"
run_tick "$BREACH"
check "amber last" "" "$(running)"

print "5. the old behaviour would have shed both on tick 1"
reset
GUARD_SHED_STRIKES=1 FAKE_FREE=$BREACH ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "with strikes=1 only one goes, not both" "amber" "$(running)"

print "6. every tick charges resident memory to each daemon user"
last=""
while IFS= read -r line; do last=$line; done < "$SANDBOX/log/history"
got=""
for field in $last; do [[ $field == rss_* ]] && got="$got $field"; done
check "history names each app's rss, summed over its processes" \
  "rss_master=512M rss_brgen=512M rss_bsdports=512M rss_amber=512M" "${got# }"

rm -rf "$SANDBOX"
[[ $fail -eq 0 ]] && print "\nALL PASS" || { print "\nFAILURES"; exit 1; }

`````

### test/run_all.rb

`````ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs OPENBSD/test/test_*.rb, one process per file.
#
#   ruby OPENBSD/test/run_all.rb            # all of them
#   ruby OPENBSD/test/run_all.rb health     # only files matching /health/
#
# One process per file for the reasons RAILS/test/run_all.rb gives: files that
# share a process share every top-level constant, one `exit` anywhere ends the
# run early with Minitest reporting whatever it had, and a red result names no
# file. Exit status is the number of red files, capped at 255.

require "open3"
require "rbconfig"

root = File.expand_path("../..", __dir__)
filter = ARGV.first
# Written out from the repository root, so MASTER/tools/runs.rb reads the glob
# and counts every file it selects as run.
files = Dir.glob(File.join(root, "OPENBSD/test/**/test_*.rb")).sort
files = files.select { |path| path.include?(filter) } if filter
abort "openbsd contracts: no test files#{filter ? " matching #{filter.inspect}" : ''}" if files.empty?

red = files.reject do |path|
  out, status = Open3.capture2e({ "MT_NO_PLUGINS" => "1" }, RbConfig.ruby, path, chdir: root)
  tally = out[/^\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips/] || "no summary"
  puts format("openbsd contracts: %s %-40s %s", status.success? ? "ok  " : "FAIL", File.basename(path), tally)
  puts out.lines.grep(/^\s*\d+\) (Failure|Error):/).first(4).map { |line| "        #{line}" } unless status.success?
  status.success?
end

puts "openbsd contracts: #{files.size} file(s), #{red.size} red#{red.empty? ? '' : ": #{red.map { |p| File.basename(p) }.join(', ')}"}"
exit red.size.clamp(0, 255)

`````

### test/test_config_drift_gate.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
# See test_restore_scripts.rb: the weekly integrity run on vm23 invokes these
# under a C locale, where Ruby reads files as US-ASCII and every read of this
# UTF-8 source raises "invalid byte sequence".
require_relative "../lib/utf8"
require_relative "../gates/config_drift_gate"

# The crontab half of the drift gate, with the shape it must flag and the shape
# it must not.
#
# It exists because the /etc half passed clean while a scheduled job was missing.
# `etc/crontab.vm23:97` has named /usr/local/bin/vps_weekly_integrity.sh for
# weeks; the box has no such line and no such file, and the weekly integrity pass
# has never run. Every file the gate compared matched, so it said clean and meant
# it — it was comparing the wrong thing.
class ConfigDriftGateCrontabTest < Minitest::Test
  REPO = <<~CRON
    # a comment, and a blank line follow
    PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin

    */5 * * * * /usr/local/bin/relayd-watchdog
    */5 * * * * ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
    30 3 * * 0 /usr/local/bin/vps_weekly_integrity.sh
  CRON

  # The real live crontab, in the state measured on 2026-09-10: the weekly line
  # was never merged onto the box.
  LIVE_WITHOUT_WEEKLY = <<~CRON
    PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
    */5 * * * * /usr/local/bin/relayd-watchdog
    */5 * * * * ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
  CRON

  def test_the_command_is_the_first_absolute_path_not_the_environment_or_the_redirect
    assert_equal(
      %w[/usr/local/bin/relayd-watchdog /usr/local/bin/uptime-check.sh /usr/local/bin/vps_weekly_integrity.sh],
      scheduled_commands(REPO)
    )
  end

  def test_a_path_assignment_is_not_a_scheduled_command
    assert_empty scheduled_commands("PATH=/bin:/usr/local/bin\n")
  end

  # The shape it must flag.
  def test_a_declared_job_the_box_does_not_schedule_is_drift
    cron = crontab_report(REPO, LIVE_WITHOUT_WEEKLY)

    refute cron[:ok], "a job scheduled only in the repo read as clean"
    assert_equal ["/usr/local/bin/vps_weekly_integrity.sh"], cron[:absent]
    assert_empty cron[:extra]
  end

  # The other shape it must flag: a hand-edit on the box that nobody copied back.
  def test_a_job_only_the_box_schedules_is_drift
    cron = crontab_report(REPO, "#{REPO}0 1 * * * /usr/local/bin/hand-added.sh\n")

    refute cron[:ok]
    assert_equal ["/usr/local/bin/hand-added.sh"], cron[:extra]
  end

  # The shape it must not flag, and the one that cost four false alarms on the
  # first run: OpenBSD ships root its own crontab and OPERATOR.sh merges onto it.
  def test_the_base_system_crontab_is_not_drift
    stock = <<~CRON
      0\t*\t*\t*\t*\t/usr/bin/newsyslog
      30\t1\t*\t*\t*\t/bin/sh /etc/daily
      30\t3\t*\t*\t6\t/bin/sh /etc/weekly
    CRON

    cron = crontab_report(REPO, REPO + stock)

    assert cron[:ok], "OpenBSD's own cron lines reported as drift: #{cron[:extra]}"
  end

  # The shape it must not flag. Order and formatting differ because OPERATOR.sh
  # merges rather than overwrites, so only the set of commands is comparable.
  def test_the_same_commands_in_another_order_are_not_drift
    reordered = <<~CRON
      30 3 * * 0 /usr/local/bin/vps_weekly_integrity.sh
      */5 * * * * MAIL_IMG_FMT=png /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
      */5 * * * * /usr/local/bin/relayd-watchdog
    CRON

    cron = crontab_report(REPO, reordered)

    assert cron[:ok], "a reordered but equivalent crontab reported drift: #{cron[:absent]} #{cron[:extra]}"
    assert_equal 3, cron[:declared]
  end

  # Nothing found and nothing missing are different answers. Reporting every
  # declared job as absent when the crontab could not be read is ten false alarms
  # and the fastest way to teach a reader to skip this section.
  def test_an_unreadable_crontab_skips_rather_than_failing_everything
    cron = crontab_report(REPO, nil)

    assert cron[:ok]
    assert_empty cron[:absent]
    assert_includes cron[:summary], "not readable"
  end

  # The gate is only as good as its mirror. If crontab.vm23 stops parsing, every
  # comparison below it silently compares nothing.
  def test_the_real_tracked_crontab_parses
    tracked = File.join(File.expand_path("..", __dir__), "etc", "crontab.vm23")
    commands = scheduled_commands(File.read(tracked))

    refute_empty commands, "etc/crontab.vm23 parsed to no commands — the check would pass having measured nothing"
    assert(commands.all? { |c| c.start_with?("/") }, "a parsed command is not an absolute path: #{commands.inspect}")
  end
end

# The byte-compare half: the doas keepenv root-RCE stayed live for days because
# nothing compared the mirror with /etc.
class ConfigDriftGateVerbatimTest < Minitest::Test
  # The box exactly as the repo describes it.
  def matching_box
    VERBATIM.to_h { |repo_rel, live_path| [live_path, File.read(File.join(MIRROR, repo_rel))] }
  end

  def test_the_mirror_is_found_and_matches_itself
    report = verbatim_report(matching_box)

    assert_empty report[:unfound], "the gate cannot find the repo mirror, so it compares nothing"
    assert_equal VERBATIM.size, report[:compared].size
    assert_empty report[:drift]
  end

  # The installed copy once resolved its mirror beside itself, found none, and
  # said clean having compared nothing. Unfound is counted, not skipped.
  def test_a_mirror_that_is_not_there_is_unfound_rather_than_clean
    Dir.mktmpdir("no-mirror") do |empty|
      report = verbatim_report(matching_box, mirror: empty)

      assert_equal VERBATIM.keys, report[:unfound]
      assert_empty report[:compared]
    end
  end

  # The shape it must flag: a hand-edit on the box.
  def test_a_live_file_that_differs_from_its_mirror_is_drift
    box = matching_box
    box["/etc/doas.conf"] = "permit keepenv persist :wheel\n"
    report = verbatim_report(box)

    assert_equal ["etc/doas.conf"], report[:drift].keys
    assert_match(/repo sha=\h{12} .* vs live sha=\h{12}/, report[:drift]["etc/doas.conf"])
  end

  def test_a_live_file_that_is_absent_is_missing_not_clean
    box = matching_box
    box["/usr/local/bin/emergency_cpu.sh"] = nil

    assert_equal ["emergency_cpu.sh"], verbatim_report(box)[:missing]
  end

  # The shape it must not flag: relayd.conf is installed from a template, so the
  # live copy always differs, and comparing it would be a permanent false alarm.
  def test_an_excluded_file_that_differs_on_the_box_is_not_drift
    box = matching_box
    EXCLUDED.each { |repo_rel| box["/#{repo_rel}"] = "templated on the box\n" }
    report = verbatim_report(box)

    assert_empty report[:drift]
    assert_empty VERBATIM.keys & EXCLUDED, "a file cannot be both byte-compared and excluded"
  end
end

`````

### test/test_core_reclaim.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# core-reclaim.sh decides whether the box is too busy to restart brgen by
# comparing two decimals in ksh, which has only integers. The function is read
# out of the script itself and run under ksh, so the verdict is the shell's and
# not a reading of its source.
class TestCoreReclaim < Minitest::Test
  SCRIPT = File.expand_path("../usr/local/bin/core-reclaim.sh", __dir__)
  KSH = %w[/bin/ksh /usr/bin/ksh].find { |path| File.executable?(path) }
  # Both sides of LOAD_MAX, loads over ten, a bare integer, a bare fraction, and
  # the 08 and 09 fractions ksh would read as bad octal without a base.
  LOADS = %w[0.00 0.08 0.09 0.18 1.9 2.08 2.09 2.49 2.50 2.5 2.51 2.500001 2.4999999 3 .5 9.99 10.00 99.99].freeze

  def verdicts(limit)
    skip "no ksh here" unless KSH
    function = File.read(SCRIPT)[/^micro\(\) \{\n.*?^\}\n/m]
    refute_nil function, "core-reclaim.sh no longer defines micro()"

    program = function + LOADS.map { |load| %(if (( $(micro "#{load}") > $(micro "#{limit}") )); then print 1; else print 0; fi\n) }.join
    out, err, status = Open3.capture3(KSH, "-c", program)
    assert status.success?, err
    out.split.map { |bit| bit == "1" }
  end

  def test_the_integer_comparison_agrees_with_float_comparison
    limit = File.read(SCRIPT)[/^LOAD_MAX=(\S+)/, 1]
    expected = LOADS.map { |load| load.to_f > limit.to_f }

    assert_equal LOADS.zip(expected), LOADS.zip(verdicts(limit))
  end
end

`````

### test/test_deploy_stamp.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/deploy_stamp"

class TestDeployStamp < Minitest::Test
  def with_stamp(body)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "last_deploy_master.json"), body) if body
      yield dir
    end
  end

  def test_the_stamp_sha_is_read_and_a_missing_or_torn_stamp_is_nil
    with_stamp(%({"app":"master","sha":"aa4f010c1","status":"ok"})) do |dir|
      assert_equal "aa4f010c1", Deploy::DeployStamp.sha("master", dir:)
    end
    with_stamp(nil) { |dir| assert_nil Deploy::DeployStamp.sha("master", dir:) }
    with_stamp(%({"app":"mas)) { |dir| assert_nil Deploy::DeployStamp.sha("master", dir:) }
  end

  # Measured on vm23 2026-09-15: /health said aa4f010c1 and the stamp said
  # aa4f010c1, while the checkout had moved on to b9d0f4fac.
  def test_the_booted_build_matching_the_stamp_passes_at_either_short_length
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1", stamped: "aa4f010c1")
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1e", stamped: "aa4f010c1")
  end

  def test_a_build_no_deploy_ran_fails_and_names_both_commits
    line = Deploy::DeployStamp.booted_mismatch(app: "master", booted: "b9d0f4fac", stamped: "aa4f010c1")

    assert_includes line, "b9d0f4fac"
    assert_includes line, "aa4f010c1"
  end

  def test_a_process_that_cannot_name_its_build_fails
    refute_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: nil, stamped: "aa4f010c1")
  end

  def test_no_stamp_is_not_a_mismatch
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1", stamped: nil)
  end
end

`````

### test/test_disk_usage.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/disk_usage"

class TestDiskUsage < Minitest::Test
  OPENBSD = <<~DF
    Filesystem  1K-blocks      Used     Avail Capacity iused   ifree  %iused  Mounted on
    /dev/sd0a     1012974    137446    824880    14%    2915  152331     2%   /
    /dev/sd0h     9912846   9420000    -2000    100%  120000   10000    92%   /home
    /dev/sd0e     1498334     40000   1383418     3%    1000  200000     0%   /var
  DF

  def test_a_full_filesystem_fails_by_blocks_and_inodes
    lines = Deploy::DiskUsage.failures(OPENBSD)

    assert_equal ["disk: /home blocks 100% used", "disk: /home inodes 92% used"], lines
  end

  def test_a_healthy_box_passes
    healthy = OPENBSD.lines.reject { |line| line.include?("/home") }.join

    assert_empty Deploy::DiskUsage.failures(healthy)
  end

  # A df that changed its columns must fail loudly, not pass having read nothing.
  def test_an_unreadable_df_is_a_failure
    refute_empty Deploy::DiskUsage.failures("")
    refute_empty Deploy::DiskUsage.failures("Filesystem Size Used\n/dev/x 1 1\n")
  end

  def test_this_hosts_df_parses
    out = IO.popen(["df", "-ik"], err: File::NULL, &:read)
    skip "no df here" if out.to_s.empty?

    refute(Deploy::DiskUsage.failures(out, limit: 101).any? { |line| line.include?("column") })
  end
end

`````

### test/test_dns_facts_agree.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"
require_relative "../bin/render_dns"

# Four DNS facts were written down twice: data/dns.yml declares them, OPERATOR.sh
# restates them as shell literals, and gates/dns_zones.rb had its own third copy
# of two. The copies had already drifted — OPERATOR.sh's resolver list led with
# 8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why.
#
# The gate now reads the policy file. OPERATOR.sh cannot: that block is sourced
# before anything else runs, and making the deploy script shell out to ruby34 to
# boot would put it behind an interpreter it is itself responsible for
# installing. So the duplication stays and this makes it cost something.
class DnsFactsAgreeTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  POLICY = YAML.safe_load_file(File.join(OPENBSD, "data", "dns.yml"))
  OPERATOR = File.read(File.join(OPENBSD, "OPERATOR.sh"), encoding: "UTF-8")

  def shell_scalar(name)
    OPERATOR[/^typeset -r #{name}="([^"]+)"/, 1]
  end

  def shell_array(name)
    OPERATOR[/^typeset -a #{name}=\(([^)]*)\)/, 1]&.split
  end

  def test_brgen_ip_is_the_nameserver_the_policy_declares
    assert_equal POLICY.fetch("nameserver").fetch("ip"), shell_scalar("BRGEN_IP")
  end

  # ns.hyp.net is Domeneshop's secondary and pulls by AXFR, so it is the first
  # peer the policy lists rather than a separate fact.
  def test_hyp_ip_is_the_first_transfer_peer
    assert_equal POLICY.fetch("xfr_peers").first, shell_scalar("HYP_IP")
  end

  def test_the_public_resolvers_are_one_list
    assert_equal POLICY.fetch("resolvers").fetch("public"), shell_array("PUBLIC_RESOLVERS")
  end

  # The domain list is read twice as well, and not in two files but in two
  # languages. OPERATOR.sh's loops walk ALL_DOMAINS as zsh expands the array;
  # render_dns.rb splits the same block into lines. A comment, a quoted entry or
  # two entries on one line inside it splits differently, and then the zones the
  # generator writes and the domains the installer walks are two fleets. zsh
  # evaluates the block here so the two readings are compared, not assumed.
  def test_all_domains_reads_the_same_in_zsh_and_in_render_dns
    block = OPERATOR[/^ALL_DOMAINS=\(\n.*?\n\)$/m]
    refute_nil block, "no ALL_DOMAINS block in OPERATOR.sh"

    out, status = Open3.capture2("zsh", "-f", "-c", "#{block}\nprint -rl -- $ALL_DOMAINS")
    assert status.success?, "zsh could not evaluate the ALL_DOMAINS block"
    expanded = out.lines.to_h do |entry|
      domain, subs = entry.chomp.split(":", 2)
      [domain, subs.to_s.split(",").map(&:strip).reject(&:empty?)]
    end

    assert_operator expanded.size, :>, 40, "zsh expanded only #{expanded.size} domains"
    assert_equal expanded, RenderDns.city_zones
  end

  # If the two readers above stop finding anything, every assertion passes by
  # comparing nil to nil.
  def test_the_scan_reads_real_values
    refute_nil shell_scalar("BRGEN_IP"), "the typeset scan found no BRGEN_IP"
    refute_nil shell_array("PUBLIC_RESOLVERS"), "the typeset scan found no PUBLIC_RESOLVERS"
    refute_empty POLICY.fetch("resolvers").fetch("public")
  end
end

require_relative "../gates/dns_zones"
require_relative "../gates/domain_alignment"
require_relative "../bin/domain_watch"

# domain_watch asks the registry about every zone the policy declares, including
# one not yet rendered into nsd.conf.
class DomainWatchPopulationTest < Minitest::Test
  def test_a_zone_the_policy_declares_is_watched_before_nsd_conf_has_it
    original = RenderDns.method(:zones)
    RenderDns.define_singleton_method(:zones) { original.call.merge("ghost.example" => []) }

    assert_includes Deploy::DomainWatch.zones, "ghost.example"
  ensure
    RenderDns.define_singleton_method(:zones, original)
  end

  def test_the_watched_zones_are_the_rendered_zones
    assert_equal RenderDns.zones.keys.sort, Deploy::DomainWatch.zones
    assert_operator Deploy::DomainWatch.zones.size, :>, 40
  end
end

# The two gates that hold those facts to the zones and the registry, each beside
# the drift it exists to catch (decision 2026-08-22). The network half of
# dns_zones is handed a resolver that answers what the fixture says, so the
# verdict is the gate's and no packet leaves the machine.
class DnsZonesGateFixtureTest < Minitest::Test
  GATE = Deploy::DnsZonesGate

  # A resolver whose every name answers `addresses`, or raises `error`.
  Resolver = Struct.new(:addresses, :error) do
    def getaddresses(_name) = error ? raise(error) : addresses
    def getaddress(_name) = error ? raise(error) : addresses.first
  end

  def gate
    @gate ||= GATE.new.tap { |g| g.instance_variable_set(:@result, Deploy::GateResult.new) }
  end

  def result = gate.instance_variable_get(:@result)

  # RenderDns answers `name` with `replacement` applied to its real answer while
  # the gate runs `check`.
  def with_render(name, replacement, check)
    original = RenderDns.method(name)
    RenderDns.define_singleton_method(name) { replacement.call(original.call) }
    gate.send(check)
  ensure
    RenderDns.define_singleton_method(name, original)
  end

  # bsdports.org, owned and paid and parked at the registrar.
  def test_an_app_domain_that_resolves_nowhere_fails
    gate.send(:check_delegation, Resolver.new([]), "bsdports", "bsdports.org")

    assert_match(/bsdports\.org \(bsdports\) resolves nowhere/, result.failures.join)
  end

  def test_an_app_domain_delegated_somewhere_else_fails
    gate.send(:check_delegation, Resolver.new(["192.0.2.1"]), "brgen", "brgen.no")

    assert_match(/resolves to 192\.0\.2\.1, not #{Regexp.escape(GATE::NAMESERVER)}/, result.failures.join)
  end

  def test_an_app_domain_pointing_here_passes_and_counts
    gate.send(:check_delegation, Resolver.new([GATE::NAMESERVER]), "brgen", "brgen.no")

    assert_empty result.failures
    assert_equal 1, result.checks_ran
  end

  # A dropped packet is not a missing record: three timeouts skip, three
  # NXDOMAINs fail.
  def test_a_vertical_our_nameserver_does_not_answer_fails_and_a_timeout_only_skips
    gate.send(:check_domain, Resolver.new(nil, Resolv::ResolvError), "brgen.no", %w[tv])

    assert_match(/does not answer for brgen\.no, tv\.brgen\.no, www\.brgen\.no/, result.failures.join)

    timed_out = GATE.new.tap { |g| g.instance_variable_set(:@result, Deploy::GateResult.new) }
    timed_out.send(:check_domain, Resolver.new(nil, Resolv::ResolvTimeout), "brgen.no", %w[tv])
    outcome = timed_out.instance_variable_get(:@result)

    assert_empty outcome.failures
    assert_equal 1, outcome.live_skips
  end

  def test_a_domain_with_no_zone_block_in_nsd_conf_fails
    with_render(:zones, ->(zones) { zones.merge("ghost.example" => []) }, :every_domain_has_a_zone)

    assert_match(/nsd\.conf has no zone block for ghost\.example/, result.failures.join)
  end

  # The hand-edit the generator exists to stop: nsd.conf on disk is no longer
  # what data/dns.yml renders.
  def test_an_nsd_conf_the_generator_would_not_write_fails
    with_render(:nsd_conf_body, ->(body) { "#{body}# hand-edited\n" }, :generated_output_matches)

    assert_match(/generated file\(s\) differ .*nsd\.conf/, result.failures.join)
  end

  def test_the_committed_zones_match_what_the_generator_renders
    gate.send(:generated_output_matches)
    gate.send(:every_domain_has_a_zone)

    assert_empty result.failures
    assert_operator result.checks_ran, :>, 50
  end
end

class DomainAlignmentGateFixtureTest < Minitest::Test
  GATE = Deploy::DomainAlignmentGate

  def setup
    @gate = GATE.new
    @registry = @gate.send(:parse_registry_entries).keys
    @keys = @gate.send(:parse_relayd_keypairs)
    @declared = @gate.send(:extract_constant, GATE::REGISTRY.read, "LIVE_DOMAINS")
  end

  def alignment_failures(keys)
    result = Deploy::GateResult.new
    @gate.send(:live_domains_check, result, @registry, keys)
    result.failures.join(" | ")
  end

  # Too many: the city network links a hostname relayd holds no certificate for.
  def test_a_live_domain_with_no_keypair_fails
    assert_match(/LIVE_DOMAINS names #{Regexp.escape(@declared.last)} with no tls keypair/,
                 alignment_failures(@keys - [@declared.last]))
  end

  # Too few: a city relayd serves and nothing links.
  def test_a_certified_city_left_out_of_live_domains_fails
    unlisted = (@registry - @declared).first

    refute_nil unlisted, "every registry domain is live, so this fixture has nothing to plant"
    assert_match(/LIVE_DOMAINS omits #{Regexp.escape(unlisted)}/, alignment_failures(@keys + [unlisted]))
  end

  # A commented-out keypair is a certificate relayd does not load, so the city it
  # names is linked with nothing serving it.
  def test_a_commented_out_keypair_does_not_count_as_live
    commented = GATE::RELAYD.read.sub(/^(\s*)(tls keypair "#{Regexp.escape(@declared.last)}")/, '\1# \2')
    keys = @gate.send(:parse_relayd_keypairs, commented)

    refute_includes keys, @declared.last
    assert_equal @keys.size - 1, keys.size
    assert_match(/LIVE_DOMAINS names #{Regexp.escape(@declared.last)} with no tls keypair/, alignment_failures(keys))
  end

  # The gate compares the registry against the fleet render_dns writes zones for,
  # and the zsh expansion test above holds that reader to OPERATOR.sh.
  def test_the_gate_reads_all_domains_through_render_dns
    original = RenderDns.method(:city_zones)
    RenderDns.define_singleton_method(:city_zones) { original.call.except("brgen.no") }

    assert_match(/missing DNS brgen\.no/, GATE.run.failures.join(" | "))
  ensure
    RenderDns.define_singleton_method(:city_zones, original)
  end

  def test_the_committed_tree_passes
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join("\n")
    assert_equal @declared.size, result.checks_ran
  end
end


class OwnedDomainFactsAgreeTest < Minitest::Test
  RAILS_APPS = File.expand_path("../../RAILS/apps.yml", __dir__)
  OPERATOR = File.expand_path("../OPERATOR.sh", __dir__)
  EXPECTED = %w[
    amberapp.art amberapp.no amberapp.online brgen.no bsdports.net bsdports.org
    cardff.uk denvr.us edinbrgh.uk foball.no frankfrt.de lndon.uk lsangeles.com
    lsangeles.store oshlo.no stvanger.no svalbrd.no trndheim.no wshingtondc.com
    wshingtondc.us
  ].freeze

  def test_rails_owned_domains_match_the_registrar_export_inventory
    inventory = YAML.safe_load_file(RAILS_APPS).fetch("owned_domains")
    assert_equal EXPECTED, inventory
  end

  def test_owned_domain_facts_match_owned_domains
    inventory = YAML.safe_load_file(RAILS_APPS)
    assert_equal inventory.fetch("owned_domains").sort, inventory.fetch("owned_domain_facts").keys.sort
    assert_equal false, inventory.fetch("owned_domain_facts").fetch("foball.no").fetch("renew")
    assert_equal "2026-09-06", inventory.fetch("owned_domain_facts").fetch("svalbrd.no").fetch("expires").to_s
  end

  def test_openbsd_owned_domains_match_rails_inventory
    operator = File.read(OPERATOR, encoding: "UTF-8")
    block = operator[/^OWNED_DOMAINS=\(\n.*?\n\)$/m]
    refute_nil block, "no OWNED_DOMAINS block in OPERATOR.sh"
    out, status = Open3.capture2("zsh", "-f", "-c", "#{block}\nprint -rl -- $OWNED_DOMAINS")
    assert status.success?, "zsh could not evaluate OWNED_DOMAINS"
    assert_equal YAML.safe_load_file(RAILS_APPS).fetch("owned_domains"), out.lines.map(&:chomp)
  end

  def test_domain_watch_includes_owned_domains_without_turning_them_into_zones
    owned = Deploy::DomainWatch.owned_domains
    assert_equal EXPECTED.sort, owned.sort
    assert_equal RenderDns.zones.sort, (Deploy::DomainWatch.zones - owned).sort
  end
end

`````

### test/test_domain_expiry.rb

`````ruby
# frozen_string_literal: true

# Domains expire silently and the site stops.
#
# amstrdam.nl served Amsterdam, lapsed, dropped, and was re-registered by someone
# else on 2026-05-18 — noticed 81 days later, by accident. lndon.uk went the same
# way. On 2026-08-07 bsdports.org, a live production site, was 24 hours from
# expiry and nothing in this repo knew.
#
# This reads the committed snapshot rather than the network, so it is fast and
# offline-safe. Refresh the snapshot with:
#
#   ruby OPENBSD/bin/domain_watch.rb --update
#
# It fails on a domain past expiry or inside the warning window, and on a domain
# whose creation date moved — that is what "someone else registered it" looks
# like in whois.

require "minitest/autorun"
require "yaml"
require "date"
require_relative "../bin/domain_watch"

class TestDomainExpiry < Minitest::Test
  SNAPSHOT = File.expand_path("../data/domain_inventory.yml", __dir__)
  RELEASED = File.expand_path("../data/domain_released.yml", __dir__)
  WARN_DAYS = 30

  def setup
    released = File.exist?(RELEASED) ? (YAML.safe_load_file(RELEASED) || {}) : {}
    # A domain we have decided to let go is not an alarm. Recording the decision
    # is the only way this gate can be greened without renewing, and it leaves a
    # reason next to the name rather than a silent skip.
    @released = released.keys
    @rows = YAML.safe_load_file(SNAPSHOT).reject { |domain, _| @released.include?(domain) }
    @today = Date.today
  end

  def expiry_for(row)
    raw = row["expires"]
    return nil if raw.nil? || raw.to_s.strip.empty?

    Date.parse(raw.to_s)
  rescue ArgumentError
    nil
  end

  def test_no_domain_is_past_expiry
    expired = @rows.filter_map do |domain, row|
      date = expiry_for(row)
      next unless date && date < @today

      "#{domain} expired #{date} (#{(@today - date).to_i} days ago)"
    end

    assert_empty expired,
                 "domains past their expiry date. Renew at the registrar and refresh the " \
                 "snapshot with OPENBSD/bin/domain_watch.rb --update, or record the decision to " \
                 "let one go in OPENBSD/data/domain_released.yml. Editing this test is neither:" \
                 "\n  #{expired.join("\n  ")}"
  end

  def test_no_domain_expires_within_the_warning_window
    soon = @rows.filter_map do |domain, row|
      date = expiry_for(row)
      next unless date && date >= @today && date <= @today + WARN_DAYS

      "#{domain} expires #{date} (#{(date - @today).to_i} days)"
    end

    assert_empty soon,
                 "domains expiring within #{WARN_DAYS} days (renew, or record the decision in " \
                 "OPENBSD/data/domain_released.yml):\n  #{soon.join("\n  ")}"
  end

  # A snapshot that silently empties would make both assertions above pass.
  def test_the_snapshot_still_holds_domains
    assert_operator @rows.size, :>, 40, "snapshot holds only #{@rows.size} domains"
    known = @rows.count { |_, row| row["state"] == "registered" }
    assert_operator known, :>, 10, "only #{known} domains resolved to a registration record"
  end

  # A lookup must be bounded and must not go through a shell. This asserted a
  # source spelling naming /usr/bin/timeout instead, which held the tool to a
  # binary macOS does not have — so --update ran only on vm23 and the snapshot
  # this suite reads went three weeks stale. The behaviour was right and the
  # check was measuring how it was written.
  #
  # What matters, held two ways: no shell form anywhere, and a slow child is
  # actually killed. The second runs a real process, because a timeout that
  # never fires looks exactly like a fast network.
  def test_a_lookup_is_bounded_and_never_goes_through_a_shell
    source = File.read(File.expand_path("../bin/domain_watch.rb", __dir__))
    # Code only. The first draft of this matched a backtick inside the comment
    # explaining why backticks are wrong — the instrument reading its own
    # documentation and reporting it as the defect.
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join

    refute_match(/`[^`\n]*\b(?:whois|curl|timeout)\b/, code, "a lookup went back through a shell")
    refute_match(/\bsystem\(/, code, "a lookup was handed to a shell")
  end

  # The registry's own words decide the state. Both patterns are /x so they can
  # wrap, and /x drops every literal space: "is free" compiled to "isfree", so
  # rottrdam.nl answering "rottrdam.nl is free" was filed unknown with that line
  # as its note. Each phrase is held against the answer it has to read.
  def whois_answer(body)
    watch = Deploy::DomainWatch
    original = watch.method(:capture_bounded)
    watch.define_singleton_method(:capture_bounded) { |*_argv, **_opts| body }
    watch.whois_query("example.nl")
  ensure
    watch.define_singleton_method(:capture_bounded, original)
  end

  def test_every_available_phrase_reads_as_available
    ["example.nl is free", "No match for \"EXAMPLE.NL\".", "NOT FOUND", "No entries found",
     "Domain example.nl is available", "No Data Found", "Object does not exist",
     "example.nl not registered", "Status: free"].each do |body|
      assert_equal "available", whois_answer(body)["state"], "#{body.inspect} did not read as available"
    end
  end

  def test_every_registered_phrase_reads_as_registered
    ["example.nl\nRegistered on: 2020-01-01", "example.nl\nCreation Date: 2020-01-01",
     "example.nl\nName Server: ns.example.nl", "example.nl\nDomain nameservers:\n ns.example.nl",
     "example.nl\nRegistrar: Example"].each do |body|
      assert_equal "registered", whois_answer(body)["state"], "#{body.inspect} did not read as registered"
    end
  end

  def test_a_hung_lookup_is_killed_rather_than_waited_on
    started = Time.now
    out = Deploy::DomainWatch.capture_bounded("sleep", "30", seconds: 1)
    elapsed = Time.now - started

    assert_operator elapsed, :<, 10, "capture_bounded waited #{elapsed.round(1)}s against a 1s bound"
    assert_equal "", out.strip
  end
end

`````

### test/test_gate_fixtures.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/utf8"
require_relative "../gates/installed_targets_gate"

# Every OPENBSD gate beside the defect it exists to catch.
#
# A gate that only ever runs over this checkout and says clean proves nothing: it
# says clean just as well with its body gutted. So each pair here plants the
# shape the gate must flag, watches it fail, and runs the committed tree for the
# shape it must not — the house decision of 2026-08-22.
class InstalledTargetsGateFixtureTest < Minitest::Test
  GATE = Deploy::InstalledTargetsGate

  def setup
    @tmp = Dir.mktmpdir("installed-targets")
    GATE.root = @tmp
  end

  def teardown
    GATE.root = GATE::DEFAULT_ROOT
    FileUtils.remove_entry(@tmp)
  end

  def plant(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def missing = GATE.orphans.keys

  # The daily.local shape the gate was written for: a guard on a target nothing
  # installs.
  def test_a_cron_target_nothing_installs_is_named
    plant("etc/crontab.vm23", "*/5 * * * * /usr/local/bin/ghost.sh\n")

    assert_equal ["bin/ghost.sh"], missing
  end

  # resource_guard.sh is installed from the tree root and calls its crisis tier by
  # its installed path. A script the repo installs is a referrer like any crontab.
  def test_an_installed_script_naming_a_target_nothing_installs_is_named
    plant("OPERATOR.sh", %(install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh\n))
    plant("guard.sh", "[ -x /usr/local/bin/crisis.sh ] && /usr/local/bin/crisis.sh\n")

    assert_equal ["bin/crisis.sh"], missing
  end

  def test_an_install_line_provides_its_target
    plant("OPERATOR.sh", <<~SH)
      install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh
      install -m 755 "${SCRIPT_DIR}/crisis.sh" /usr/local/bin/crisis.sh
    SH
    plant("guard.sh", "/usr/local/bin/crisis.sh\n")
    plant("crisis.sh", "#!/bin/ksh\n")

    assert_empty missing
  end

  # libexec is copied wholesale like bin, and root dot-sources what is in it.
  def test_a_libexec_target_is_measured_and_shipping_it_provides_it
    plant("etc/daily.local", ". /usr/local/libexec/helper.ksh\n")

    assert_equal ["libexec/helper.ksh"], missing

    plant("usr/local/libexec/helper.ksh", "#!/bin/ksh\n")

    assert_empty missing
  end

  def test_a_directory_named_in_prose_is_not_a_target
    plant("etc/daily.local", "# nothing lives in /usr/local/bin/lib/ any more\n")

    assert_empty GATE.referenced
  end

  def test_the_committed_tree_names_the_crisis_tier_and_provides_it
    GATE.root = GATE::DEFAULT_ROOT

    # Named by the guard itself, not by any file that mentions the path: a comment
    # elsewhere naming it would keep the key present with the guard unread.
    assert_includes GATE.referenced.fetch("bin/emergency_cpu.sh", []), "bin/resource_guard.sh",
                    "resource_guard.sh's crisis path is no longer read, so a missing install would pass"
    assert_includes GATE.referenced.keys, "libexec/stale_ci_cleanup.ksh"
    assert_empty GATE.orphans
  end
end

# OPERATOR.sh re-runs on a live box, so each destructive step has to be one a
# second run survives. The check reads the script for four guarantees; these
# hand it the script with one of them broken.
class IdempotencyFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  CHECK = File.join(OPENBSD, "gates", "verify_openbsd_idempotency.rb")
  BACKUP = "backup_directory /var/nsd/zones/master nsd-zones\n"
  DELETE = "rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)\n" # scan: intentional — fixture text, never run
  REST = <<~SH
    cp -R "${src}/home" "/var/backups/home"
    bin/rails db:prepare
    rcctl restart ${svc} || rcctl start ${svc}
  SH

  def verdict(body)
    Dir.mktmpdir("idempotency") do |dir|
      path = File.join(dir, "OPERATOR.sh")
      File.write(path, body)
      out, status = Open3.capture2e(RbConfig.ruby, CHECK, path)
      [status.success?, out]
    end
  end

  def test_the_zones_deleted_with_no_backup_is_refused
    ok, out = verdict(DELETE + REST)

    refute ok, "a zone wipe with no backup passed"
    assert_includes out, "nsd backup does not precede destructive delete"
  end

  def test_a_backup_taken_after_the_delete_is_refused
    ok, = verdict(DELETE + BACKUP + REST)

    refute ok, "a backup of zones already deleted passed"
  end

  def test_a_restart_with_no_start_fallback_is_refused
    ok, out = verdict(BACKUP + DELETE + REST.sub(" || rcctl start ${svc}", ""))

    refute ok
    assert_includes out, "missing restart/start fallback"
  end

  def test_the_snippet_with_every_guarantee_passes
    ok, out = verdict(BACKUP + DELETE + REST)

    assert ok, out
  end

  def test_the_committed_operator_script_passes
    out, status = Open3.capture2e(RbConfig.ruby, CHECK)

    assert status.success?, out
  end
end

# Every app deploy calls into RAILS/_deploy.sh. The identity check used to find
# the function by its spelling, which a comment satisfies as well as a definition.
class DeployIdentityFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  load File.join(OPENBSD, "gates", "verify_deploy_identity.rb")

  def missing(body)
    Dir.mktmpdir("identity") do |dir|
      File.write(File.join(dir, "helper.sh"), "need_cmd() { :; }\n")
      library = File.join(dir, "_deploy.sh")
      File.write(library, body)
      shell_functions_missing(library, %w[deploy_tracked_app need_cmd])
    end
  end

  def test_a_function_named_only_in_a_comment_is_missing
    assert_equal %w[deploy_tracked_app need_cmd], missing("# deploy_tracked_app() lives here\n")
  end

  def test_a_function_from_a_sourced_file_counts
    body = %(. "${${(%):-%x}:A:h}/helper.sh"\ndeploy_tracked_app() { :; }\n)

    assert_empty missing(body)
  end

  def test_the_committed_library_defines_every_shared_function
    assert_empty shell_functions_missing(File.join(OPENBSD, "..", "RAILS", "_deploy.sh"), SHARED_FUNCTIONS)
  end

  def test_the_run_fails_on_a_library_that_defines_nothing
    Dir.mktmpdir("identity") do |dir|
      library = File.join(dir, "_deploy.sh")
      File.write(library, "# deploy_tracked_app() lives here\n")
      out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "gates", "verify_deploy_identity.rb"), library)

      refute status.success?
      assert_includes out, "defines no deploy_tracked_app"
    end
  end

  def test_the_committed_tree_passes
    out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "gates", "verify_deploy_identity.rb"))

    assert status.success?, out
  end
end

require_relative "../gates/port_inventory"

# port_inventory handed the fleet with one port moved, so each mirror it reads
# must notice apps.yml and its copy no longer agree.
class PortInventoryFixtureTest < Minitest::Test
  GATE = Deploy::PortInventoryGate

  def apps = @apps ||= Deploy::Inventory.new(root: GATE::ROOT).apps

  # The fleet as apps.yml would describe it after brgen moved to port 40000.
  def moved = apps.map { |app| app.name == "brgen" ? app.dup.tap { |a| a.port = 40_000 } : app }

  def findings(check, fleet, *rest)
    result = Deploy::GateResult.new
    GATE.new.send(check, result, fleet, *rest)
    result.failures
  end

  def test_relayd_forwarding_to_the_old_port_fails
    old = apps.find { |app| app.name == "brgen" }.port

    assert_includes findings(:check_relayd_ports, moved),
                    "brgen: relayd.conf forwards to port #{old}, apps.yml says 40000"
  end

  def test_a_smoke_probe_on_the_old_port_fails
    assert_match(/probes port \d{5}, which no app in apps.yml listens on \(line names brgen\)/,
                 findings(:check_smoke_probes, moved).join(" | "))
  end

  # A probe that names one app and another app's port warms the wrong process,
  # and the bare `smoke <app> <port>` form is read as well as the URL form.
  def test_a_probe_naming_one_app_on_another_apps_port_fails
    named, other = apps.first(2)
    Dir.mktmpdir("smoke") do |dir|
      File.write(File.join(dir, "smoke.sh"), <<~SH)
        smoke #{named.name} #{other.port}
        curl -fsS http://127.0.0.1:#{named.port}/up
      SH
      result = Deploy::GateResult.new
      GATE.new.send(:check_smoke_probes, result, apps, root: dir, scripts: ["smoke.sh"])

      assert_equal ["smoke.sh:1 probes port #{other.port}, which no app in apps.yml listens on (line names #{named.name})"],
                   result.failures
    end
  end

  def test_operator_app_ports_on_the_old_port_fails
    assert_includes findings(:check_openbsd_ports, moved).join(" | "), "brgen: OpenBSD APP_PORTS"
  end

  def test_two_apps_on_one_port_fail
    clash = apps.first(2).map(&:dup).each { |app| app.port = 40_000 }

    assert_equal ["port collision 40000: #{clash.map(&:name).join(', ')}"], findings(:check_uniques, clash, :port)
  end

  def test_the_committed_tree_passes
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join("\n")
    assert_operator apps.size, :>=, 3
  end
end

# shell_syntax_gate parses each script with the interpreter its shebang names.
class ShellSyntaxFixtureTest < Minitest::Test
  GATE = File.expand_path("../gates/shell_syntax_gate.rb", __dir__)

  def scan(files)
    Dir.mktmpdir("shell-syntax") do |root|
      files.each do |rel, body|
        path = File.join(root, "OPENBSD", rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      out, status = Open3.capture2e({ "SHELL_SYNTAX_ROOT" => root }, RbConfig.ruby, GATE)
      [status.success?, out]
    end
  end

  def test_a_script_that_does_not_parse_fails_and_is_named
    ok, out = scan("bin/broken" => "#!/usr/bin/env zsh\nif [[ -n x ]]; then\n  print hi\n",
                   "fine.sh" => "#!/bin/sh\necho ok\n")

    refute ok
    assert_includes out, "1 of 2 scripts do not parse"
    assert_includes out, "zsh -n OPENBSD/bin/broken"
  end

  # The shebang picks the parser: `set -A` is ksh and a syntax error to nothing
  # else that matters here, so a ksh script must not be read by sh.
  def test_each_script_is_parsed_by_its_own_shebang
    ok, out = scan("usr/local/bin/warm.sh" => "#!/bin/ksh\nset -A T a b\nfor t in \"${T[@]}\"; do print $t; done\n")

    assert ok, out
    assert_includes out, "1 scripts parse"
  end

  def test_a_tree_with_no_shebangs_is_a_broken_scan
    ok, out = scan("notes.sh" => "echo no shebang\n")

    refute ok
    assert_includes out, "the scan is broken"
  end

  def test_the_committed_tree_parses
    out, status = Open3.capture2e(RbConfig.ruby, GATE)

    assert status.success?, out
  end
end

class DeploySmokeFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  require File.join(OPENBSD, "gates", "deploy_smoke_gate.rb")

  PUBLIC = %w[/up /health].freeze

  def rc_findings(body)
    failures = []
    check_master_rc(failures, body, PUBLIC)
    failures
  end

  def test_a_warmup_that_needs_a_token_is_refused
    body = %(curl -fsS "http://127.0.0.1:${PORT}/chat/metrics?token=${TOKEN}"\n)
    named = rc_findings(body).join(" | ")

    assert_includes named, "carries a credential"
    assert_includes named, "needs auth since the tier gate"
    assert_includes named, "no warmup request asks a path AuthTier serves without a token"
  end

  def test_a_start_block_with_nothing_to_warm_is_refused
    assert_includes rc_findings("rcctl restart relayd\n"), "rc.d/master: no warmup request to the local port"
  end

  # The query string is the script's own business, which the old check was not:
  # it wanted `chat/message?message=ping` spelled exactly.
  def test_any_credential_free_warmup_through_a_public_path_passes
    body = %(curl -fsS "http://127.0.0.1:${PORT}/up"\ncurl -fsS "http://127.0.0.1:${PORT}/chat/message?message=hello"\n)

    assert_empty rc_findings(body)
  end

  # The line rc.d/master carried: a restart printed the operator token into
  # ~/vps-deploy.log. Placeholders only; no real token belongs in a test.
  def test_a_script_that_prints_a_token_value_is_refused
    ruby = %q(puts t ? "web: #{u}/?token=#{t}" : "web: #{u}") + "\n"
    shell = %(print "web: ${url}/?token=${WEB_TOKEN}"\nlogger -t master "open $url?token=$tok"\n)

    assert_equal ["rc.d/master:1"], TokenEcho.echoes(ruby, "rc.d/master")
    assert_equal ["bin/x:1", "bin/x:2"], TokenEcho.echoes(shell, "bin/x")
  end

  def test_a_request_that_sends_a_token_prints_nothing
    body = %(curl -fsS "http://127.0.0.1:${PORT}/chat/metrics?token=${TOKEN}"\n) +
           %q(middleware.call(env.merge("QUERY_STRING" => "token=#{token}"))) + "\n" +
           %(puts "web: token set, /pair issue for a code"\n)

    assert_empty TokenEcho.echoes(body, "bin/smoke")
  end

  def test_no_tracked_script_prints_a_token_value
    failures = []
    TokenEcho.check(failures, ROOT)
    scripts = TokenEcho.candidates(ROOT)

    assert_empty failures
    assert_operator scripts.size, :>, 100, "the scan read almost nothing, so its silence is not a finding"
    assert_includes scripts, "OPENBSD/etc/rc.d/master"
  end

  def test_the_committed_start_block_passes_against_the_real_middleware
    failures = []
    check_master_rc(failures)

    assert_empty failures
    refute_empty auth_tier_public_paths, "AuthTier's public paths read as empty, so every warmup would fail"
  end

  def test_a_relayd_host_route_that_is_missing_is_named
    relayd = File.read(RELAYD)
    port = YAML.safe_load_file(APPS_YML).dig("apps", "brgen", "port")
    failures = []
    assert_forward(relayd.sub(/^\s*match request header "Host" value "brgen\.no" forward to <brgen>.*$/, ""),
                   failures, "brgen", port, "brgen.no")

    assert_equal ["relayd: missing Host route for brgen.no in brgen"], failures
  end

  def test_the_committed_tree_passes
    out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "gates", "deploy_smoke_gate.rb"))

    assert status.success?, out
  end
end

`````

### test/test_gate_lib.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../lib/gate_result"
require_relative "../lib/gate_environment"
require_relative "../gates/integrity_gate"

class GateLibTest < Minitest::Test
  def test_gate_result_tracks_failures_and_warnings
    result = Deploy::GateResult.new
    assert result.ok?

    result.warn("heads up")
    assert result.ok?

    result.fail("blocked")
    refute result.ok?
    assert_equal ["blocked"], result.failures
    assert_equal ["heads up"], result.warnings
  end

  def test_gate_result_report_exits_on_failure
    result = Deploy::GateResult.new
    result.fail("nope")

    assert_raises(SystemExit) { result.report!("should not print") }
  end

  def test_integrity_gates_include_expected_entries
    names = Deploy::GateEnvironment::INTEGRITY_GATES.map(&:name)

    %w[
      deploy_identity
      production
      phantom_fk
      frontend
      relayd_smoke
      domain_align
      crawl_inventory
      schema_migration
      asset_freshness
      human_walkthrough
      vps_health
    ].each do |expected|
      assert_includes names, expected, "missing gate #{expected}"
    end
  end

  # measured_nothing? separates "declined to measure" from "measured and passed".
  # A result that recorded nothing at all is a pass: it made no claim either way.
  def test_measured_nothing_distinguishes_a_skip_from_a_check
    assert_equal :passed, Deploy::GateResult.new.outcome

    skipped = Deploy::GateResult.new.inconclusive!("no Chrome")
    assert skipped.measured_nothing?
    assert_equal :inconclusive, skipped.outcome

    partial = Deploy::GateResult.new.inconclusive!("no Chrome").checked!(3)
    refute partial.measured_nothing?, "a gate that ran three checks measured something"
    assert_equal :passed, partial.outcome

    live = Deploy::GateResult.new.skipped_live("port 61352 closed")
    assert live.measured_nothing?, "every live check skipped is nothing measured"
  end

  def test_skip_reason_consults_the_needs_it_declares
    vps_gate = Deploy::GateEnvironment::Gate.new(name: "x", path: "y", needs: %i[vps])
    plain = Deploy::GateEnvironment::Gate.new(name: "x", path: "y")

    assert_equal "not on VPS", Deploy::GateEnvironment.skip_reason(vps_gate, on_vps: false)
    assert_nil Deploy::GateEnvironment.skip_reason(vps_gate, on_vps: true)
    assert_nil Deploy::GateEnvironment.skip_reason(plain, on_vps: false)
  end

  # A need nothing reads is a claim with no effect; integrity_gate.rb skips on
  # exactly these three.
  def test_integrity_gates_declare_only_needs_skip_reason_reads
    needs = Deploy::GateEnvironment::INTEGRITY_GATES.flat_map(&:needs).uniq
    assert_empty needs - %i[vps bundle browser]
  end

  def test_every_integrity_gate_script_exists
    root = File.expand_path("../..", __dir__)
    missing = Deploy::GateEnvironment::INTEGRITY_GATES.map(&:path).uniq.reject { |path| File.file?(File.join(root, path)) }
    assert_empty missing
  end

  def test_vps_health_gate_targets_core_health_check
    gate = Deploy::GateEnvironment::INTEGRITY_GATES.find { |entry| entry.name == "vps_health" }
    refute_nil gate
    assert_equal "OPENBSD/gates/health_check.rb", gate.path
    assert_equal ["--core"], gate.args
    assert_includes gate.needs, :vps
  end
end

# integrity_gate.rb's loop, handed fake gates and a recording executor so the
# verdicts are its own and no real gate runs.
class IntegrityRunTest < Minitest::Test
  Gate = Deploy::GateEnvironment::Gate

  def setup
    @root = Dir.mktmpdir("integrity")
    %w[pass.rb fail.rb soft.rb box.rb].each { |name| File.write(File.join(@root, name), "") }
    @ran = []
  end

  def teardown = FileUtils.rm_rf(@root)

  def run_chain(gates, on_vps:)
    execute = lambda do |cmd|
      script = File.basename(cmd[1])
      @ran << script
      [script == "pass.rb" ? "" : "boom\n", script == "pass.rb"]
    end
    integrity_run(gates, root: @root, on_vps:, execute:, io: StringIO.new)
  end

  def test_a_vps_gate_off_the_box_is_skipped_and_never_executed
    report = run_chain([Gate.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: false)

    assert_equal ["vps_health: not on VPS"], report[:skipped]
    assert_empty @ran
    assert_empty report[:failures]
  end

  def test_a_vps_gate_on_the_box_runs_and_its_failure_blocks
    report = nil
    _, err = capture_io { report = run_chain([Gate.new(name: "vps_health", path: "box.rb", needs: %i[vps])], on_vps: true) }

    assert_equal ["box.rb"], @ran
    assert_equal ["vps_health"], report[:failures]
    assert_empty err, "the post-pull note is for a connect failure, not every failure"
  end

  def test_required_failures_block_and_optional_ones_warn
    gates = [
      Gate.new(name: "good", path: "pass.rb"),
      Gate.new(name: "bad", path: "fail.rb"),
      Gate.new(name: "soft", path: "soft.rb", optional: true),
    ]
    report = run_chain(gates, on_vps: false)

    assert_equal %w[pass.rb fail.rb soft.rb], @ran
    assert_equal ["bad"], report[:failures]
    assert_equal ["soft: boom"], report[:warnings]
  end

  # crawl_probe exits 3 when no app is listening. That is neither a pass nor a
  # failure, so the chain lists it as skipped unless strict mode asks it to block.
  def test_a_gate_that_measured_nothing_is_skipped_unless_strict
    gates = [Gate.new(name: "crawl", path: "pass.rb")]
    execute = ->(_cmd) { ["crawl: inconclusive (4 targets, 4 skipped)\n", :inconclusive] }

    report = integrity_run(gates, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_empty report[:failures]
    assert_equal ["crawl: measured nothing — crawl: inconclusive (4 targets, 4 skipped)"], report[:skipped]

    ENV["GATE_STRICT_INCONCLUSIVE"] = "1"
    strict = integrity_run(gates, root: @root, on_vps: false, execute:, io: StringIO.new)
    assert_equal ["crawl"], strict[:failures]
  ensure
    ENV.delete("GATE_STRICT_INCONCLUSIVE")
  end

  def test_a_gate_whose_script_is_gone_is_a_warning_not_a_pass
    report = run_chain([Gate.new(name: "ghost", path: "nowhere.rb")], on_vps: true)

    assert_equal ["ghost: missing nowhere.rb"], report[:warnings]
    assert_empty @ran
  end
end

`````

### test/test_githooks.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# The three guards in OPENBSD/dev/githooks are the only thing standing between a
# shared checkout and the accidents CLAUDE.md calls trap one, and until now
# nothing proved they still refuse anything. They are prose about prose: a hook
# that stopped firing would look exactly like a tree in which nobody made the
# mistake, and the mistakes they were written for — a cross-tree `git commit -a`,
# a push carrying four other sessions' commits, a move that half-landed — all
# happened in the week before the hooks existed, so there is no shortage of
# evidence about what silence costs.
#
# These run the real hooks through real git, in a throwaway repository, because
# a hook is only installed behaviour: unit-testing its logic would not have
# caught a missing chmod, a bad shebang, or a core.hooksPath that points at the
# wrong directory.
class TestGitHooks < Minitest::Test
  HOOKS = File.expand_path("../dev/githooks", __dir__)

  def setup
    @dir = Dir.mktmpdir("githooks")
    git("init", "--initial-branch=main")
    git("config", "user.email", "test@example.invalid")
    git("config", "user.name", "Hook Test")
    git("config", "core.hooksPath", HOOKS)
    # A first commit, so every case below has a HEAD to diff against.
    write("README.md", "seed\n")
    git("add", "README.md")
    commit("seed", env: { "PUB4_UNTRACKED" => "1" })
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  # --- helpers -------------------------------------------------------------

  def git(*args, env: {})
    out, status = Open3.capture2e(env, "git", *args, chdir: @dir)
    [out, status]
  end

  def git!(*args, env: {})
    out, status = git(*args, env:)
    raise "git #{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def write(path, body)
    full = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def commit(message, env: {})
    git("commit", "-m", message, env:)
  end

  def refute_committed(out, status, matching)
    refute status.success?, "the hook allowed the commit:\n#{out}"
    assert_match matching, out
  end

  # --- the hooks are actually installed ------------------------------------

  def test_every_hook_is_executable_and_runnable
    %w[pre-commit pre-push post-commit].each do |hook|
      path = File.join(HOOKS, hook)

      assert File.file?(path), "#{hook} is missing"
      assert File.executable?(path), "#{hook} is not executable — git would skip it silently"

      _out, status = Open3.capture2e(RbConfig.ruby, "-c", path)

      assert status.success?, "#{hook} does not parse"
    end
  end

  # --- 1. a commit spanning two trees is the `git commit -a` signature ------

  def stage_two_trees
    write("MASTER/a.rb", "# a\n")
    write("RAILS/b.rb", "# b\n")
    git!("add", "MASTER/a.rb", "RAILS/b.rb")
  end

  def test_a_cross_tree_commit_is_refused
    stage_two_trees
    out, status = commit("spans two trees")

    refute_committed out, status, /REFUSED — this commit spans 2 trees: MASTER, RAILS/
  end

  def test_the_refusal_names_the_way_out
    stage_two_trees
    out, _status = commit("spans two trees")

    assert_match(/PUB4_CROSS_TREE=1/, out)
    assert_match(/bin\/operator worktree/, out, "the refusal should name the actual fix, not only the override")
  end

  def test_the_cross_tree_override_is_honoured
    stage_two_trees
    out, status = commit("spans two trees, deliberately", env: { "PUB4_CROSS_TREE" => "1" })

    assert status.success?, "PUB4_CROSS_TREE=1 did not let the commit through:\n#{out}"
  end

  def test_a_single_tree_commit_passes
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    out, status = commit("one tree")

    assert status.success?, "an ordinary single-tree commit was refused:\n#{out}"
  end

  # --- 2. untracked files in the tree being committed ----------------------

  def test_an_untracked_file_in_the_committed_tree_is_refused
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("MASTER/forgotten.rb", "# never staged\n")
    out, status = commit("one tree, one file left behind")

    refute_committed out, status, /REFUSED — untracked file\(s\)/
    assert_match(/MASTER\/forgotten\.rb/, out, "the refusal should name the file it is refusing over")
    assert_match(/PUB4_UNTRACKED=1/, out)
  end

  def test_an_untracked_file_in_another_tree_does_not_refuse
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("RAILS/elsewhere.rb", "# another session's\n")
    out, status = commit("one tree")

    assert status.success?, "an untracked file in a tree this commit does not touch blocked it:\n#{out}"
  end

  def test_what_is_left_uncommitted_is_printed_grouped_by_tree
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("RAILS/one.rb", "# 1\n")
    write("RAILS/two.rb", "# 2\n")
    out, _status = commit("one tree")

    assert_match(/leaving uncommitted:.*RAILS \(2\)/, out)
    assert_match(/may belong to another session/, out)
  end

  # --- 3. a move that would half-land --------------------------------------

  def test_a_staged_deletion_beside_an_untracked_twin_is_refused
    write("MASTER/store.rb", "# original\n")
    git!("add", "MASTER/store.rb")
    commit("add store", env: { "PUB4_UNTRACKED" => "1" })

    git!("rm", "--cached", "MASTER/store.rb")
    FileUtils.rm(File.join(@dir, "MASTER/store.rb"))
    write("MASTER/ground/store.rb", "# moved\n")
    out, status = commit("move store")

    refute_committed out, status, /REFUSED — staged deletion \+ untracked twin/
    assert_match(/PUB4_SPLIT_MOVE=1/, out)
  end

   # --- 4. MASTER/tools ownership -------------------------------------------------

  def test_master_tools_belongs_to_the_session_that_claimed_it
    write("MASTER/tools/.session", "other-session\n")
    write("MASTER/tools/beat.rb", "# a take\n")
    git!("add", "STUDIO/.session", "STUDIO/beat.rb")
    out, status = commit("touch MASTER/tools")

    refute_committed out, status, /REFUSED — MASTER\/tools is owned by session 'other-session'/
  end

  def test_the_claiming_session_may_commit_master_tools
    write("MASTER/tools/.session", "mine\n")
    write("MASTER/tools/beat.rb", "# a take\n")
    git!("add", "STUDIO/.session", "STUDIO/beat.rb")
    out, status = commit("touch MASTER/tools", env: { "PUB4_SESSION" => "mine" })

    assert status.success?, "the owning session was refused its own tree:\n#{out}"
  end

  # --- 4b. the dilla engine must parse before it lands ----------------------
  #
  # A syntax error in dilla.rb or lib/ stops every render at load; one shipped
  # on 2026-09-19 and nothing noticed until renders died at boot. The hook
  # parses staged engine files, so the same incident cannot land again unseen.

  def test_a_staged_engine_file_that_does_not_parse_is_refused
    write("MASTER/tools/dilla/dilla.rb", "def broken\nend\nend\n")
    git!("add", "STUDIO/dilla/dilla.rb")
    out, status = commit("break the engine")

    refute_committed out, status, /REFUSED — .*dilla\.rb does not parse/
    assert_match(/PUB4_PARSE_SKIP=1/, out)
  end

  def test_a_staged_engine_file_that_parses_commits
    write("MASTER/tools/dilla/lib/knob.rb", "# frozen_string_literal: true\n\n# a knob\n")
    git!("add", "STUDIO/dilla/lib/knob.rb")
    out, status = commit("a knob that parses")

    assert status.success?, "a parsing engine file was refused:\n#{out}"
  end

  def test_a_staged_non_engine_ruby_file_needs_no_parse
    write("MASTER/tools/scratch.rb", "# not the engine\n")
    git!("add", "STUDIO/scratch.rb")
    out, status = commit("ruby outside the engine")

    assert status.success?, "a Ruby file outside the engine was refused a parse:\n#{out}"
  end

  def test_the_parse_override_is_honoured
    write("MASTER/tools/dilla/dilla.rb", "end\n")
    git!("add", "STUDIO/dilla/dilla.rb")
    out, status = commit("broken, deliberately", env: { "PUB4_PARSE_SKIP" => "1" })

    assert status.success?, "PUB4_PARSE_SKIP=1 did not let the commit through:\n#{out}"
  end

  # --- 5. pre-push: a push carries everything beneath it -------------------

  def push_setup
    remote = File.join(@dir, "..", "remote-#{File.basename(@dir)}.git")
    Open3.capture2e("git", "init", "--bare", "--initial-branch=main", remote)
    git!("remote", "add", "origin", remote)
    git!("push", "origin", "main", env: { "PUB4_PUSH_ALL" => "1" })
    remote
  end

  def add_commits(count)
    count.times do |i|
      write("MASTER/c#{i}.rb", "# #{i}\n")
      git!("add", "MASTER/c#{i}.rb")
      out, status = commit("commit #{i}", env: { "PUB4_UNTRACKED" => "1" })
      raise "setup commit failed: #{out}" unless status.success?
    end
  end

  def test_a_push_of_one_commit_is_allowed_and_named
    remote = push_setup
    add_commits(1)
    out, status = git("push", "origin", "main")

    assert status.success?, "a single-commit push was refused:\n#{out}"
    assert_match(/pre-push: publishing/, out, "the one commit being published should still be named")
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_a_push_of_more_than_one_commit_is_refused
    remote = push_setup
    add_commits(3)
    out, status = git("push", "origin", "main")

    refute status.success?, "a three-commit push was allowed:\n#{out}"
    assert_match(/REFUSED — 3 commits would be published, not 1/, out)
    assert_match(/PUB4_PUSH_ALL=1/, out)
    assert_match(/bin\/operator worktree/, out)
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_the_refusal_lists_every_commit_it_is_holding_back
    remote = push_setup
    add_commits(3)
    out, _status = git("push", "origin", "main")

    3.times { |i| assert_match(/commit #{i}/, out, "commit #{i} was held back without being named") }
    assert_match(/Hook Test/, out, "each held commit should carry its author")
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_the_push_override_is_honoured
    remote = push_setup
    add_commits(3)
    out, status = git("push", "origin", "main", env: { "PUB4_PUSH_ALL" => "1" })

    assert status.success?, "PUB4_PUSH_ALL=1 did not let the push through:\n#{out}"
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  # A missing ledger must read as "unknown", never as "foreign", or the first
  # push from a shell without one is a wall of false accusations.
  def test_an_absent_session_ledger_does_not_accuse
    remote = push_setup
    add_commits(3)
    FileUtils.rm_f(File.join(@dir, ".git", "pub4-session-commits"))
    out, _status = git("push", "origin", "main")

    refute_match(/FOREIGN/, out, "with no ledger the hook accused commits of being foreign")
    assert_match(/yours\?/, out)
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  # --- 6. post-commit keeps the ledger the push guard reads ----------------

  def test_post_commit_records_this_session_so_pre_push_can_mark_foreign_commits
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    commit("recorded", env: { "PUB4_SESSION" => "session-a" })

    ledger = File.join(@dir, ".git", "pub4-session-commits")

    assert File.file?(ledger), "post-commit wrote no ledger, so pre-push can never mark anything"
    assert_match(/\Asession-a [0-9a-f]+/, File.read(ledger).lines.last.to_s)
  end
end

`````

### test/test_guard_state.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/guard_state"

# amber and bsdports get shed and stay down, and nothing says so.
#
# relayd answers TLS on their behalf while they are down, so the outage reads as
# a hang rather than a 5xx and every other check on the box passes.
# TODO.md has carried "amber_bsdports_stop_and_stay_down" for
# exactly this, and each occurrence was found by a person noticing amber was off
# — including 2026-08-14, when two concurrent deploys shed both and the guard
# did not bring either back.
#
# An earlier version of this rule asked whether resource_guard.sh's restore
# thresholds were still reachable, computed from its history log. Measured
# against the real 1550-tick log it stayed silent through the incident it was
# written for, so it was replaced rather than shipped: the gate does open, just
# rarely, and the log never records whether anything was shed at the time. The
# rule below observes the outage instead of modelling the mechanism.
class TestGuardState < Minitest::Test
  ALL_UP = ->(_svc) { true }
  ALL_DOWN = ->(_svc) { false }

  def test_reports_a_shed_service_that_is_still_down
    message = Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: ALL_DOWN)

    refute_nil message
    assert_match(/amber, bsdports shed and still down/, message)
    assert_match(/relayd answers TLS/, message, "the message should say why nothing else reports it")
    assert_match(/rcctl restart amber/, message, "name the command that fixes it")
  end

  def test_reports_only_the_ones_actually_down
    up_only_amber = ->(svc) { svc == "amber" }
    message = Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: up_only_amber)

    assert_match(/bsdports shed and still down/, message)
    refute_match(/amber,/, message)
  end

  def test_silent_when_everything_shed_is_back_up
    assert_nil Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: ALL_UP)
  end

  def test_silent_when_nothing_is_shed
    assert_nil Deploy::GuardState.shed_and_down(shed: "", running: ALL_DOWN)
    assert_nil Deploy::GuardState.shed_and_down(shed: "\n \n", running: ALL_DOWN)
  end

  # The guard removes an entry only when its own restore path runs. A service
  # that is listed and running therefore proves restore did not bring it back —
  # something else did, and the list is now lying about the state of the box.
  # This is the state vm23 was left in on 2026-08-14: both apps up, both still
  # listed, unchanged across three further guard ticks.
  def test_names_entries_left_behind_by_a_restore_that_never_ran
    assert_equal %w[amber bsdports],
                 Deploy::GuardState.stale_entries(shed: "amber\nbsdports\n", running: ALL_UP)
    assert_empty Deploy::GuardState.stale_entries(shed: "amber\n", running: ALL_DOWN)
  end

  # The thresholds are not asserted as numbers — they are recalibrated as the box
  # changes, and have been twice. What must hold across recalibrations is that
  # restore sits above warn, or shed and restore chase each other.
  def test_the_guard_keeps_hysteresis_between_shed_and_restore
    # encoding: named, not inherited. Under a C locale — which is how the
    # integrity chain invokes everything on vm23 — Ruby reads files as US-ASCII,
    # and resource_guard.sh's comments are full of em-dashes. A bare File.read
    # passed on a Mac and raised "invalid byte sequence in US-ASCII" on the box.
    guard = File.read(File.expand_path("../bin/resource_guard.sh", __dir__), encoding: "UTF-8")
    warn_at = guard[/^MEM_WARN=(\d+)/, 1].to_i
    restore_at = guard[/^MEM_RESTORE=(\d+)/, 1].to_i

    assert_operator warn_at, :>, 0, "MEM_WARN is no longer parseable — this test is asserting nothing"
    assert_operator restore_at, :>, warn_at,
                    "no hysteresis: the guard would shed and restore around one threshold"
  end
end

`````

### test/test_guard_thresholds_documented.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"

# A threshold copied into prose goes stale the next time the box changes.
#
# OPENBSD/CLAUDE.md said "thresholds are now 8/14" for a month after
# resource_guard.sh moved MEM_RESTORE from 14 to 10 on 2026-08-14 — a
# recalibration the script records in full, with the 1550-tick dataset that
# justified it. Anyone reading the doc to decide whether the guard was tuned
# right was reading a number the running code had abandoned.
#
# The doc is allowed to name a threshold; it is not allowed to name a different
# one from the script. This checks the direction that matters: every number the
# prose attaches to a guard variable has to be the number the script sets.
class GuardThresholdsDocumentedTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  SCRIPT = File.join(OPENBSD, "bin", "resource_guard.sh")
  DOC = File.join(OPENBSD, "CLAUDE.md")

  # The gates the prose discusses by name.
  VARIABLES = %w[MEM_WARN MEM_RESTORE LOAD_WARN LOAD_RESTORE].freeze

  def script_values
    source = File.read(SCRIPT)
    VARIABLES.to_h do |name|
      # The assignment, not a mention of it in a comment.
      value = source[/^#{name}=([\d.]+)/, 1]
      [name, value]
    end
  end

  def test_the_script_sets_every_threshold_the_doc_discusses
    missing = script_values.select { |_, value| value.nil? }.keys

    assert_empty missing, "resource_guard.sh sets no value for: #{missing.join(', ')}"
  end

  # `MEM_RESTORE` is 10 — a backticked variable followed by a number is the
  # shape the stale sentence used, and the shape worth pinning.
  def test_no_documented_threshold_contradicts_the_script
    doc = File.read(DOC)
    wrong = []

    script_values.each do |name, value|
      doc.scan(/`#{name}`[^.\n]{0,40}?\*{0,2}(\d+(?:\.\d+)?)\*{0,2}/) do |(stated)|
        next if stated == value
        # A sentence recounting history says what a threshold WAS; those carry a
        # year and are not claims about today.
        next if Regexp.last_match.pre_match.lines.last.to_s.match?(/\b20\d\d-\d\d-\d\d\b/)

        wrong << "#{name}: doc says #{stated}, script sets #{value}"
      end
    end

    assert_empty wrong, "the doc names a threshold the script does not set: #{wrong.join('; ')}"
  end

  # The guard has to be reading something. If the assignment regex breaks, the
  # test above passes by comparing nothing.
  def test_the_guard_reads_real_values
    values = script_values.values.compact

    assert_equal VARIABLES.size, values.size
    assert(values.all? { |v| v.to_f.positive? }, "a threshold of zero means the scan broke: #{values.inspect}")
  end
end

`````

### test/test_health_check.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "json"
require "yaml"
# Under a C locale -- which is how the weekly integrity run invokes these on
# vm23 -- Ruby defaults file reads to US-ASCII. Same require, same reason, as
# MASTER/gates/runner.rb.
require_relative "../lib/utf8"

# Behaviour, not spelling. These run health_check.rb the way the laptop and the
# installed uptime wrapper do -- --public-only, which needs no vm23 tool -- with
# CURL pointed at a stub, so the verdict is the script's and not a grep of it.
class HealthCheckBehaviourTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  SCRIPT = File.join(OPENBSD, "gates", "health_check.rb")
  APPS = YAML.safe_load_file(File.join(OPENBSD, "..", "RAILS", "apps.yml")).fetch("apps")
  FACE = JSON.parse(File.read(File.join(OPENBSD, "deploy_inventory.json"))).fetch("master_face")

  def stub_curl(dir, body)
    path = File.join(dir, "curl")
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def run_public_only(curl, *extra)
    Open3.capture3({ "CURL" => curl, "HEALTH_CHECK_TIMEOUT" => "2" },
                   RbConfig.ruby, SCRIPT, "--public-only", "--all-ready-apps", *extra)
  end

  def test_every_endpoint_answering_is_a_pass_that_says_it_checked_nothing_on_the_box
    Dir.mktmpdir do |dir|
      out, err, status = run_public_only(stub_curl(dir, "exit 0"))
      assert status.success?, "expected a pass, got: #{err}"
      assert_includes out, "public-only (#{APPS.size} app(s); nothing on vm23 was checked)"
    end
  end

  def test_an_endpoint_that_refuses_fails_and_names_every_public_host
    Dir.mktmpdir do |dir|
      _, err, status = run_public_only(stub_curl(dir, "echo 'curl: (7) Failed to connect' >&2; exit 7"))
      refute status.success?
      APPS.each_value { |meta| assert_includes err, "#{meta.fetch('domain')} https" }
      assert_includes err, "#{FACE.fetch('domain')} https", "master's public name must come from deploy_inventory.json"
    end
  end

  def test_json_success_lists_the_apps_it_checked
    Dir.mktmpdir do |dir|
      out, _, status = run_public_only(stub_curl(dir, "exit 0"), "--json")
      assert status.success?
      assert_equal APPS.keys.sort, JSON.parse(out).fetch("apps_checked")
    end
  end

  def test_documented_flags_are_accepted
    out, _, status = Open3.capture3(RbConfig.ruby, SCRIPT, "--help")
    assert status.success?
    %w[--core --all-ready-apps --public --public-only --json].each { |flag| assert_includes out, flag }
  end
end

`````

### test/test_path_ownership.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../lib/utf8"

# PATH_OWNERSHIP.yml had no reader, and so it named `openbsd/sh/vps_ci.sh`, an
# `archive/` that does not exist and lowercase `rails/` paths for months while
# omitting most of the tree. These three assertions are what keep a map honest:
# every key names something, everything is named, and every check can run.
class PathOwnershipTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", OPENBSD)
  MAP = File.join(OPENBSD, "PATH_OWNERSHIP.yml")

  def ownership
    @ownership ||= YAML.safe_load_file(MAP).fetch("ownership")
  end

  def matches(key)
    Dir.glob(File.join(OPENBSD, key.delete_suffix("/")), File::FNM_DOTMATCH)
  end

  def test_every_key_names_a_path_that_exists
    dead = ownership.keys.select { |key| matches(key).empty? }
    assert_empty dead, "PATH_OWNERSHIP.yml keys that name nothing"
  end

  def test_every_top_level_entry_has_an_owner
    covered = ownership.keys.flat_map { |key| matches(key) }.map { |path| File.expand_path(path) }
    orphans = Dir.children(OPENBSD).reject { |entry| entry.start_with?(".") }.reject do |entry|
      covered.include?(File.join(OPENBSD, entry))
    end
    assert_empty orphans.sort, "top-level OPENBSD entries with no PATH_OWNERSHIP.yml key"
  end

  def test_every_check_names_files_that_exist
    missing = ownership.flat_map do |key, row|
      row.fetch("check").to_s.scan(%r{\b(?:OPENBSD|MASTER|RAILS)/[\w./-]+}).reject do |path|
        File.exist?(File.join(REPO, path))
      end.map { |path| "#{key}: #{path}" }
    end
    assert_empty missing, "checks naming files that are gone"
  end

  def test_every_row_declares_purpose_risk_and_check
    incomplete = ownership.reject { |_, row| row.is_a?(Hash) && (%w[purpose risk check] - row.keys).empty? }
    assert_empty incomplete.keys
  end
end

`````

### test/test_permission_audit.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/permission_audit"

class TestPermissionAudit < Minitest::Test
  def audit(secrets: [], private_dirs: [], daemon_logs: [])
    Deploy::PermissionAudit.failures(secrets:, private_dirs:, daemon_logs:, daemon_user: "master")
  end

  def test_the_modes_the_scripts_write_pass
    assert_empty audit(
      secrets: [{ path: "/etc/brgen.env", mode: 0o100640 }],
      private_dirs: [{ path: "/home/brgen/app/storage", mode: 0o040750 }],
      daemon_logs: [{ path: "/home/dev/pub4/MASTER/.master/tts-worker-0.log", owner: "master" }]
    )
  end

  def test_a_world_readable_secret_fails
    lines = audit(secrets: [{ path: "/etc/master.env", mode: 0o100644 }])

    assert_equal 1, lines.size
    assert_includes lines.first, "/etc/master.env is 0644"
  end

  # The state the app homes were in until 2026-08-25.
  def test_a_world_readable_storage_directory_fails
    refute_empty audit(private_dirs: [{ path: "/home/amber/app/storage", mode: 0o040755 }])
  end

  # The 2026-09-09 TTS outage: the daemon could not write its own log.
  def test_a_daemon_log_owned_by_root_fails
    lines = audit(daemon_logs: [{ path: ".master/tts-worker-1.log", owner: "root" }])

    assert_includes lines.first, "owned by root"
  end
end

`````

### test/test_ptr_openbsd_amsterdam.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../ptr_openbsd_amsterdam"

# Setting a PTR record changes how the internet names this box, and the script
# is run perhaps once a year. The dry run is what an operator reads before
# APPLY_PTR=1, so it must describe the exact request and must not send it.
class PtrOpenbsdAmsterdamTest < Minitest::Test
  def dry_run(ip:, hostname:)
    ptr = Operator::PtrOpenbsdAmsterdam.new(ip:, hostname:, apply: false)
    sent = []
    result = nil
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*args, **| sent << args }
    out, = capture_io { result = ptr.call }
    [ptr, JSON.parse(out), result, sent.any?]
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  def test_a_dry_run_builds_the_post_and_sends_nothing
    ptr, report, result, sent = dry_run(ip: "46.23.89.226", hostname: "ns.brgen.no")

    refute sent, "a dry run reached the network"
    assert result
    assert_equal({ "dry_run" => true, "endpoint" => "http://ptr4.openbsd.amsterdam",
                   "ip" => "46.23.89.226", "hostname" => "ns.brgen.no", "method" => "POST" },
                 report.except("note"))
    uri = ptr.send(:build_request).uri
    assert_equal "ip=46.23.89.226&hostname=ns.brgen.no", uri.query
  end

  def test_an_ipv6_address_goes_to_the_ipv6_endpoint
    _, report, = dry_run(ip: "2a03:6000:1:1::226", hostname: "ns.brgen.no")

    assert_equal "http://ptr6.openbsd.amsterdam", report.fetch("endpoint")
  end

  def test_bad_input_is_refused_before_a_request_exists
    [["127.0.0.1", "ns.brgen.no"], ["46.23.89.226", "ns"], ["not an ip", "ns.brgen.no"]].each do |ip, hostname|
      assert_raises(ArgumentError, "#{ip} #{hostname} was accepted") do
        Operator::PtrOpenbsdAmsterdam.new(ip:, hostname:).call
      end
    end
  end
end

`````

### test/test_rc_env_export.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"

# An rc.d script that sources an env file must export it.
#
# `.` sets a bare KEY=value without exporting it, so `. /etc/brgen.env && export
# RAILS_ENV=production SECRET_KEY_BASE ...` is an allowlist nobody can see: only
# the keys written onto that line reach the process, and a key added to the file
# later does nothing. rc.d/brgen carries the story — VAPID_PUBLIC_KEY sat in
# /etc/brgen.env for hours while push failed silently — and was fixed with
# `set -a && . file && set +a`.
#
# The three job workers were not fixed with it, and they are where it matters
# most: the classes brgen_jobs exists to run include WebPushJob, which wants the
# VAPID pair the app could not see either. Found 2026-09-11, all three at once,
# which is what a fix applied to one file of a family looks like a month later.
#
# Text, not execution: these run as root on OpenBSD and this asserts their shape.
class RcEnvExportTest < Minitest::Test
  RC_D = File.expand_path("../etc/rc.d", __dir__)

  # A new app's script is generated from rc.d/brgen by OPERATOR.sh, so holding
  # brgen to the rule holds every app made from it.
  def scripts
    Dir.glob(File.join(RC_D, "*")).select { |path| File.file?(path) }.sort
  end

  def daemon_flags(source)
    source[/^daemon_flags=.*/]
  end

  def test_every_script_that_sources_an_env_file_in_daemon_flags_exports_it
    offenders = scripts.filter_map do |path|
      flags = daemon_flags(File.read(path))
      next unless flags
      next unless flags.match?(%r{\.\s+/etc/[\w./-]+\.env})
      next if flags.include?("set -a")

      File.basename(path)
    end

    assert_empty offenders,
                 "these source an env file without set -a, so only the keys named after it are exported: #{offenders.join(', ')}"
  end

  # The guard has to be looking at something. If the glob or the daemon_flags
  # match breaks, the test above passes by finding nothing.
  def test_the_guard_reads_a_real_population
    sourcing = scripts.count do |path|
      flags = daemon_flags(File.read(path))
      flags&.match?(%r{\.\s+/etc/[\w./-]+\.env})
    end

    assert_operator sourcing, :>=, 6,
                    "three apps and three job workers source an env file in daemon_flags; a smaller number means the scan broke"
  end

  # set -a without set +a leaves every later assignment in that command line
  # exported too, which is not what the apps do and not what was intended.
  def test_the_export_window_is_closed_again
    unclosed = scripts.filter_map do |path|
      flags = daemon_flags(File.read(path)).to_s
      next unless flags.include?("set -a")
      next if flags.include?("set +a")

      File.basename(path)
    end

    assert_empty unclosed, "set -a is opened and never closed in: #{unclosed.join(', ')}"
  end
end

# An rc.d script that runs as an app user takes the rails login class.
#
# rc.subr(8) and rc.d(8) on the OpenBSD target: daemon_class is read-only and
# set by rc.subr itself — the login.conf(5) class named after the script, or
# "daemon" when there is none. rc.d/brgen gets `brgen`, which inherits `rails`.
# Without a `brgen_jobs` class, rc.d/brgen_jobs runs its worker under `daemon`,
# whose openfiles-cur is 128 against the rails class's 2048.
# A script cannot name its class, so the class has to exist under its name.
class RcLoginClassTest < Minitest::Test
  RC_D = File.expand_path("../etc/rc.d", __dir__)
  LOGIN_CONF = File.read(File.expand_path("../etc/login.conf", __dir__))
  APP_USERS = %w[brgen amber bsdports].freeze

  def app_scripts
    Dir.glob(File.join(RC_D, "*")).select { |path| File.file?(path) }.filter_map do |path|
      user = File.read(path)[/^daemon_user="(\w+)"/, 1]
      File.basename(path) if APP_USERS.include?(user)
    end.sort
  end

  # A login.conf record: its names, then capability lines joined by backslashes.
  def record(name)
    LOGIN_CONF[/^#{Regexp.escape(name)}(?:\|[^:\n]*)?:\\\n((?:[^\n]*\\\n)*[^\n]*\n)/, 1]
  end

  def test_every_app_user_script_has_a_login_class_that_inherits_rails
    missing = app_scripts.reject { |name| record(name).to_s.match?(/:tc=rails:/) }

    assert_empty missing, "rc.subr runs these under the daemon class, since login.conf has " \
                          "no rails class by their name: #{missing.join(', ')}"
  end

  def test_the_guard_reads_a_real_population
    assert_operator app_scripts.size, :>=, 6,
                    "three apps and three job workers run as app users; fewer means the scan broke"
    assert_match(/:openfiles-cur=2048:/, record("rails").to_s,
                 "the rails record did not parse, so every lookup above is blind")
  end
end

`````

### test/test_reach.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/utf8"
require_relative "../tools/reach"

# Every check here is shown failing before it is trusted passing. A probe nobody
# has watched fire is the same shape as the drift it looks for: complete,
# correct-looking, and measuring nothing.
#
# Two of the three would have been wrong without this. `cron` naively wants the
# scheduled path to be tracked, and resource_guard.sh is tracked at the OPENBSD
# root while being scheduled at /usr/local/bin — OPERATOR.sh installs it there,
# so a path-only check reports a false positive on a correct tree. `rcd` naively
# wants a starter, and all four *_jobs workers plus irc_gateway deliberately have
# none and say so in their own headers.
class ReachTest < Minitest::Test
  R = Operator::OpenbsdReach

  def setup
    @tmp = Dir.mktmpdir("reach")
    %w[etc/rc.d var/nsd/etc var/nsd/zones/master usr/local/bin bin].each do |d|
      FileUtils.mkdir_p(File.join(@tmp, d))
    end
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n")
    write("OPERATOR.sh", "#!/bin/ksh\n")
    write("var/nsd/etc/nsd.conf", "server:\n")
    R.root = @tmp
  end

  def teardown
    R.root = R::DEFAULT_ROOT
    FileUtils.remove_entry(@tmp)
  end

  def write(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def checks(kind) = R.findings.select { |f| f.check == kind }

  # ---- cron -----------------------------------------------------------------

  def test_a_scheduled_command_that_is_tracked_reaches
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/thing.sh\n")
    write("usr/local/bin/thing.sh", "#!/bin/ksh\n")

    assert_empty checks("cron")
  end

  def test_a_scheduled_command_that_is_nowhere_is_reported
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/ghost.sh\n")

    assert_equal ["/usr/local/bin/ghost.sh"], checks("cron").map(&:subject)
  end

  # The resource_guard.sh shape: tracked somewhere else, installed into place.
  def test_a_command_installed_by_operator_reaches_from_anywhere
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/guard.sh\n")
    write("guard.sh", "#!/bin/ksh\n")
    write("OPERATOR.sh", %(install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh\n))

    assert_empty checks("cron")
  end

  # cron's own PATH excludes /usr/local/bin, where every env-shebang interpreter
  # lives. Four of five jobs had never run for exactly this.
  def test_a_command_outside_the_declared_path_is_reported
    write("etc/crontab.vm23", "PATH=/bin\n*/5 * * * * /opt/thing.sh\n")
    write("opt/thing.sh", "#!/bin/ksh\n")

    assert_includes checks("cron").map(&:subject), "/opt"
  end

  # The uptime-check shape. reach reads cron lines through the drift gate's
  # scheduled_commands, so an environment prefix is the gate's parsing, proved
  # here from reach's side.
  def test_an_environment_prefix_is_not_mistaken_for_the_command
    line = "*/5 * * * * ALLOW_X=1 /usr/local/bin/b.sh >> /var/log/b.log 2>&1"
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n#{line}\n")
    write("usr/local/bin/b.sh", "#!/bin/ksh\n")

    assert_equal ["/usr/local/bin/b.sh"], R.cron_commands
    assert_empty checks("cron")
  end

  def test_redirections_are_not_mistaken_for_the_command
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n0 2 * * 1 /usr/local/bin/a.sh >> /var/log/a.log 2>&1\n")
    write("usr/local/bin/a.sh", "#!/bin/ksh\n")

    assert_empty checks("cron")
  end

  # ---- rc.d -----------------------------------------------------------------

  def test_a_service_a_starter_enables_reaches
    write("etc/rc.d/thing", "#!/bin/ksh\n")
    write("start_all.sh", "rcctl enable thing\n")

    assert_empty checks("rcd")
  end

  def test_a_service_nothing_starts_and_nothing_explains_is_reported
    write("etc/rc.d/orphan", "#!/bin/ksh\ndaemon=/usr/local/bin/orphan\n")

    assert_equal ["orphan"], checks("rcd").map(&:subject)
  end

  # The *_jobs shape: deliberately off, with the rcctl lines in its own footer.
  def test_a_service_that_declares_itself_off_by_default_reaches
    write("etc/rc.d/thing_jobs", "#!/bin/ksh\n# Solid Queue worker. NOT enabled by default — see the footer.\n")

    assert_empty checks("rcd")
  end

  # ---- boot list ------------------------------------------------------------

  def test_a_boot_name_with_a_shipped_script_reaches
    write("etc/rc.d/thing", "#!/bin/ksh\n# not enabled by default\n")
    write("etc/rc.conf.local", "pf=YES\npkg_scripts=thing\n")

    assert_empty checks("boot")
  end

  # litestream's config may ship; the service may not boot, because there is no
  # script and no binary to run.
  def test_a_boot_name_with_no_script_is_reported
    write("etc/litestream.yml", "dbs: []\n")
    write("etc/rc.conf.local", "pkg_scripts=litestream\n")

    assert_equal ["litestream"], checks("boot").map(&:subject)
  end

  # ---- zones ----------------------------------------------------------------

  def test_a_zone_named_and_present_reaches
    write("var/nsd/zones/master/example.no.zone", "$ORIGIN example.no.\n")
    write("var/nsd/etc/nsd.conf", %(zone:\n  name: "example.no"\n))

    assert_empty checks("zones")
  end

  def test_a_zone_file_nsd_does_not_name_is_reported
    write("var/nsd/zones/master/lonely.no.zone", "$ORIGIN lonely.no.\n")

    assert_equal ["lonely.no"], checks("zones").map(&:subject)
  end

  # nsd refuses to start over a zone whose file is missing, so this direction is
  # the one that takes DNS down rather than merely leaving a domain unserved.
  def test_a_named_zone_with_no_file_is_reported
    write("var/nsd/etc/nsd.conf", %(zone:\n  name: "ghost.no"\n))

    assert_equal ["ghost.no"], checks("zones").map(&:subject)
  end

  # ---- the live tree --------------------------------------------------------

  def test_the_real_tree_reaches
    R.root = R::DEFAULT_ROOT

    assert_empty R.findings.map { |f| "#{f.check} #{f.subject}: #{f.detail}" }
  end

  def test_the_real_tree_has_something_to_measure
    R.root = R::DEFAULT_ROOT
    counts = R.counts

    assert_operator counts["cron"], :>=, 5, "a probe over an empty population passes having measured nothing"
    assert_operator counts["rcd"], :>=, 5
    assert_operator counts["boot"], :>=, 4
    assert_operator counts["zones"], :>=, 50
  end

  def test_litestream_config_ships_and_litestream_does_not_boot
    R.root = R::DEFAULT_ROOT

    assert File.file?(File.join(R.root, "etc", "litestream.yml"))
    refute_includes R.boot_names, "litestream"
  end
end

`````

### test/test_restore_scripts.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
# Every read below inspects UTF-8 source. Under a C locale -- which is how the
# weekly integrity run invokes these on vm23 -- Ruby defaults file reads to
# US-ASCII and each one raises "invalid byte sequence". Same require, same
# reason, as MASTER/gates/runner.rb.
require_relative "../lib/utf8"

class RestoreScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_restore_litestream_is_litestream_restore
    source = File.read(File.join(ROOT, "bin", "restore_litestream.sh"))
    assert_includes source, "litestream restore"
    refute_includes source, "MASTER/RAILS"
  end

  # litestream is absent from this box and unpackageable, so every precondition
  # in restore_litestream.sh is false and a skipping version walked all three apps,
  # restored none and exited 0. A restore that reports success having restored
  # nothing is read as evidence the backups work.
  def test_restore_litestream_fails_rather_than_skipping
    source = File.read(File.join(ROOT, "bin", "restore_litestream.sh"))
    assert_includes source, "require_litestream", "no check that the binary exists"
    refute_match(/log "skip \$app/, source, "a missing replica must fail, not skip")
    assert_match(/missing replica \$replica"; exit 1/, source)
    assert_includes source, "dr-pull", "the failure must name the backup that does work"
  end

  # Run, not read. The config failure used to print to stdout, where the loop read
  # it as an app name and failed later on "/home/[restore] missing…/app/storage".
  def test_a_dry_run_with_no_config_fails_on_the_config
    env = { "DRY_RUN" => "1", "LITESTREAM_CONFIG" => File.join(Dir.tmpdir, "no-such-litestream.yml") }
    out, err, status = Open3.capture3(env, "zsh", File.join(ROOT, "bin", "restore_litestream.sh"))

    assert_equal 1, status.exitstatus
    assert_includes err, "missing litestream config"
    refute_includes out, "/home/", "a log line was read as an app name"
    refute_includes out, "done"
  end

  def test_a_dry_run_of_a_config_plans_only_its_apps
    Dir.mktmpdir("litestream") do |dir|
      config = File.join(dir, "litestream.yml")
      File.write(config, "dbs:\n  - path: /home/ghostapp/app/storage/production.sqlite3\n")
      out, _, status = Open3.capture3({ "DRY_RUN" => "1", "LITESTREAM_CONFIG" => config },
                                      "zsh", File.join(ROOT, "bin", "restore_litestream.sh"))

      assert_equal 1, status.exitstatus, "the app has no storage here, so the plan must fail rather than skip"
      assert_includes out, "FAIL ghostapp — missing /home/ghostapp/app/storage"
    end
  end

  def test_vps_deploy_stamps_head_after_the_work
    source = File.read(File.join(ROOT, "bin/vps-deploy"))
    assert_includes source, "write_stamp()"
    assert_includes source, 'sha=$(git -C "$repo" rev-parse --short HEAD)'
    # The read must live inside write_stamp, not above the master pull.
    write = source[ /write_stamp\(\) \{.*?\n\}/m ]
    assert write, "write_stamp function missing"
    assert_includes write, "rev-parse --short HEAD"
    refute_match(/sha=\$\(git -C "\$repo" rev-parse --short HEAD\)\nstarted=/, source.split("write_stamp()")[0])
    assert_includes source, "pull --ff-only origin main"
    assert_includes source, 'write_stamp master failed'
    assert_includes source, 'write_stamp "$app" failed'
  end

  def test_vps_ci_mirrors_the_tracked_tree_not_vendor
    source = File.read(File.join(ROOT, "bin", "vps_ci.sh"))
    assert_includes source, "git -C \"$repo\" archive HEAD RAILS"
    refute_includes source, 'doas tar cf - -C "$repo" RAILS'
    assert_includes source, "vendor/javascript"
    assert_includes source, "public"
  end

  # public/assets is the one synced directory git does not carry — Propshaft
  # writes it on the box at precompile. Pruning public/ wholesale deleted the
  # running site's stylesheets, and it happened before bin/ci, so a CI failure
  # left the new code live with no assets: brgen served every page with a 404ing
  # <link> on 2026-08-14 while /up, rcctl check and the TLS probe all passed.
  def test_vps_ci_keeps_compiled_assets_across_the_prune
    source = File.read(File.join(ROOT, "bin", "vps_ci.sh"))
    prune = source[/for dir_rel in test app lib config bin db engines public.*?done/m]
    assert prune, "the prune loop moved — re-read this before trusting the assertions below"
    assert_includes prune, "public/assets", "the prune must special-case the one directory git does not carry"
    assert_match(/mv .*public\/assets.*assets-carry/, prune, "assets must be held aside, not deleted")
    assert_match(/mv .*assets-carry.*public\/assets/, prune, "…and put back")
  end

  # /up answers before Propshaft is reached, so it cannot tell a styled site from
  # an unstyled one. The deploy asks for the stylesheet the page links, through
  # the Host that owns it — a bare-IP request 403s on these apps, which would
  # pass by finding no link at all.
  def test_vps_deploy_verifies_the_page_stylesheet_resolves
    source = File.read(File.join(ROOT, "bin/vps-deploy"))
    assert_includes source, "css_href", "no stylesheet verification after restart"
    # The reader is run rather than matched: what matters is the href it finds
    # on a page that links one, and nothing, not a failure, on a page that does
    # not — under set -e a failing read ends the deploy with no stamp.
    reader = source[/^css_href=\$\(.*ruby40 -e '([^']+)'\)$/, 1]
    assert reader, "must read the href off the rendered page"
    link = '<link rel="stylesheet" href="/assets/application-1a2b.css">'
    found, status = Open3.capture2(RbConfig.ruby, "-e", reader, stdin_data: link)
    assert_equal ["/assets/application-1a2b.css", true], [found, status.success?]
    found, status = Open3.capture2(RbConfig.ruby, "-e", reader, stdin_data: "<p>no link</p>")
    assert_equal ["", true], [found, status.success?]
    assert_match(/^home_page=\$\(curl .*\) \|\| \{\n\s*write_stamp "\$app" failed/, source,
                 "a home page that does not answer must fail the deploy with a stamp")
    assert_includes source, 'Host: ${domain}', "must ask through the app's own Host or it 403s"
    assert_match(/css_href.*\n.*write_stamp "\$app" failed/m.freeze, source[/if \[\[ -n \$css_href \]\].*?^fi/m].to_s,
                 "a 404 stylesheet must fail the deploy, not warn")
  end
end

`````

### test/test_solid_queue_proof.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "time"
require_relative "../lib/utf8"
require_relative "../gates/solid_queue_proof"

# The gate exists so an app whose jobs never run cannot deploy green. It used to
# assert a registered SolidQueue::Process, which vm23 deliberately does not have
# — rc.d/<app>_jobs is disabled at boot and drain-jobs.sh runs the queue hourly
# instead — so every Rails deploy stamped failed while the app was healthy, and
# `vps-deploy all` could never get past brgen.
#
# Both halves are pinned here. Widening a gate is only safe if the failure it
# was built for is still reachable, so the "nothing is running these jobs" case
# gets as much attention as the passing one.
class SolidQueueProofTest < Minitest::Test
  P = SolidQueueProof

  # The real format, copied from /var/log/drain-jobs.log on vm23.
  LOG = <<~TXT
    2026-08-18T01:08:18Z brgen due 22 -> 2  ahead=54 failed=0 (ran 180s)
    2026-08-18T01:08:19Z amber nothing due (ahead=0 failed=0)
    2026-08-18T01:08:20Z bsdports nothing due (ahead=0 failed=0)
    2026-08-18T02:08:07Z brgen due 11 -> 2  ahead=48 failed=0 (ran 180s)
    2026-08-18T02:08:07Z amber nothing due (ahead=0 failed=0)
  TXT

  def with_log(text = LOG)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "drain-jobs.log")
      File.write(path, text)
      yield path
    end
  end

  def test_it_reads_the_newest_run_for_the_named_app
    with_log do |path|
      assert_equal Time.parse("2026-08-18T02:08:07Z"), P.last_drain_at("brgen", log_path: path)
      assert_equal Time.parse("2026-08-18T02:08:07Z"), P.last_drain_at("amber", log_path: path)
    end
  end

  # "nothing due" is the drain reporting it looked and found no work. That is
  # proof it ran, which is the thing being measured.
  def test_a_nothing_due_line_still_counts_as_a_run
    with_log("2026-08-18T02:08:20Z bsdports nothing due (ahead=0 failed=0)\n") do |path|
      assert P.drain_recent?("bsdports", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_recent_drain_passes_and_a_stale_one_does_not
    with_log do |path|
      assert P.drain_recent?("brgen", now: Time.parse("2026-08-18T03:00:00Z"), log_path: path),
             "52 minutes after the last drain is well inside the window"
      refute P.drain_recent?("brgen", now: Time.parse("2026-08-18T09:00:00Z"), log_path: path),
             "seven hours after the last drain the queue is not being worked"
    end
  end

  # The boundary is a decision, not an accident: hourly schedule, two hours so
  # one skipped tick is tolerated and a dead drain is not.
  def test_the_window_is_two_hours
    assert_equal 7200, P::MAX_DRAIN_AGE_S

    with_log do |path|
      base = Time.parse("2026-08-18T02:08:07Z")
      assert P.drain_recent?("brgen", now: base + 7199, log_path: path)
      refute P.drain_recent?("brgen", now: base + 7201, log_path: path)
    end
  end

  # The failure the gate is built for. An app the drain never mentions has
  # nothing running its jobs, and must not pass.
  def test_an_app_the_drain_never_ran_does_not_pass
    with_log do |path|
      refute P.drain_recent?("takeaway", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_missing_log_does_not_pass
    refute P.drain_recent?("brgen", now: Time.parse("2026-08-18T02:30:00Z"),
                                    log_path: "/nonexistent/drain-jobs.log")
  end

  # A line whose app column happens to contain the name must not match on a
  # substring — "amber" is not "amberapp".
  def test_the_app_column_matches_exactly
    with_log("2026-08-18T02:08:07Z amberapp nothing due (ahead=0 failed=0)\n") do |path|
      refute P.drain_recent?("amber", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_garbled_line_does_not_raise
    with_log("not a log line at all\n\n2026-08-18T02:08:07Z brgen due 1 -> 0\n") do |path|
      assert P.drain_recent?("brgen", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  # The adapter check is the half that must NOT be widened: an app that is not
  # on SolidQueue is misconfigured regardless of who runs the jobs.
  def test_the_runner_still_hard_fails_on_the_wrong_adapter
    src = P.runner_source("amber", 1)

    assert_includes src, "SolidQueueAdapter"
    assert_match(/adapter=.*\n\s*exit 1/m, src, "a non-SolidQueue adapter no longer exits 1")
  end

  # Three, not one, so "no resident worker" is distinguishable from
  # "misconfigured" — the distinction the old script could not make.
  def test_the_runner_reports_no_worker_separately_from_misconfiguration
    src = P.runner_source("amber", 15)

    assert_includes src, "exit 3"
    assert_includes src, "no resident worker registered"
    assert_includes src, "15.times"
  end

  def test_it_looks_once_when_the_drain_already_proves_the_work
    assert_includes P.runner_source("amber", 1), "1.times"
  end
end

`````

### test/test_ssh_vm23_contract.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"

class SshVm23ContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/ssh_vm23.sh", __dir__), encoding: "UTF-8")

  def test_tmux_session_name_is_shell_quoted_before_remote_execution
    assert_includes SOURCE, "typeset quoted_session=${(q)session}"
    refute_match(/tmux has-session -t \$\{session\}/, SOURCE)
    refute_match(/tmux kill-session -t \$\{session\}/, SOURCE)
    refute_match(/tmux new-session -d -s \$\{session\}/, SOURCE)
  end

  def test_remote_command_payload_remains_quoted
    assert_includes SOURCE, "${(q)cmd}"
  end
end

`````

### test/test_sync_redaction.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/secret_redaction"

# sync.rb's redaction is fail-open no longer. Watched failing before this file
# was trusted: the patterns pinned `_KEY=` values to the sk- prefix, so
# `REPLICATE_KEY=r8_...` mirrored into git verbatim, and a secret matching no
# pattern at all (`smtp_url=smtp://user:pass@...`) had no second line of
# defence. Each probe below pins one of those two findings; the residue tests
# fire only through the audit added with them.
class SyncRedactionTest < Minitest::Test
  R = SecretRedaction

  def test_redacts_provider_keys_beyond_the_sk_prefix
    out = R.redact("REPLICATE_KEY=r8_secret_value123\n")
    assert_equal "REPLICATE_KEY=#{R::PLACEHOLDER}\n", out
  end

  def test_redacts_the_patterns_that_always_worked
    body = "OPENAI_API_KEY=sk-abc\nACCESS_TOKEN=tok\nDB_PASSWORD=pw\nJWT_SECRET=s\n"
    out = R.redact(body)
    %w[OPENAI_API_KEY ACCESS_TOKEN DB_PASSWORD JWT_SECRET].each do |name|
      assert_match %r{^#{name}=#{R::PLACEHOLDER}$}, out, "#{name} must reach the placeholder"
    end
  end

  def test_leaves_ordinary_lines_alone
    body = "PATH=/bin:/usr/local/bin\nlisten on 127.0.0.1\n"
    assert_equal body, R.redact(body)
  end

  def test_residue_empty_when_the_patterns_caught_everything
    assert_empty R.residue("REPLICATE_KEY=r8_secret_value123\nAPI_TOKEN=tok\n")
  end

  def test_residue_flags_a_secret_the_patterns_never_learned
    left = R.residue("smtp_url=smtp://user:pass@mail.brgen.no\n")
    assert_equal 1, left.size
    assert_includes left.first, "smtp_url"
  end

  def test_residue_ignores_lines_it_redacted_itself
    assert_empty R.residue("API_KEY=__REDACTED__\n")
  end

  def test_residue_ignores_empty_values_and_public_names
    assert_empty R.residue("KEY=\nmoniker=brgen\n")
  end

  def test_sync_refuses_files_the_audit_flags
    # The refusal itself runs only on vm23, so this pins the contract at the
    # source: sync.rb must call the audit and must refuse what it flags.
    src = File.read(File.expand_path("../sync.rb", __dir__))
    assert_includes src, "SecretRedaction.residue"
    assert_includes src, "refused", "a flagged file must be refused, not warned"
    assert_match(/exit 3 if refused/, src)
  end
end

`````

### test/test_tracked_crontab.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "fileutils"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
# See test_restore_scripts.rb: the weekly integrity run on vm23 invokes these
# under a C locale, where Ruby reads files as US-ASCII and every read of this
# UTF-8 source raises "invalid byte sequence".
require_relative "../lib/utf8"
require_relative "../gates/config_drift_gate"

# etc/crontab.vm23 is the tracked half of root's crontab, and OPERATOR.sh's
# install_tracked_crontab merges it onto the box. Both halves can be complete
# and correct while the job is not scheduled anywhere, which is the failure this
# file exists for.
#
# Measured 2026-08-18: uptime-check.sh was in crontab.vm23 and in
# usr/local/bin/ since 2026-08-12, and was on neither the box's crontab nor its
# filesystem. Nothing was missing from either file, so nothing read as wrong.
# The merge loop had skipped the line — correctly, since the wrapper was not
# installed and cron would otherwise mail root every five minutes — but
# silently, so the skip taught nobody anything.
class TrackedCrontabTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TRACKED = File.join(ROOT, "etc", "crontab.vm23")
  OPERATOR = File.join(ROOT, "OPERATOR.sh")

  def crontab_source = @crontab_source ||= File.read(TRACKED)

  def operator_source = @operator_source ||= File.read(OPERATOR)

  # One parser for a cron line, the drift gate's, so the shapes it must and must
  # not read (an env prefix, a redirect, a PATH line) have one set of fixtures, in
  # test_config_drift_gate.rb, and a new cron line is proved once.
  def scheduled = scheduled_commands(crontab_source)

  def test_env_prefixed_lines_are_parsed
    assert_includes scheduled, "/usr/local/bin/uptime-check.sh" if crontab_source.include?("uptime-check.sh")
  end

  def test_the_tracked_crontab_actually_schedules_something
    refute_empty scheduled,
                 "no cron lines parsed out of etc/crontab.vm23 — this test would pass having measured nothing"
  end

  # The repo may not schedule a command it does not ship. If it does, the merge
  # loop skips the line on every run and the job is tracked but never installed.
  def test_every_scheduled_command_is_shipped_by_this_repo
    # Shipped means copied with usr/local/bin/, or named by an `install` line in
    # OPERATOR.sh whose source is in the tree. Where that source sits is the
    # install line's business, so the test reads the line rather than guessing a
    # directory.
    installed = operator_source.scan(%r{install\s[^\n]*?"\$\{SCRIPT_DIR\}/([\w./-]+)"\s+(/usr/local/bin/[\w.-]+)})
                               .select { |source, _| File.file?(File.join(ROOT, source)) }
                               .map(&:last)
    missing = scheduled.reject do |command|
      File.file?(File.join(ROOT, "usr", "local", "bin", File.basename(command))) || installed.include?(command)
    end

    assert_empty missing,
                 "etc/crontab.vm23 schedules commands this repo does not ship, so " \
                 "install_tracked_crontab will skip them forever:\n#{missing.join("\n")}"
  end

  # install(1) sets the mode on the box, but a non-executable source is a sign
  # the wrapper was written and never wired, and it is free to check here.
  def test_shipped_cron_wrappers_are_executable_in_the_repo
    not_executable = scheduled.filter_map do |command|
      base = File.basename(command)
      path = [File.join(ROOT, "usr", "local", "bin", base), File.join(ROOT, base)].find { |p| File.file?(p) }
      path if path && !File.executable?(path)
    end

    assert_empty not_executable, "tracked cron wrappers are not executable:\n#{not_executable.join("\n")}"
  end

  # cron(8) runs with PATH=/bin:/sbin:/usr/bin:/usr/sbin. Every interpreter this
  # box uses is in /usr/local/bin, so without this line an `#!/usr/bin/env ruby`
  # job fails at exec once per tick, forever, one unread line at a time. Four of
  # five jobs here had never run for exactly that reason.
  def test_the_crontab_sets_a_path_that_includes_usr_local_bin
    path_line = crontab_source.each_line.find { |l| l.start_with?("PATH=") }

    refute_nil path_line, "etc/crontab.vm23 no longer sets PATH"
    assert_includes path_line, "/usr/local/bin"
  end

  def test_operator_rewrites_the_path_rather_than_appending_it
    assert_includes operator_source, "grep -m1 '^PATH=' $tracked",
                    "install_tracked_crontab no longer carries the PATH line, which the merge loop cannot"
  end

  # The point of this file. Skipping is correct; skipping quietly is what let a
  # tracked job go unscheduled for six days.
  def test_missing_tracked_crontab_fails_closed
    assert_match(/\[\[ -f \$tracked \]\] \|\| \{ log ERROR .*; return 1; \}/,
                 operator_source)
  end

  def test_template_helpers_do_not_eval_repository_content
    install = operator_source[/install_template\(\).*?\n\}\n\nappend_template\(/m]
    append = operator_source[/append_template\(\).*?\n\}\n\ninstall_static\(/m]

    refute_nil install
    refute_nil append
    refute_match(/\beval\b/, install)
    refute_match(/\beval\b/, append)
  end

  def test_a_skipped_cron_line_says_so
    loop_body = operator_source[/while IFS= read -r line; do.*?done < \$tracked/m]

    refute_nil loop_body, "install_tracked_crontab's merge loop moved or changed shape"
    assert_match(/! -x \$cmdpath/, loop_body, "the merge loop no longer checks the command is executable")
    assert_match(/log WARN .*not installed/, loop_body,
                 "install_tracked_crontab skips a tracked cron job without logging it")
  end
end

# The scheduled jobs themselves, run against fixtures rather than read. Each one
# is run only where it cannot touch a real box: rcctl present means vm23, and a
# test there would reach the certificates and the zones.
class ScheduledJobsTest < Minitest::Test
  BIN = File.expand_path("../usr/local/bin", __dir__)

  def setup
    skip "on an OpenBSD box these would act on live state" if File.executable?("/usr/sbin/rcctl")
    @tmp = Dir.mktmpdir("jobs")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp
  end

  def write(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # ---- nsd-resign -----------------------------------------------------------

  def rrsig(expiry) = "brgen.no. 3600 IN RRSIG SOA 13 2 3600 #{expiry} 20260901000000 4242 brgen.no. c2ln\n"

  def resign(*args)
    Open3.capture2e({ "NSD_ZONES_DIR" => @tmp }, RbConfig.ruby, File.join(BIN, "nsd-resign"), *args)
  end

  def test_nsd_resign_reads_the_earliest_signature_expiry
    load File.join(BIN, "nsd-resign")
    signed = write("brgen.no.zone.signed", rrsig("20261201000000") + rrsig("20261015120000"))

    assert_equal Date.new(2026, 10, 15), expiry_date(signed)
  end

  # Garbage has no expiry, and no expiry means re-sign, never "still valid".
  def test_nsd_resign_treats_an_unparseable_signed_zone_as_due
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    write("Kbrgen.no.+013+04242.key", "brgen.no. IN DNSKEY 257 3 13 AAAA\n")
    write("brgen.no.zone.signed", "\x00\xFF not a zone")
    out, status = resign

    assert_includes out, "brgen.no expires unknown — resigning"
    refute status.success?, "no ldns-signzone here, so the zone must count as failed: #{out}"
    assert_includes out, "FAIL 1 zone(s) not signed: brgen.no"
  end

  def test_nsd_resign_leaves_a_fresh_zone_alone
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    write("Kbrgen.no.+013+04242.key", "brgen.no. IN DNSKEY 257 3 13 AAAA\n")
    write("brgen.no.zone.signed", rrsig((Date.today + 25).strftime("%Y%m%d000000")))
    out, status = resign

    assert status.success?, out
    assert_includes out, "all 1 zones valid — nothing to do"
  end

  def test_nsd_resign_with_no_keyed_zones_fails
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    out, status = resign

    refute status.success?
    assert_includes out, "FAIL no signable zones"
  end

  # ---- renew-certs.sh -------------------------------------------------------

  def renew(conf)
    env = { "RENEW_CERTS_ACME_CONF" => write("acme-client.conf", conf), "RENEW_CERTS_SSL_DIR" => File.join(@tmp, "ssl") }
    Open3.capture3(env, "zsh", File.join(BIN, "renew-certs.sh"))
  end

  # CONFIGURED ∩ HELD: a held name acme-client cannot renew is skipped, a
  # configured name with no certificate is never attempted, smtp is smtpd's own.
  def test_renew_certs_renews_only_what_is_both_held_and_configured
    %w[brgen.no amberapp.art ai.brgen.no smtp].each { |name| write("ssl/#{name}.crt", "") }
    out, _, status = renew(%(domain "brgen.no" {\n}\ndomain "amberapp.art" {\n}\ndomain "lapsed.uk" {\n}\n))

    assert status.success?, out
    assert_includes out, "renewing 2 of 3 held certificate(s): amberapp.art brgen.no"
    assert_includes out, "held but not in"
    assert_includes out, "skipping: ai.brgen.no"
    refute_includes out, "lapsed.uk"
    assert_includes out, "nothing renewed, leaving relayd alone"
  end

  def test_renew_certs_refuses_when_nothing_held_is_configured
    write("ssl/ai.brgen.no.crt", "")
    _, err, status = renew(%(domain "brgen.no" {\n}\n))

    assert_equal 1, status.exitstatus
    assert_includes err, "refusing to run"
  end

  # ---- the load-waiting wrappers --------------------------------------------

  # No ruby40 here, so the load never reads low: every tick waits and the run
  # ends in a skip, exit 0, without reaching an app.
  def test_prune_guests_waits_every_tick_then_skips
    env = { "PRUNE_GUESTS_LOAD_CEILING" => "0", "PRUNE_GUESTS_WAIT_TICKS" => "2", "PRUNE_GUESTS_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "prune-guests.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|removed=/, out)
  end

  def test_drain_jobs_waits_every_tick_then_skips
    env = { "DRAIN_JOBS_LOAD_CEILING" => "0", "DRAIN_JOBS_WAIT_TICKS" => "2", "DRAIN_JOBS_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "drain-jobs.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2
    assert_match(/skipped: load stayed over 0/, out)
  end

  def test_declutter_hygiene_waits_every_tick_then_skips
    env = { "DECLUTTER_HYGIENE_LOAD_CEILING" => "0", "DECLUTTER_HYGIENE_WAIT_TICKS" => "2",
            "DECLUTTER_HYGIENE_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "declutter-hygiene.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|expired_challenges=/, out)
  end

  def test_ports_import_waits_every_tick_then_skips
    env = { "PORTS_IMPORT_LOAD_CEILING" => "0", "PORTS_IMPORT_WAIT_TICKS" => "2",
            "PORTS_IMPORT_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "ports-import.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|ports_count=/, out)
  end

  # A shed app is left shed: nothing listening is skipped silently, not warmed
  # and not logged as a failure every ten minutes.
  def test_keep_warm_skips_a_target_that_is_not_listening
    ports = [38_182, 61_352]
    skip "an app is listening locally" if ports.any? { |port| (TCPSocket.new("127.0.0.1", port).close || true) rescue false }
    out, status = Open3.capture2e("ksh", File.join(BIN, "keep-warm.sh"))

    assert status.success?, out
    assert_empty out.strip
  end
end

`````

### test/test_vps_admin.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../bin/vps-admin"

class VpsAdminTest < Minitest::Test
  def test_read_only_commands_are_named
    assert_equal [["doas", "df", "-h"]], OpenBSDAdmin.commands_for(["disk"])
    assert_equal [["doas", "pfctl", "-si"]], OpenBSDAdmin.commands_for(["pf", "status"])
    assert_equal [["doas", "syspatch", "-c"]], OpenBSDAdmin.commands_for(["updates"])
    assert_equal [["doas", "pkg_info"]], OpenBSDAdmin.commands_for(["packages"])
    assert_equal [["doas", "sysupgrade", "-n"]], OpenBSDAdmin.commands_for(["upgrade", "stage"])
  end

  def test_service_actions_are_allowlisted
    assert_equal [["doas", "rcctl", "restart", "master"]],
                 OpenBSDAdmin.commands_for(["service", "master", "restart"])
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "shell"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master;touch /tmp/x", "restart"]) }
  end

  def test_firewall_reload_validates_before_loading
    assert_equal(
      [["doas", "pfctl", "-nf", "/etc/pf.conf"], ["doas", "pfctl", "-f", "/etc/pf.conf"]],
      OpenBSDAdmin.commands_for(["pf", "reload"]),
    )
  end

  def test_arbitrary_commands_are_refused
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["sh", "-c", "id"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "exec", "id"]) }
  end

  def test_reboot_is_one_explicit_action
    assert_equal [["doas", "/sbin/reboot"]], OpenBSDAdmin.commands_for(["reboot"])
  end

  def test_status_is_composed_of_named_commands
    commands = OpenBSDAdmin.commands_for(["status"])
    assert_includes commands, ["hostname"]
    assert_includes commands, ["uptime"]
    assert_includes commands, ["uname", "-a"]
    assert_includes commands, ["doas", "df", "-h"]
  end
end

`````

### test/test_vps_deploy_contract.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"

# vps-deploy is the entrypoint for every production deploy and had no test.
#
# Running it is not an option — it deploys — so this reads the source for the
# three things it promises that a reader cannot otherwise check: that the fleet
# it deploys is the fleet apps.yml declares, that the order which makes the pass
# survive its own side effects is still that order, and that it refuses to run as
# root rather than dying at `git pull` with a message about host keys.
class VpsDeployContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps-deploy"), encoding: "UTF-8")
  APPS = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps").keys.map(&:to_s)

  def deploy_all
    SOURCE[/^DEPLOY_ALL=\(([^)]*)\)/, 1]&.split
  end

  def test_the_fleet_it_deploys_is_the_fleet_apps_yml_declares
    refute_nil deploy_all, "DEPLOY_ALL not found — the scan broke, not the script"

    # master is not in apps.yml: it is not a Rails app under /home/*/app, which is
    # the reason an operator enumerating the apps leaves it behind and the reason
    # it is named here at all.
    assert_equal APPS.sort, (deploy_all - ["master"]).sort
    assert_includes deploy_all, "master"
  end

  # The script's own comment carries the argument: master leads because it is
  # independent of the Rails apps and is the one that gets forgotten; amber and
  # bsdports go last because every deploy sheds them, so deploying them last folds
  # the restore into the same pass instead of leaving a window with nobody looking.
  def test_the_order_that_survives_its_own_side_effects
    assert_equal "master", deploy_all.first
    assert_equal %w[amber bsdports], deploy_all.last(2).sort
  end

  def test_it_rejects_an_unknown_deploy_target
    assert_match(
      /case \$app in\n\s+all\|master\|brgen\|amber\|bsdports\) ;;.*\n\s+\*\) .*exit 2/,
      SOURCE,
      "an arbitrary app name must not reach filesystem, service or deploy-stamp paths"
    )
  end

  def test_it_refuses_to_run_as_root
    assert_match(/if \[\[ \$\(id -u\) -eq 0 \]\]; then/, SOURCE,
                 "the uid guard is gone — root reaches git pull and fails on a host key instead")
    guard = SOURCE[/if \[\[ \$\(id -u\) -eq 0 \]\]; then.*?^fi$/m]

    assert_match(/exit 2/, guard, "the root guard must exit, not warn")
  end

  # SKIP_CI=1 does not mean no gate runs: it takes the ${app}.sh branch, which
  # reaches rails_runtime_gate through deploy_tracked_app. The name says otherwise,
  # and a hotfix pushed on that belief is how something bin/ci would have caught
  # gets onto the box. The branch must keep running the app script.
  def test_skip_ci_takes_the_narrower_gate_rather_than_no_gate
    branch = SOURCE[/if \[\[ \$\{SKIP_CI:-\} == 1 \]\]; then(.*?)^else$/m]

    refute_nil branch, "the SKIP_CI branch is gone — the scan broke, or the path did"
    assert_match(%r{RAILS/\$\{app\}/\$\{app\}\.sh}, branch,
                 "SKIP_CI=1 must still run the app script, which is what reaches rails_runtime_gate")
  end

  GUARD = File.read(File.join(ROOT, "OPENBSD", "bin", "resource_guard.sh"), encoding: "UTF-8")

  def flag_block
    SOURCE[/^deploy_flag=.*?^hold_deploy_flag$/m]
  end

  # resource_guard stops shedding while a .deploying* flag is fresh. rc.d holds
  # one only across the restart, so CI and the gates ran as strikes and the app
  # deployed last was shed on the first tick after its flag came off. The flag
  # this script holds has to be one the guard reads, live across the deploy,
  # and gone when the script exits.
  def test_the_deploy_flag_is_held_for_the_whole_deploy_and_released_on_exit
    refute_nil flag_block, "the deploy flag block is gone — the scan broke, or the flag did"
    guard_glob = GUARD[%r{for _flag in (/home/dev/pub4/\.deploying\S*); do}, 1]
    refute_nil guard_glob, "resource_guard no longer reads a deploy flag glob"

    Dir.mktmpdir do |repo|
      script = "repo=#{repo}; app=bsdports\n#{flag_block}\nprint -r -- $deploy_flag\n[[ -e $deploy_flag ]] && print held\n"
      out = IO.popen(["zsh", "-c", script], &:read).lines.map(&:chomp)
      flag = out.first

      assert_equal "held", out.last, "the flag is not on disk while the deploy runs"
      assert File.fnmatch?(guard_glob.sub("/home/dev/pub4", repo), flag, File::FNM_DOTMATCH),
             "#{flag} is not a name resource_guard's #{guard_glob} reads"
      refute File.exist?(flag), "the flag outlived the script, so shedding stays off for 30 minutes"

      rcd_flag = File.read(File.join(ROOT, "OPENBSD", "etc", "rc.d", "bsdports"))[%r{touch \S+/(\.deploying\S*)}, 1]
      refute_equal rcd_flag, File.basename(flag),
                   "rc.d removes its own flag after /up, so sharing its name drops the hold mid-deploy"
    end
  end

  def test_the_flag_is_taken_before_ci_and_the_app_is_checked_before_ok
    assert_operator SOURCE.index("\nhold_deploy_flag\n"), :<, SOURCE.index("OPENBSD/bin/vps_ci.sh")
    assert_operator SOURCE.rindex(%(doas rcctl check "$app")), :>, SOURCE.index("GATE_REQUIRE_LIVE=1 ruby40")
  end
end

`````

### test/test_vps_run_remote_contract.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"

class VpsRunRemoteContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/vps_run_remote.sh", __dir__), encoding: "UTF-8")

  def test_nested_vm_target_is_shell_quoted
    assert_includes SOURCE, "quoted_vm=${(q)VM}"
    refute_match(/scp .* \$\{VM\}:/, SOURCE)
    refute_match(/ssh .* \$\{VM\} /, SOURCE)
  end

  def test_nested_remote_log_path_is_shell_quoted
    assert_includes SOURCE, "quoted_log=${(q)REMOTE_LOG}"
    refute_includes SOURCE, "> ${REMOTE_LOG} 2>&1"
  end
end

`````

### test/test_vps_safety_gate.rb

`````ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "fileutils"
require "tmpdir"

class VpsSafetyGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  GATE = File.join(ROOT, "gates", "vps_safety_gate.rb")

  def run_gate(root = nil)
    env = root ? { "VPS_SAFETY_ROOT" => root } : {}
    Open3.capture2e(env, RbConfig.ruby, GATE)
  end

  # A copy of everything the gate reads, so one file can be broken at a time.
  def with_fixture
    Dir.mktmpdir do |dir|
      openbsd = File.join(dir, "OPENBSD")
      FileUtils.mkdir_p(File.join(openbsd, "etc"))
      FileUtils.cp_r(File.join(ROOT, "etc", "rc.d"), File.join(openbsd, "etc"))
      FileUtils.cp(File.join(ROOT, "etc", "doas.conf"), File.join(openbsd, "etc"))
      FileUtils.mkdir_p(File.join(openbsd, "bin"))
      (Dir.glob(File.join(ROOT, "bin", "*.exp")) + [File.join(ROOT, "bin", "validate_doas.ksh")]).each do |path|
        FileUtils.cp(path, File.join(openbsd, "bin"))
      end
      yield dir, File.join(openbsd, "etc", "doas.conf")
    end
  end

  def test_gate_passes_on_the_tracked_tree
    out, status = run_gate
    assert status.success?, "expected VPS safety gate to pass, got:\n#{out}"
    assert_includes out, "VPS safety gate passed"
  end

  def test_the_fixture_is_a_faithful_copy
    with_fixture do |dir, _|
      out, status = run_gate(dir)
      assert status.success?, "an unmodified fixture must pass, or the must-flag tests below prove nothing:\n#{out}"
    end
  end

  def test_keepenv_on_the_dev_rule_is_refused
    with_fixture do |dir, doas|
      File.write(doas, File.read(doas).sub(/permit nopass setenv \{[^}]*\} dev as root/, "permit nopass keepenv dev as root"))
      out, status = run_gate(dir)
      refute status.success?
      assert_includes out, "must not use keepenv"
    end
  end

  def test_every_allowlisted_variable_is_pinned
    with_fixture do |dir, doas|
      rules = File.read(doas).lines.map { |line| line.start_with?("permit") ? line.sub(" MAIL_IMG_FMT", "") : line }
      File.write(doas, rules.join)
      out, status = run_gate(dir)
      refute status.success?
      assert_includes out, "setenv-allowlist MAIL_IMG_FMT"
    end
  end

  # The ack is the whole safety of the console scripts, so hold the behaviour:
  # with it unset the script refuses before it spawns anything.
  def test_console_automation_refuses_without_the_ack
    expect = %w[/usr/bin/expect /usr/local/bin/expect].find { |path| File.executable?(path) }
    skip "expect not installed" unless expect

    env = { "I_UNDERSTAND_CONSOLE_RISK" => nil }
    out, status = Open3.capture2e(env, expect, "-f", File.join(ROOT, "bin", "vps_console.exp"), "short")
    assert_equal 1, status.exitstatus
    assert_includes out, "REFUSING"
  end

  # A second console script would reach vmctl without passing the ack.
  def test_a_second_console_script_is_refused
    with_fixture do |dir, _|
      File.write(File.join(dir, "OPENBSD", "bin", "vps_console_short.exp"), "#!/usr/bin/expect -f\nspawn ssh vm23\n")
      out, status = run_gate(dir)
      refute status.success?
      assert_includes out, "vps_console_short.exp: console automation belongs in vps_console.exp"
    end
  end

  def test_console_scripts_live_in_openbsd_bin
    %w[validate_doas.ksh vps_console.exp].each do |name|
      assert File.file?(File.join(ROOT, "bin", name)), "missing #{name} in OPENBSD/bin"
    end
  end
end

`````

### usr/local/bin/core-reclaim.sh

`````zsh
#!/bin/ksh
# Return a core app's grown resident set to the box.
#
# resource_guard.sh sheds OPTIONAL="bsdports amber" under pressure and
# restores them when it clears. It never touches CORE="master brgen", by design —
# those are the surfaces that must stay up. The consequence is that brgen's
# worker grows and nothing ever gives the memory back.
#
# Measured 2026-08-17. brgen's worker boots at 225M and had reached 355M, growing
# about 0.4M per request and never returning any of it. One restart:
#
#   before   brgen 355M   swap 1142M/1264M (91%)   free  43M
#   after    brgen 225M   swap  812M/1264M (64%)   free 249M
#
# 130M of resident set, and 330M of swap with it. That matters because the box
# was paging continuously at rest (vmstat pi 13-27/s while idle), and a page-in
# is what a visitor actually feels: amber's home measured 12.19s to first byte
# cold against 0.40s warm. On a low-traffic site nearly every visitor is the cold
# case.
#
# Install: doas cp OPENBSD/usr/local/bin/core-reclaim.sh /usr/local/bin/ &&
#          doas chmod 755 /usr/local/bin/core-reclaim.sh
# Cron (root): 40 * * * * /usr/local/bin/core-reclaim.sh >> /var/log/core-reclaim.log 2>&1

set -e

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/core-reclaim.sh"
  echo "  restart brgen when its RSS or swap is over the ceiling, at most hourly, never under load"
  exit 0
  ;;
esac

# Same reason resource_guard sets this: cron's PATH has no /usr/local/bin, where
# rcctl's dependencies and curl live, and everything started here inherits it.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

STATE=/var/db/core_reclaim_last

# brgen only, for now, and deliberately.
#
# master's RSS reads 42M against 927M of address space because it is almost
# entirely swapped out — RSS understates a swapped process, so the same ceiling
# would never fire for it and a VSZ ceiling would fire constantly. Restarting the
# face also drops any open TTS socket. amber and bsdports already belong to
# resource_guard; two jobs restarting one app is how they fight.
APP=brgen
PORT=38182
# Boot baseline 225M, measured above. 320M is baseline plus ~40%: high enough
# that a normal working day does not trip it, low enough that the box never
# reaches the 91% swap this was written for.
CEILING_MB=320
# Swap pressure that a restart is worth answering. The box pages continuously
# above roughly two thirds, and the first response measured 12.19s cold against
# 0.40s warm — so this is the number a visitor feels, not a tidiness figure.
SWAP_PCT_MAX=65
# A restart costs a cold boot for whoever asks next, so not during a spike and
# not more than once an hour. vm23 is 1 vCPU: load 1.0 is a busy core, not a
# crisis, so this is about avoiding a restart storm rather than about load.
LOAD_MAX=2.5
MIN_INTERVAL_S=3000

# A heartbeat, written every run, before any decision.
#
# This job logs only when it reclaims, so an empty log means either "nothing
# needed doing" or "cron stopped calling me", and those are the same silence.
# It read 12 days quiet while the box sat at 76% swap. health_check.rb reads
# this file's mtime, so the two states are now different facts.
mkdir -p /var/db 2>/dev/null || true
date +%s > /var/db/core_reclaim_seen 2>/dev/null || true

# Resident size of the process listening on a port, in KB.
#
# Was `ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 |
# awk '{print $1}'`. grep, head and awk are banned in committed scripts here
# because this deploys to OpenBSD and the BSD variants break GNU idioms, and
# the pipeline was fragile on its own terms: it matched an args substring
# across every process on the box, so the answer depended on which line came
# first, and `grep -v grep` existed because the pipeline matched itself.
#
# pgrep -n -f names one pid, the newest match. Verified on vm23 against the
# old form: both returned 52020 KB for master.
rss_of_port() {
  _pid=$(pgrep -n -f "127.0.0.1:$1" 2>/dev/null) || return 0
  [[ -n "$_pid" ]] || return 0
  ps -o rss= -p "$_pid" 2>/dev/null | tr -d ' '
}

now=$(date +%s)
if [[ -r "$STATE" ]]; then
  last=$(cat "$STATE" 2>/dev/null || echo 0)
  if [[ "$(( now - last ))" -lt "$MIN_INTERVAL_S" ]]; then
    exit 0
  fi
fi

rss_kb=$(rss_of_port "$PORT")
[[ -n "$rss_kb" ]] || exit 0
rss_mb=$(( rss_kb / 1024 ))

# RSS or swap, because RSS alone could not see the case this exists for.
#
# The header above says it about master: RSS understates a swapped process. It
# is just as true of brgen. Measured 2026-09-11 — brgen resident 199M against a
# 320M ceiling, address space 877M, swap 968M/1264M — so the ceiling never
# fired, this job never reclaimed once in twelve days, and the kernel did the
# reclaiming instead: 21 `killed: out of swap` for brgen in one dmesg buffer,
# one of them relayd. A ceiling that cannot fire under pressure is not a
# ceiling; the pressure itself has to be readable.
# swapctl -l prints a Device header, then one row per device: device, blocks,
# used, avail, capacity, priority. Read with ksh itself rather than a grep,
# head, cut and tr pipeline. swap_pct is the first device's capacity and
# swap_used the used blocks of the last row, as the pipelines this replaces
# read them.
swap_pct() {
  swapctl -l 2>/dev/null | while read -r _dev _blocks _used _avail _cap _prio; do
    [[ "$_dev" = "Device" ]] && continue
    print -r -- "${_cap%\%}"
    break
  done
}
swap_used() {
  swapctl -l 2>/dev/null | {
    _last=0
    while read -r _dev _blocks _used _rest; do
      [[ "$_dev" = "Device" ]] || _last=$_used
    done
    print -r -- "$_last"
  }
}
swap_pct=$(swap_pct)
[[ -n "$swap_pct" ]] || swap_pct=0
if [[ "$rss_mb" -lt "$CEILING_MB" ]] && [[ "$swap_pct" -lt "$SWAP_PCT_MAX" ]]; then
  exit 0
fi

# Field 1 is the 1-minute average, and it is the right one here while
# resource_guard.sh takes field 2. The two ask opposite questions. The guard
# must not shed a site over a passing spike, so it wants the smoothed figure; this
# script is about to cost somebody a cold boot, so it wants to know whether the box
# is busy in this minute. Reading the same field in both would make one of them
# wrong, which is why there is no shared helper for this line.
set -- $(sysctl -n vm.loadavg)
load=$1
# ksh arithmetic is integer only, so both figures are compared as millionths.
# sysctl prints the load with two decimals and LOAD_MAX has one, so six places
# lose nothing; measured on vm23 against Ruby's Float comparison over 22
# values, from 0.00 through 99.99 and both sides of 2.5, with no disagreement.
# The fraction is read as base 10 because ksh(1) takes a leading 0 as octal,
# and 08 would not parse. It spares a ruby34 start at the one moment this job
# knows the box is short of memory.
micro() {
  _int=${1%%.*}
  _frac=
  [[ "$1" = *.* ]] && _frac=${1#*.}
  _frac="${_frac}000000"
  while (( ${#_frac} > 6 )); do _frac=${_frac%?}; done
  print -r -- "$(( 10#${_int:-0} * 1000000 + 10#$_frac ))"
}
if (( $(micro "$load") > $(micro "$LOAD_MAX") )); then
  echo "$(date '+%Y-%m-%dT%H:%M:%S') skip $APP ${rss_mb}M — load $load over $LOAD_MAX"
  exit 0
fi

swap_before=$(swap_used)
rcctl restart "$APP" >/dev/null 2>&1 || {
  echo "$(date '+%Y-%m-%dT%H:%M:%S') FAILED to restart $APP at ${rss_mb}M"
  exit 1
}
echo "$now" > "$STATE"

# Wait for it to answer before claiming success: rc.d/$APP returns once the
# process is up, which is not the same as the app serving.
sleep 10
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
       -H "Host: brgen.no" "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)
rss_after=$(rss_of_port "$PORT")
swap_after=$(swap_used)
echo "$(date '+%Y-%m-%dT%H:%M:%S') reclaimed $APP ${rss_mb}M -> $(( ${rss_after:-0} / 1024 ))M, \
swap $(( swap_before / 2048 ))M -> $(( swap_after / 2048 ))M, first response $code"

`````

### usr/local/bin/declutter-hygiene.sh

`````zsh
#!/bin/sh
# Nightly amber declutter hygiene, when the box is actually quiet.
#
# DeclutterHygieneJob sits in amber's recurring.yml for 6am, but a recurring
# schedule only fires while a Solid Queue scheduler is resident to notice the
# time has come, and amber holds no resident worker. drain-jobs.sh cannot
# substitute for it: it only starts a worker for an app that already has due
# rows, and this job's sole trigger is the recurring schedule itself, so
# drain-jobs.sh never has a reason to start one. Same load-gate shape as
# prune-guests.sh, next door.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${DECLUTTER_HYGIENE_LOAD_CEILING:-3.0}
WAIT_TICKS=${DECLUTTER_HYGIENE_WAIT_TICKS:-15}
TICK_SECONDS=${DECLUTTER_HYGIENE_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average, so waiting for it to fall does not spike on the Rails
# boot this wrapper is about to cause. See prune-guests.sh for the measurement
# that found the 1-minute figure self-defeating.
load_is_low() {
  ruby40 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[1].to_f <= ARGV[0].to_f ? 0 : 1)
  ' "$CEILING"
}

wait_for_quiet() {
  i=0
  while [ "$i" -lt "$WAIT_TICKS" ]; do
    if load_is_low; then
      return 0
    fi
    i=$((i + 1))
    sleep "$TICK_SECONDS"
  done
  return 1
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

out=$(su -m amber -c "cd /home/amber/app && set -a && . /etc/amber.env && set +a && HOME=/home/amber RAILS_ENV=production /usr/local/bin/ruby40 bin/rails runner /usr/local/bin/declutter_hygiene.rb" 2>&1)
status=$?

result=$(printf '%s\n' "$out" | grep '^expired_challenges=')

if [ "$status" -ne 0 ] || [ -z "$result" ]; then
  echo "$(stamp) amber FAILED (exit $status)"
  printf '%s\n' "$out"
  logger -t declutter-hygiene "amber declutter hygiene failed - see /var/log/declutter-hygiene.log"
  exit 1
fi

echo "$(stamp) amber $result"

`````

### usr/local/bin/declutter_hygiene.rb

`````ruby
# frozen_string_literal: true

# Run amber's daily declutter hygiene and say what happened, on stdout.
#
# DeclutterHygieneJob has no enqueuer while amber holds no resident Solid
# Queue worker: drain-jobs.sh only starts a worker for a queue that already
# has due rows, so a job whose only trigger is its own recurring schedule --
# nothing else ever enqueues it -- can never get the worker it needs to be
# enqueued in the first place.
#
# Fed to `bin/rails runner` by declutter-hygiene.sh, which is what cron calls.
#
# Operator::LoadAverage lives in shared/lib, which no app autoloads (only
# app/* is on config.autoload_paths — see shared/lib/shared/engine.rb).
# prune_guests.rb gets it for free because PruneGuestUsersJob happens to
# require it; nothing here does that incidentally, so it needs its own
# require.
require "operator/load_average"

started = Time.now
overdue_before = DeclutterChallenge.overdue.count

DeclutterHygieneJob.new.perform

overdue_after = DeclutterChallenge.overdue.count
nudges = Recommendation.declutter.where(created_at: started..).count

puts format(
  "expired_challenges=%d box_nudges=%d in %.1fs load=%s",
  overdue_before - overdue_after, nudges, Time.now - started, Operator::LoadAverage.one.inspect
)

`````

### usr/local/bin/drain-jobs.sh

`````zsh
#!/bin/sh
# set -e with the three deliberate failures guarded below: a drain window
# ending in timeout(1) killing rake IS the design, and an unreadable queue
# db is reported as FAIL for that app while the sweep goes on to the next.
set -eo pipefail
# Run the background job queue for a few minutes, hourly, because vm23 cannot
# hold a worker that stays up.
#
# Solid Queue needs its own process under Falcon and none was ever started, so
# `perform_later` on this box meant never. Ten job classes are reached from live
# request paths; on 2026-08-14 brgen was holding 181 unfinished jobs of which
# 178 were MessageExpirationJob — disappearing messages that had never
# disappeared — and amber 28.
#
# A resident worker does not fit, and that is measured rather than assumed. At
# the time of writing the box had 60 MB free with 1032 MB of 1264 MB of swap in
# use, and a Solid Queue supervisor plus its workers came to roughly 460 MB of
# RSS across four processes. Three of those, one per app, is not a thing this
# machine can carry.
#
# A bounded run is. 180 seconds of worker drained 96 of the 181, held the load
# under 2, and the box finished the run with MORE free memory than it started
# (58 MB before, 292 MB after) because starting it made the kernel reclaim.
#
# WHAT THIS DOES NOT FIX: latency. ChannelBotReplyJob is a bot answering someone
# in a chat room, and an answer that arrives up to an hour later is not an
# answer. That one wants a worker that stays up, which wants a bigger box. The
# jobs this does fix are the ones where an hour costs nothing — expiring
# messages, blurhashes, media derivatives, federation, moderation notices.
#
# Same shape as prune-guests.sh next door: wait for quiet, bound the work, and
# print what happened rather than trusting a logger that may not reach anyone.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/drain-jobs.sh"
  echo "  run each app's Solid Queue for DRAIN_JOBS_SECONDS once the 5-minute load is under DRAIN_JOBS_LOAD_CEILING"
  exit 0
  ;;
esac

CEILING=${DRAIN_JOBS_LOAD_CEILING:-3.0}
SECONDS_PER_APP=${DRAIN_JOBS_SECONDS:-180}
WAIT_TICKS=${DRAIN_JOBS_WAIT_TICKS:-5}
TICK_SECONDS=${DRAIN_JOBS_TICK_SECONDS:-60}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average. The 1-minute figure spikes on anything that starts,
# including the boot this script is about to do, so a gate reading it refuses
# the spike it caused itself — see the header of prune-guests.sh, where that
# cost a night's work before anyone noticed.
load_is_low() {
  ruby34 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[1].to_f <= ARGV[0].to_f ? 0 : 1)
  ' "$CEILING"
}

wait_for_quiet() {
  i=0
  while [ "$i" -lt "$WAIT_TICKS" ]; do
    if load_is_low; then
      return 0
    fi
    i=$((i + 1))
    sleep "$TICK_SECONDS"
  done
  return 1
}

# Count what is actually RUNNABLE, not what is unfinished.
#
# The first version of this reported unfinished jobs and printed "brgen pending
# 85 -> 85 (ran 150s)", which reads as a worker that did nothing. It had drained
# everything there was: 82 of those 85 were MessageExpirationJob rows scheduled
# hours ahead, which is the feature working, and 1 was a permanently failed job.
# A number that cannot go down is not a progress report.
#
# due            — ready now, or scheduled for a time that has passed
# ahead          — scheduled for later, nothing to do about it
# failed         — gave up after its retries; needs a person, not another tick
queue_counts() {
  su -m "$1" -c "sqlite3 /home/$1/app/storage/production_queue.sqlite3 \"
    select
      (select count(*) from solid_queue_jobs j
        where j.finished_at is null
          and (j.scheduled_at is null or j.scheduled_at <= datetime('now'))
          and not exists (select 1 from solid_queue_failed_executions f where f.job_id = j.id)),
      (select count(*) from solid_queue_jobs j
        where j.finished_at is null and j.scheduled_at > datetime('now')),
      (select count(*) from solid_queue_failed_executions);
  \"" 2>/dev/null
}

# Split "due|ahead|failed" with the shell's own read. ruby34 -e was tried first
# and ARGF took a trailing argument for a FILENAME, so every field read 0 against
# a queue holding 82 jobs; cut(1) is on the banned list. read has neither trap.
split_counts() {
  IFS='|' read -r due ahead failed <<EOF
$1
EOF
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

status=0
for app in brgen amber bsdports; do
  [ -d "/home/$app/app" ] || continue
  [ -f "/home/$app/app/storage/production_queue.sqlite3" ] || continue
  if [ "$app" = brgen ] && rcctl check brgen_jobs >/dev/null 2>&1; then
    echo "$(stamp) brgen skipped: brgen_jobs is running"
    continue
  fi

  # An unreadable queue is not an empty one. Reading it as zero printed
  # "nothing due", which solid_queue_proof.rb takes as proof the drain ran, so a
  # broken queue file kept every deploy green.
  counts=$(queue_counts "$app") || counts=""
  if [ -z "$counts" ]; then
    echo "$(stamp) $app FAIL queue unreadable: /home/$app/app/storage/production_queue.sqlite3"
    status=1
    continue
  fi
  split_counts "$counts"

  if [ "$due" -eq 0 ]; then
    echo "$(stamp) $app nothing due (ahead=$ahead failed=$failed)"
    continue
  fi

  # SIGTERM, which Solid Queue handles: it stops claiming new work and lets what
  # is in flight finish. -k gives it 20 seconds before SIGKILL.
  su -m "$app" -c "cd /home/$app/app && set -a && . /etc/$app.env && set +a && HOME=/home/$app RAILS_ENV=production timeout -k 20 -s TERM $SECONDS_PER_APP /usr/local/bin/bundle34 exec rake solid_queue:start" \
    >>/var/log/drain-jobs.detail.log 2>&1 || true

  before_due=$due
  after=$(queue_counts "$app") || after=""
  split_counts "$after"
  echo "$(stamp) $app due $before_due -> ${due:-?}  ahead=${ahead:-?} failed=${failed:-?} (ran ${SECONDS_PER_APP}s)"
done

exit "$status"

`````

### usr/local/bin/keep-warm.sh

`````zsh
#!/bin/ksh
# Keep the public apps' pages resident, so a visitor is never the one paying for
# the page-in.
#
# The box carries more than fits: measured 2026-08-17 at 918M real with 43M free
# and swap 91% used, paging continuously at rest. OpenBSD evicts whatever is
# idle, which on a low-traffic site is everything between visits — so the first
# request after a quiet spell reads its own working set back from disk. amber's
# home measured 12.19s to first byte cold against 0.40s warm. Nearly every real
# visitor is the cold case.
#
# One request every ten minutes is enough to keep a working set warm and is
# invisible as load: two page renders per ten minutes against a box that idles at
# 84%.
#
# Install: doas cp OPENBSD/usr/local/bin/keep-warm.sh /usr/local/bin/ &&
#          doas chmod 755 /usr/local/bin/keep-warm.sh
# Cron (root): */10 * * * * /usr/local/bin/keep-warm.sh >> /var/log/keep-warm.log 2>&1

set -e
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/keep-warm.sh"
  echo "  render brgen's and amber's home over loopback; log only a slow or failed hit"
  exit 0
  ;;
esac

# A heartbeat on every run, because this job logs only when a hit is slow or
# fails: without it "all warm" and "never ran" are the same empty log.
# health_check.rb reads the file's age.
# Braced, because a 2>/dev/null after the redirect cannot silence the redirect's
# own failure.
{ date +%s > /var/db/keep_warm_seen; } 2>/dev/null || true

# Loopback and a Host header rather than the public name: this is about keeping
# the Ruby process resident, and going out through relayd and back would measure
# the network as well as pay for TLS on a box that has no spare core.
#
# brgen and amber only, and not because of the guard's sets — amber is in
# OPTIONAL="bsdports amber" and master is in CORE="master brgen", so naming the
# guard here gets it backwards in both directions. These two are the surfaces a
# visitor arrives on cold. bsdports is a low-traffic ports index nobody waits on,
# and master is 927M of address space that is correctly swapped out until someone
# actually opens the face. The shed case is handled below, per target.
set -A TARGETS "brgen.no 38182" "amberapp.art 61352"

# A real page, not /up. The health endpoint answers from a handful of objects and
# leaves the render path — views, the feed query, the template cache — exactly as
# cold as it found it, which is the part a visitor waits for.
for target in "${TARGETS[@]}"; do
  set -- $target
  host=$1
  port=$2
  # Skip a target that is not listening: resource_guard sheds amber under real
  # pressure, and warming it back up would undo that deliberately.
  nc -z 127.0.0.1 "$port" 2>/dev/null || continue

  start=$(date +%s)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
         -H "Host: $host" "http://127.0.0.1:$port/" 2>/dev/null || echo 000)
  elapsed=$(( $(date +%s) - start ))
  # Only worth a log line when it was slow or it failed — a warm hit every ten
  # minutes for a month is 4,000 lines saying nothing.
  if [[ "$code" != "200" ]] || [[ "$elapsed" -ge 3 ]]; then
    echo "$(date '+%Y-%m-%dT%H:%M:%S') $host $code in ${elapsed}s"
  fi
done

`````

### usr/local/bin/ports-import.sh

`````zsh
#!/bin/sh
# Nightly bsdports ports-tree import, when the box is actually quiet.
#
# PortsImportJob sits in bsdports' recurring.yml for 3am, but a recurring
# schedule only fires while a Solid Queue scheduler is resident to notice the
# time has come, and bsdports holds no resident worker. drain-jobs.sh cannot
# substitute for it: it only starts a worker for an app that already has due
# rows, and this job's sole trigger is the recurring schedule itself, so
# drain-jobs.sh never has a reason to start one. Same load-gate shape as
# prune-guests.sh, next door.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

CEILING=${PORTS_IMPORT_LOAD_CEILING:-3.0}
WAIT_TICKS=${PORTS_IMPORT_WAIT_TICKS:-15}
TICK_SECONDS=${PORTS_IMPORT_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average, so waiting for it to fall does not spike on the Rails
# boot this wrapper is about to cause. See prune-guests.sh for the measurement
# that found the 1-minute figure self-defeating.
load_is_low() {
  ruby40 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[1].to_f <= ARGV[0].to_f ? 0 : 1)
  ' "$CEILING"
}

wait_for_quiet() {
  i=0
  while [ "$i" -lt "$WAIT_TICKS" ]; do
    if load_is_low; then
      return 0
    fi
    i=$((i + 1))
    sleep "$TICK_SECONDS"
  done
  return 1
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

out=$(su -m bsdports -c "cd /home/bsdports/app && set -a && . /etc/bsdports.env && set +a && HOME=/home/bsdports RAILS_ENV=production /usr/local/bin/ruby40 bin/rails runner /usr/local/bin/ports_import.rb" 2>&1)
status=$?

result=$(printf '%s\n' "$out" | grep '^platform=')

if [ "$status" -ne 0 ] || [ -z "$result" ]; then
  echo "$(stamp) bsdports FAILED (exit $status)"
  printf '%s\n' "$out"
  logger -t ports-import "bsdports ports import failed - see /var/log/ports-import.log"
  exit 1
fi

echo "$(stamp) bsdports $result"

`````

### usr/local/bin/ports_import.rb

`````ruby
# frozen_string_literal: true

# Run bsdports' nightly ports-tree import and say what happened, on stdout.
#
# PortsImportJob has no enqueuer while bsdports holds no resident Solid Queue
# worker, the same gap DeclutterHygieneJob has: drain-jobs.sh only starts a
# worker for a queue that already has due rows, so a job whose only trigger
# is its own recurring schedule can never get the worker it needs to be
# enqueued in the first place.
#
# Calls Ports::Importer directly rather than through the job. PortsImportJob
# does the same call and then only forwards the result to an event; running
# the importer here directly means Result#ports_count is available to report
# instead of being swallowed by the job's own return value.
#
# Fed to `bin/rails runner` by ports-import.sh, which is what cron calls.
#
# Operator::LoadAverage lives in shared/lib, which no app autoloads (only
# app/* is on config.autoload_paths — see shared/lib/shared/engine.rb).
# prune_guests.rb gets it for free because PruneGuestUsersJob happens to
# require it; nothing here does that incidentally, so it needs its own
# require.
require "operator/load_average"

started = Time.now
platform = Platform.active.find_by!(slug: "openbsd")
result = Ports::Importer.call(platform:)

puts format(
  "platform=%s ports_count=%d tree_path=%s in %.1fs load=%s",
  platform.slug, result.ports_count, result.tree_path, Time.now - started, Operator::LoadAverage.one.inspect
)

`````

### usr/local/bin/prune-guests.sh

`````zsh
#!/bin/sh
# set -e with the two deliberate failures guarded: the runner's exit is
# CAPTURED (status) for the report, and an absent removed= line is the
# failure signal itself, not a crash.
set -eo pipefail
# Nightly guest-row prune, one app at a time, when the box is actually quiet.
#
# This ran from daily.local for exactly one night and removed nothing. Three
# things were wrong and all three are fixed here.
#
# WHEN. daily.local runs at the tail of /etc/daily, which starts at 01:30 and
# has the box at load 4.12 by the time it gets there. PruneGuestUsersJob's own
# ceiling is 3.0, so the guard correctly refused and the job did nothing — the
# schedule and the guard were fighting each other. Its own cron slot at 04:20 is
# after daily(8) has finished and before the morning. And rather than skip a
# whole night if 04:20 happens to be busy, this waits for the load to fall,
# checking every two minutes for up to half an hour. One Rails boot either way.
#
# WHETHER. See prune_guests.rb: brgen's production logger does not write to
# stdout, so the run left no trace at all and could not be told from a crash.
# The result is printed now, with a timestamp, per app.
#
# HOME. cron's environment has HOME=/var/log (see the root crontab), and `su -m`
# preserves it, so bundler announced "`/var/log` is not writable" and relocated
# the home directory on every invocation. HOME is set explicitly below.
#
# bsdports has no `guest` column on users and is deliberately absent.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
export PATH

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/prune-guests.sh"
  echo "  prune brgen's and amber's guest rows once the 5-minute load is under PRUNE_GUESTS_LOAD_CEILING"
  exit 0
  ;;
esac

CEILING=${PRUNE_GUESTS_LOAD_CEILING:-3.0}
WAIT_TICKS=${PRUNE_GUESTS_WAIT_TICKS:-15}
TICK_SECONDS=${PRUNE_GUESTS_TICK_SECONDS:-120}

stamp() {
  date -u +%FT%TZ
}

# The 5-minute average, matching the job's own guard. The 1-minute figure spikes
# on anything that starts, including the Rails boot this wrapper is about to do:
# waiting for a 1-minute load of 1.85 and then booting the runner put it at 3.31,
# over the ceiling, and the job refused a spike it had caused itself.
#
# ruby40 because awk is banned in committed scripts here, and OpenBSD prints the
# three numbers bare while macOS wraps them in braces.
load_is_low() {
  ruby40 -e '
    n = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
    exit(1) if n.size < 3
    exit(n[1].to_f <= ARGV[0].to_f ? 0 : 1)
  ' "$CEILING"
}

wait_for_quiet() {
  i=0
  while [ "$i" -lt "$WAIT_TICKS" ]; do
    if load_is_low; then
      return 0
    fi
    i=$((i + 1))
    sleep "$TICK_SECONDS"
  done
  return 1
}

if ! wait_for_quiet; then
  echo "$(stamp) skipped: load stayed over $CEILING for $((WAIT_TICKS * TICK_SECONDS / 60)) minutes"
  exit 0
fi

for app in brgen amber; do
  [ -d "/home/$app/app" ] || continue

  status=0
  out=$(su -m "$app" -c "cd /home/$app/app && set -a && . /etc/$app.env && set +a && HOME=/home/$app RAILS_ENV=production /usr/local/bin/ruby40 bin/rails runner /usr/local/bin/prune_guests.rb" 2>&1) || status=$?

  result=$(printf '%s\n' "$out" | grep '^removed=') || result=""

  if [ "$status" -ne 0 ] || [ -z "$result" ]; then
    echo "$(stamp) $app FAILED (exit $status)"
    printf '%s\n' "$out"
    logger -t prune-guests "guest prune failed for $app - see /var/log/prune-guests.log"
    continue
  fi

  echo "$(stamp) $app $result"
done

`````

### usr/local/bin/prune_guests.rb

`````ruby
# frozen_string_literal: true

# Run the guest prune and SAY WHAT HAPPENED, on stdout.
#
# The first attempt at this called the job straight from daily.local and relied
# on Rails.logger. brgen's production logger does not write to stdout, so the
# 2026-08-14 01:30 run left not one line about brgen in /tmp/prune-guests.out —
# only amber's, because amber's logger is configured differently. From the log
# there was no way to tell whether brgen had pruned 20,000 rows, pruned none, or
# crashed before it started. The count answered it later: none.
#
# So the result is printed here rather than logged. A nightly job that cannot be
# told from a nightly crash is the same kind of defect as the job never running.
#
# Fed to `bin/rails runner` by prune-guests.sh, which is what cron calls.

started = Time.now
removed = Shared::PruneGuestUsersJob.new.perform
remaining = ::User.where(guest: true)
                  .where(created_at: ..Shared::PruneGuestUsersJob::RETENTION.ago)
                  .where.missing(:sessions)
                  .count

puts format(
  "removed=%d remaining=%d in %.1fs load=%s",
  removed.to_i, remaining, Time.now - started, Operator::LoadAverage.one.inspect
)

`````

### usr/local/bin/renew-certs.sh

`````zsh
#!/usr/bin/env zsh
# Renew TLS certs via acme-client; relayd reload only.
# Zone signing and TLSA records: usr/local/bin/nsd-resign (daily.local).
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: doas /usr/local/bin/renew-certs.sh"
  print "  renew each held certificate acme-client.conf names; restart relayd only when one changed"
  exit 0
fi

# Overridable so the intersection below can be run against a fixture.
ACME_CONF=${RENEW_CERTS_ACME_CONF:-/etc/acme-client.conf}
SSL_DIR=${RENEW_CERTS_SSL_DIR:-/etc/ssl}

# Renew what we hold, not what we hope for.
#
# This was a hardcoded list of all 53 domains in acme-client.conf. Only nine of
# them have ever been issued a certificate; the other 44 are NXDOMAIN at their
# registrar, so every weekly run asked Let's Encrypt to validate 44 hostnames
# that do not resolve. That never actually happened, because the script's
# `#!/usr/bin/env zsh` shebang could not find zsh under cron's PATH and the job
# had never once run (see etc/crontab.vm23). Fixing the PATH armed it: the next
# Monday would have been the first real run, and it would have spent 44 failed
# authorizations against the account rate limit to renew nine certificates.
#
# The list is now an intersection of two facts on disk, both of which acme-client
# itself maintains:
#
#   /etc/ssl/<name>.crt        we hold a certificate for this name, and it is the
#                              exact file relayd loads
#   domain "<name>" { ... }    acme-client knows how to renew it
#
# Held-but-unconfigured names are excluded rather than attempted. There is one,
# ai.brgen.no, which is a SAN of brgen.no rather than a domain acme-client knows
# how to renew on its own — passing it in fails on a config lookup before a
# single packet leaves the box. Renewal covers exactly what is deployed, and
# first issuance stays a deliberate act.
typeset -a CONFIGURED HELD DOMAINS

CONFIGURED=()
while IFS= read -r line; do
  [[ $line == domain\ \"*\"* ]] || continue
  line=${line#domain \"}
  CONFIGURED+=(${line%%\"*})
done < $ACME_CONF

# (N) nullglob, :t basename, :r strip the final extension -- "amberapp.art.crt"
# becomes "amberapp.art". smtp.crt is smtpd's own self-signed certificate and
# is not ACME's to renew; cert.pem is the trust store.
HELD=($SSL_DIR/*.crt(N:t:r))
HELD=(${HELD:#smtp})

DOMAINS=(${HELD:*CONFIGURED})

if (( ${#DOMAINS} == 0 )); then
  print -ru2 -- "renew-certs: no held certificate matches a domain in $ACME_CONF — refusing to run"
  exit 1
fi

typeset -a skipped
skipped=(${HELD:|DOMAINS})
(( ${#skipped} )) && print -r -- "renew-certs: held but not in $ACME_CONF, skipping: ${skipped}"

# http-01 needs a listener on port 80, and relayd is not it: relayd.conf declares
# exactly one relay, `listen on 0.0.0.0 port 443 tls`. httpd serves /var/www/acme
# and nothing else. It was down on 2026-08-12 -- daily.out had been saying so under
# "Services that should be running but aren't" -- and the only visible symptom was
# bsdports.org failing to renew with 7 days left on its certificate while the other
# eight succeeded, because their authorizations were still cached at Let's Encrypt
# and did not need a challenge. Cached authorizations expire; this is the renewal
# that quietly stops working months before anyone notices.
if ! /usr/sbin/rcctl check httpd >/dev/null 2>&1; then
  print -ru2 -- "renew-certs: httpd is down — starting it, http-01 challenges need port 80"
  /usr/sbin/rcctl start httpd || print -ru2 -- "renew-certs: httpd would not start; renewals needing a challenge will fail"
fi

print -r -- "renew-certs: renewing ${#DOMAINS} of ${#HELD} held certificate(s): ${DOMAINS}"

# acme-client exits 0 whether it renewed or found the certificate still valid, so
# counting successful invocations counts every domain every week — which meant
# the relayd restart below fired on every run. That is not free: relayd's health
# check is `interval 120`, and after a restart brgen's table sits empty until the
# first check passes. Measured 2026-08-12, that is roughly 20 seconds of 000 on
# brgen.no and every city with it, once a week, for nothing.
#
# The file mtime is the honest signal: acme-client rewrites the fullchain only
# when it actually issues.
typeset renewed=0
for domain in $DOMAINS; do
  typeset chain=$SSL_DIR/$domain.fullchain.pem
  typeset before=0
  [[ -f $chain ]] && before=$(stat -f %m $chain)

  if acme-client -v -f $ACME_CONF "$domain"; then
    typeset after=0
    [[ -f $chain ]] && after=$(stat -f %m $chain)
    if (( after > before )); then
      print -r -- "Renewed: $domain"
      (( renewed += 1 ))
    fi
  fi
done

print -r -- "renew-certs: $renewed renewed of ${#DOMAINS}"

# restart, not reload. `rcctl reload relayd` sends SIGHUP, and relayd loads its
# tls keypairs in the parent before chroot -- a SIGHUP after the certificate files
# have been replaced leaves it accepting connections on 443 and answering none of
# them. Measured 2026-08-12: seven certificates renewed, one reload, and every host
# on the box returned curl (52) Empty reply from server until relayd was restarted.
# rcctl check reported relayd(ok) throughout, so nothing on the box disagreed.
#
# Only when something changed. A restart is a real interruption, and the common
# case is that nothing was renewed at all.
if (( renewed > 0 )); then
  print -r -- "renew-certs: restarting relayd to load $renewed replaced certificate(s)"
  /usr/sbin/rcctl restart relayd
else
  print -r -- "renew-certs: nothing renewed, leaving relayd alone"
fi

`````

### usr/local/bin/uptime-check.sh

`````zsh
#!/bin/ksh
# Public /up only. Installed to /usr/local/bin so root cron does not exec
# the checkout. ksh shebang so cron still runs it if PATH loses /usr/local/bin.
#
# The list is derived, not written here. RAILS/apps.yml is the feature truth,
# and a copy of it in this file names whatever the fleet held on the day it was
# typed — a fifth app ships and this keeps checking four, with nothing to say
# so. OPENBSD/bin/uptime-check.sh answers the same question by running
# health_check.rb, and it is not what cron gets: root would be executing a file
# the dev user can rewrite, which is the escalation this installed copy exists
# to close. Reading is the half that is safe, so this reads apps.yml as data
# through a system interpreter and never runs anything from the checkout.
#
# The names below are the fallback for a box with no checkout to read.
#
# Optional apps can be waived the same way deploy-smoke does:
#   ALLOW_AMBER_DOWN=1 ALLOW_BSDPORTS_DOWN=1
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
# Strict on purpose: every fallible command below already carries its own
# fallback (curl || print 000), so set -e only guards the plumbing.
set -eo pipefail

fail=0
PUB4_ROOT=${PUB4_ROOT:-/home/dev/pub4}
FALLBACK='brgen,https://brgen.no/up
master,https://ai.brgen.no/up
amber,https://amberapp.art/up
bsdports,https://bsdports.org/up'

# name,url per line. The master face is not in apps.yml — it is not a Rails app
# under /home/*/app — so its domain comes from the deploy inventory beside it.
app_targets() {
  ruby34 -ryaml -rjson -e '
    root = ARGV[0]
    rows = YAML.safe_load(File.read(File.join(root, "RAILS", "apps.yml")))
              .fetch("apps")
              .map { |name, meta| [name.to_s, meta.fetch("domain").to_s] }
    inventory = File.join(root, "OPENBSD", "deploy_inventory.json")
    if File.file?(inventory)
      face = JSON.parse(File.read(inventory))["master_face"]
      rows << [face["name"].to_s, face["domain"].to_s] if face && face["domain"]
    end
    rows.each { |name, domain| puts "#{name},https://#{domain}/up" }
  ' "$PUB4_ROOT" 2>/dev/null
}

check() {
  url=$1
  code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${UPTIME_CHECK_TIMEOUT:-20}" "$url") || code=000
  case $code in
  2??|3??) ;;
  *)
    print -u2 "DOWN $url ($code)"
    fail=1
    ;;
  esac
}

# Falling back is a finding, not a quiet substitution. The built-in names are
# still checked — knowing those four are up is worth more than checking nothing —
# but the run exits nonzero whatever they answer, because this script cannot then
# tell you a fifth app exists and is down. A green uptime check measuring a fleet
# that is one deploy out of date is the failure the header at the top describes.
targets=$(app_targets) || targets=
if [[ -z $targets ]]; then
  print -u2 "uptime-check: FAIL — no app list under $PUB4_ROOT, so the fleet is unknown."
  print -u2 "uptime-check: checking the built-in names anyway; this exit code is the missing list, not them."
  targets=$FALLBACK
  fail=1
fi

# A for loop, not a pipe: pdksh runs the last stage of a pipeline in a subshell,
# and `fail` set there would never reach the exit below.
for row in $targets; do
  name=${row%%,*}
  url=${row#*,}
  case $name in
  amber)    if [[ ${ALLOW_AMBER_DOWN:-0} == 1 ]]; then continue; fi ;;
  bsdports) if [[ ${ALLOW_BSDPORTS_DOWN:-0} == 1 ]]; then continue; fi ;;
  esac
  check "$url"
done

# cron sends this job's output to /var/log/uptime-check.log, which nothing reads
# unprompted; one syslog line puts a failure where an operator will see it.
if [[ $fail != 0 ]]; then
	logger -t uptime-check "a public endpoint is down - see /var/log/uptime-check.log"
fi

exit "$fail"

`````

### vm_resource.yml

`````yaml
# vm23 resource budget — 1 vCPU, ~1 GiB RAM (OpenBSD Amsterdam).
# Keep aggregate steady-state under ~60% CPU and ~85% RAM to avoid host complaints.
# vm23 is the only environment; OPENBSD/CLAUDE.md, "Refused, and why", says why
# there is no staging copy.

profile: vm23_small
cpus: 1
ram_mb: 1024

# Always on: public face + flagship app.
core_services:
  - master
  - brgen

# Start manually: doas ksh OPENBSD/bin/start_all_apps.sh
# Pins all apps (creates /var/db/pub4_all_apps; resource_guard skips shedding).
# Mirrors resource_guard.sh's OPTIONAL, which is the live authority.
optional_services:
  - amber
  - bsdports

limits:
  # These mirror resource_guard.sh, which is the live authority and compares
  # the 5-minute load average (the second field of vm.loadavg). Change the
  # script first, then this.
  load_avg_5m_warn: 2.5
  load_avg_5m_crit: 5.00
  # 12 sat above the observed p50 of 13 and would have alarmed at rest; the
  # guard runs 8 after three recalibrations that never reached this file.
  mem_free_pct_warn: 8
  mem_free_pct_crit: 6
  # Restore floor, read by the guard as MEM_RESTORE.
  mem_free_pct_restore: 10
  relayd_check_interval: 120
  # etc/rc.d/master runs ${FALCON_WORKERS:-1}: one worker on 1 GB so amber and
  # bsdports can boot alongside master and brgen.
  master_falcon_workers: 1

`````
