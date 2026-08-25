#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh OPENBSD/vps_ci.sh brgen
set -euo pipefail

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: vps_ci.sh APP"; exit 2 }

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
  doas chown -R "${app}:${app}" "$mirror"
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
    local -a paths=(test app lib config bin db engines public vendor/javascript Gemfile Gemfile.lock config.ru Rakefile .rubocop.yml)
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
# App users traverse /home/dev by GROUP, not other: 710 dev:_pub4ci, members
# brgen/amber/bsdports (2026-08-22, closes the world-traversable half of the
# secrets debt entry). Idempotent so a fresh box converges on first CI run.
doas groupadd _pub4ci 2>/dev/null || true
doas usermod -G _pub4ci "${app}" 2>/dev/null || true
doas chgrp _pub4ci /home/dev 2>/dev/null || true
doas chmod 710 /home/dev 2>/dev/null || true
doas chmod -R a+rX "${repo}/MASTER/tools" 2>/dev/null || true
deploy_status "$app" "bundle install + bin/ci"
doas sh -c "su -m ${app} -c 'export HOME=/home/${app}; export PUB4_ROOT=${repo}; export PUB4_CI_GUARD=1; export PUB4_CI_APP=${app}; export PUB4_RAILS_ROOT=${ci_rails_root}; export NPM_CONFIG_CACHE=${npm_cache}; export XDG_CACHE_HOME=${cache_home}; export BUNDLE_USER_HOME=/home/${app}/.bundle; cd ${app_dir} && bundle34 config unset without 2>/dev/null || true && bundle34 config unset deployment 2>/dev/null || true && bundle34 install --jobs=2 && bundle34 exec bin/ci'" \
  || { deploy_status "$app" "bundle install + bin/ci" "failed"; exit 1; }

sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)
started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
doas mkdir -p /var/db/pub4 2>/dev/null || true
doas tee "/var/db/pub4/last_deploy_${app}.json" >/dev/null <<EOF
{"app":"${app}","sha":"${sha}","at":"${started}","status":"ci_ok","host":"$(hostname)"}
EOF
deploy_status "$app" "done" "done"
