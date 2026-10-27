# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "socket"
require "yaml"
require "open3"

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
  CI_SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
  APPS = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps").keys.map(&:to_s)
  MASTER_DEPLOY = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")

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
    degraded = SOURCE[/^DEPLOY_ALL_DEGRADED=\(([^)]*)\)/, 1]&.split
    assert_equal "master", degraded&.last, "when the box cannot take master first, master goes last"
    assert_equal deploy_all.sort, degraded.sort
  end

  def test_deploy_paths_export_openbsd_package_path
    expected = "export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
    assert_includes SOURCE, expected
    assert_includes MASTER_DEPLOY, expected
  end

  def test_it_rejects_an_unknown_deploy_target
    assert_match(
      /case \$app in\n\s+all\|master\|brgen\|amber\|bsdports\) ;;.*\n\s+\*\) .*exit 2/,
      SOURCE,
      "an arbitrary app name must not reach filesystem, service or deploy-stamp paths"
    )
  end

  def test_master_deploy_refuses_root_override
    source = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")
    assert_includes source, 'if [ "$ROOT" != "/home/dev/pub4" ]; then'
    assert_includes source, 'pub4-admin master-web-assets-reset'
    assert_includes source, 'pub4-admin master-web-runtime-dirs'
    refute_includes source, 'doas rm -rf public/assets'
    refute_includes source, 'doas chown -R dev:dev public'
    refute_includes source, 'doas cp "$ROOT/OPENBSD/etc/rc.d/master" /etc/rc.d/master'
  end
  def test_workstation_per_app_mode_uses_canonical_unprivileged_supervisor
    script = File.read(File.join(ROOT, "OPENBSD", "bin", "deploy_all.sh"), encoding: "UTF-8")
    assert_includes script, 'zsh OPENBSD/bin/vps-deploy ${app}'
    refute_includes script, 'doas zsh ${script}'
    refute_includes script, 'RAILS/${app}/${app}.sh'
  end
  def test_ci_rejects_unknown_target_before_interpolating_a_path
    guard = CI_SOURCE[/^case \$app in\n.*?^esac$/m]
    refute_nil guard, "vps_ci app allowlist missing — arbitrary strings may reach path construction"
    assert_operator CI_SOURCE.index("case $app in"), :<, CI_SOURCE.index("app_dir=/home/${app}/app")

    out = IO.popen(
      ["zsh", "-c", "app='../outside'; #{guard}; print accepted", { err: %i[child out] }],
      &:read
    )

    assert_equal 2, $?.exitstatus
    assert_includes out, "unknown app"
    refute_includes out, "accepted"
  end

  def test_root_crontab_staging_is_private_from_deploy_receipts
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"))
    block = operator[/typeset cron_dir=\/var\/db\/pub4\/private.*?chmod 700 "\$cron_dir"/m]

    refute_nil block, "root crontab temp files must not share the public deploy-receipt directory"
    assert_includes block, "chmod 755 /var/db/pub4"
    assert_includes block, "chown root:wheel /var/db/pub4"
  end

  def test_disk_recovery_hint_uses_bounded_broker
    assert_includes SOURCE, "doas /usr/local/sbin/pub4-admin disk-usage $mount_point"
    refute_includes SOURCE, "doas du -xk $mount_point"
  end
  def test_failure_hints_use_the_bounded_service_broker
    assert_includes SOURCE, "doas /usr/local/sbin/pub4-admin service restart <app>"
    assert_includes SOURCE, 'doas /usr/local/sbin/pub4-admin service start $app'
    assert_includes SOURCE, 'doas /usr/local/sbin/pub4-admin service restart $other'
  end

  def test_vps_deploy_fails_closed_without_root_fallbacks
    assert_includes SOURCE, '[[ -f /usr/local/sbin/pub4-admin && -x /usr/local/sbin/pub4-admin && ! -L /usr/local/sbin/pub4-admin ]]'
    refute_match(/^\s*doas\s+rcctl\b/, SOURCE)
    refute_match(/^\s*doas\s+(?:tee|chmod|mkdir)\b/, SOURCE)
    refute_includes SOURCE, 'doas ksh "$repo/OPENBSD/bin/resource_guard.sh"'
    refute_includes SOURCE, 'doas "$RUBY" "$repo/OPENBSD/checks/solid_queue_proof.rb"'
    refute_includes SOURCE, 'doas tee "$file"'
  end
  def test_deploy_uses_the_fixed_root_broker_when_installed
    assert_includes SOURCE, 'doas /usr/local/sbin/pub4-admin service'
    assert_includes SOURCE, 'admin_request stamp "$name" "$sha" "$stamp_status"'
    assert_includes SOURCE, "admin_request resource-guard"
    assert_includes SOURCE, 'admin_request solid-queue-proof "$app"'
  end

  def test_tree_sync_exposes_only_the_fixed_app_user_broker
    sync = File.read(File.join(ROOT, "RAILS", "_sync.sh"), encoding: "UTF-8")
    refute_includes sync, "def sync_tree("
    refute_match(/\$\{_PRIV\}\s+(?:rm|mkdir|mv|tar|openrsync)\b/, sync)
    assert_includes sync, 'pub4-admin rails-sync "$app_name" "$mode"'
    assert_includes sync, 'case "$mode" in'
    assert_includes sync, "app|shared"
    assert_includes sync, "verticals"
  end
  def test_rails_task_runner_fails_closed_without_broker
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")
    runner = runtime[/run_rails_as_app\(\) \{.*?^\}/m]
    refute_nil runner
    assert_includes runner, '[[ -x /usr/local/sbin/pub4-admin ]]'
    assert_includes runner, '"run_rails_as_app: pub4-admin is missing; run OPERATOR.sh before deploying"'
    assert_includes runner, '/usr/local/sbin/pub4-admin rails-task "$app_name" "$task"'
    refute_match(/\$\{_PRIV\} sh -c/, runner)
    refute_match(/su -m/, runner)
    refute_includes runtime, 'secret=$(app_secret_for "$app_name")'
  end
  def test_npm_cache_setup_uses_the_app_owned_task
    bundle = File.read(File.join(ROOT, "RAILS", "_bundle.sh"), encoding: "UTF-8")
    helper = bundle[/ensure_npm_cache\(\) \{.*?^\}/m]
    refute_nil helper
    assert_includes helper, 'run_rails_as_app "$app_name" "/home/${app_name}/app" "npm-cache"'
    refute_match(/\$\{_PRIV\}.*(?:mkdir|chown)/, helper)
  end
  def test_skip_ci_deploy_prepares_checkout_group_before_sync
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    ensure_index = deploy.index('pub4-admin ensure-app "$app_name"')
    access_index = deploy.index('pub4-admin ci-prepare "$app_name"')
    sync_index = deploy.index('rails_sync_app_tree "$app_name" app')

    assert_operator ensure_index, :<, access_index
    assert_operator access_index, :<, sync_index
  end
  def test_production_tree_sync_uses_the_bounded_app_user_helper
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    sync = File.read(File.join(ROOT, "RAILS", "_sync.sh"), encoding: "UTF-8")
    block = deploy[/rails_sync_app_tree "\$app_name" app.*?overlay_shared_public "\$APP_DIR"/m]

    refute_nil block, "production deploy must use the fixed app-user sync path"
    assert_includes block, 'rails_sync_app_tree "$app_name" shared'
    assert_includes block, 'rails_sync_app_tree "$app_name" verticals'
    refute_match(/doas (?:rm|chown|mkdir|mv|sh -c)/, block)
    assert_includes sync, 'pub4-admin rails-sync "$app_name" "$mode"'
    assert_includes sync, "rails_sync_app_tree: pub4-admin is missing"
  end

  def test_rails_bundle_cache_setup_is_app_owned
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    helper = File.read(File.join(ROOT, "OPENBSD", "usr", "local", "libexec", "rails-task.ksh"), encoding: "UTF-8")

    assert_includes deploy, 'run_rails_as_app "$app_name" "$APP_DIR" "bundle-cache-prepare"'
    refute_includes deploy, 'doas mkdir -p "$bundle_home"'
    refute_includes deploy, 'doas chown -R "${app_name}:${app_name}" "$bundle_home"'
    assert_includes helper, 'bundle-cache-prepare)'
    assert_includes helper, 'target="$bundle_home/$part"'
  end

  def test_rails_production_bundle_uses_bounded_broker
    core = File.read(File.join(ROOT, "RAILS", "_bundle.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")

    assert_equal 1, core.scan("bundle_install_as_app() {").length
    assert_includes core, 'run_rails_as_app "$app_name" "$app_dir" "bundle-install"'
    assert_includes File.read(File.join(ROOT, "RAILS", "_runtime_check.sh")), '/usr/local/sbin/pub4-admin rails-task "$app_name" "$task"'
    assert_includes deploy, "[[ -x /usr/local/sbin/pub4-admin ]] || {"
    refute_includes deploy, 'doas chown -R "$app_name:$app_name" "${APP_DIR}/.bundle"'
    refute_includes deploy, 'doas tee "${APP_DIR}/.bundle/config"'
  end

  def test_relayd_adapter_fails_closed_without_broker
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")
    adapter = service[/relayd_add_relay\(\) \{.*?^\}/m]
    refute_nil adapter
    assert_includes adapter, '[[ -x /usr/local/sbin/pub4-admin ]]'
    assert_includes adapter, '"relayd: fixed broker is missing; run OPERATOR.sh before deploying"'
    refute_match(/\$\{_PRIV\}.*\$RUBY/, adapter)
  end
  def test_rails_relayd_route_check_uses_the_fixed_broker
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    assert_includes service, 'pub4-admin relayd-check "$app" "$domain" "$port"'
    assert_includes deploy, 'relayd_add_relay "$APP_NAME" "$APP_DOMAIN" "$APP_PORT"'
    health_probe = service[/relayd_confirm_live\(\) \{.*?^\}/m]
    refute_nil health_probe
    refute_match(/\$\{_PRIV\}.*\$RUBY/m, health_probe)
  end
  def test_app_secret_path_fails_closed_without_the_broker
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    secret_fn = database[/app_secret_for\(\) \{.*?^\}/m]
    refute_nil secret_fn
    assert_includes secret_fn, '[[ -x /usr/local/sbin/pub4-admin ]]'
    assert_includes secret_fn, '"app_secret_for: pub4-admin is missing; run OPERATOR.sh before deploying"'
    assert_includes secret_fn, '"${_PRIV}" /usr/local/sbin/pub4-admin ensure-secret "$app_name"'
    refute_includes secret_fn, '"${_PRIV}" sh -c'
    refute_includes secret_fn, '"${_PRIV}" cat "$env_file"'
  end
  def test_secondary_database_probe_uses_the_fixed_app_task
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    probe = database[/secondary_db_initialized\(\) \{.*?^\}/m]
    refute_nil probe
    assert_includes probe, '"secondary-db-check" "$db"'
    refute_match(/\$\{_PRIV\} sh -c/, probe)
    refute_match(/\$\{_PRIV\} cat/, probe)
  end
  def test_storage_migration_has_no_privileged_path_fallback
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    migration = database[/migrate_sqlite_db_to_storage_if_needed\(\) \{.*?^\}/m]
    refute_nil migration
    assert_includes migration, 'run_rails_as_app "$app_name" "$app_dir" "db-storage-migrate"'
    assert_includes migration, '[[ -x /usr/local/sbin/pub4-admin ]]'
    refute_match(/\$\{_PRIV\}\s+(?:mkdir|mv|chown)\b/, migration)
  end
  def test_rails_database_tasks_use_closed_dispatcher
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")

    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-prepare"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "schema-load" "$db"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "secondary-db-check" "$db"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-storage-migrate"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-seed"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "demo-seed"'
    assert_includes runtime, 'rails-task "$app_name" "$task" "$database"'
  end

  def test_rails_deploy_never_installs_rcd_from_writable_checkout
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")

    refute_includes service, '${_PRIV} install -o root -g wheel -m 0555 "$rcd_src" "$rcd_dst"'
    assert_includes service, 'owner=$(/usr/bin/stat -f %u "$rcd_dst")'
    assert_includes service, 'mode=$(/usr/bin/stat -f %Lp "$rcd_dst")'
    assert_includes service, 'rc.d ${svc} must be root-owned mode 555'
    assert_includes service, '/usr/local/sbin/pub4-admin retire-legacy "$app_name"'
  end

  def test_rails_service_adapter_fails_closed_without_broker
    core = File.read(File.join(ROOT, "RAILS", "_core.sh"), encoding: "UTF-8")
    adapter = core[/pub4_rcctl\(\) \{.*?^\}/m]

    refute_nil adapter
    assert_includes adapter, '[[ -x /usr/local/sbin/pub4-admin ]]'
    assert_includes adapter, 'log_err "pub4_rcctl: pub4-admin is missing'
    assert_includes adapter, '/usr/local/sbin/pub4-admin service "$action" "$service"'
    refute_match(/\$\{_PRIV\}\s+rcctl\b/, adapter)
  end

  def test_rails_deploy_service_lifecycle_uses_closed_broker_adapter
    core = File.read(File.join(ROOT, "RAILS", "_core.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")

    assert_includes core, "pub4_rcctl() {"
    assert_includes core, "check|get|start|stop|restart"
    assert_includes core, '/usr/local/sbin/pub4-admin service "$action" "$service"'
    assert_includes deploy, 'pub4_rcctl stop "$app_name"'
    assert_includes deploy, 'pub4_rcctl restart "$APP_NAME" || pub4_rcctl start "$APP_NAME"'
    refute_includes deploy, 'doas rcctl stop "$app_name"'
  end

  def test_rails_app_deploy_wrappers_refuse_root_execution
    %w[brgen amber bsdports].each do |app|
      source = File.read(File.join(ROOT, "RAILS", app, "#{app}.sh"), encoding: "UTF-8")
      assert_includes source, 'if [[ $(id -u) -eq 0 ]]', "#{app} wrapper must refuse root"
      assert_includes source, 'refusing to run checkout code as root', "#{app} refusal should be explicit"
    end
  end

  def test_legacy_rails_entrypoint_never_escalates_checkout_code
    legacy = File.read(File.join(ROOT, "RAILS", "deploy.sh"), encoding: "UTF-8")

    assert_includes legacy, 'if [[ $(id -u) -eq 0 ]]'
    assert_includes legacy, 'exec zsh "${REPO_ROOT}/OPENBSD/bin/vps-deploy" "$app"'
    refute_includes legacy, 'doas zsh "$script"'
  end

  def test_ci_source_permissions_do_not_grant_world_read
    assert_includes CI_SOURCE, 'chmod -R u+rX,g+rX "${repo}/MASTER/tools"'
    refute_includes CI_SOURCE, 'chmod -R a+rX "${repo}/MASTER/tools"'
    runtime_check = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")
    assert_includes runtime_check, 'chmod -R u+rX,g+rX "$rails_tree"'
    refute_includes runtime_check, 'chmod -R a+rX "$rails_tree"'
  end

  def test_ci_does_not_escalate_permission_changes_on_the_checkout
    refute_includes CI_SOURCE, 'doas chmod -R a+rX "${repo}/MASTER/tools"'
    assert_includes CI_SOURCE, 'chmod -R u+rX,g+rX "${repo}/MASTER/tools"'
    refute_includes CI_SOURCE, 'chmod -R a+rX "${repo}/MASTER/tools"'
  end

  def test_ci_broker_paths_are_installed_and_used_before_sync
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")
    assert_includes operator, 'cp -R "$src/$d"/. "/$d"/'
    assert_includes operator, 'for f in /usr/local/libexec/*(N)'
    assert_includes CI_SOURCE, 'doas /usr/local/sbin/pub4-admin ci-sync "$app"'
    assert_operator CI_SOURCE.index('doas /usr/local/sbin/pub4-admin ci-prepare "$app"'),
                    :<, CI_SOURCE.index("sync_from_repo\n")
  end

  def test_ci_copy_tree_uses_the_app_scoped_broker_helper
    assert_includes CI_SOURCE, 'doas /usr/local/sbin/pub4-admin ci-sync "$app"'
    refute_includes CI_SOURCE, "sync_from_repo_legacy"
    refute_includes CI_SOURCE, "sync_ci_rails_root_legacy"
    assert_includes CI_SOURCE, "unaccounted_tracked_files \"$app\" \"$repo\" paths kept_local"
    assert_operator CI_SOURCE.index('doas /usr/local/sbin/pub4-admin ci-prepare "$app"'),
                    :<, CI_SOURCE.index("sync_from_repo\n")
  end

  def test_ci_fails_closed_without_broker_and_has_no_root_copy_fallback
    assert_includes CI_SOURCE, '[[ -x /usr/local/sbin/pub4-admin ]] || { print -u2 "vps_ci: pub4-admin missing; run reviewed OPENBSD/OPERATOR.sh first"; exit 1 }'
    refute_match(/doas\s+(?:sh\s+-c|(?:rm|mkdir|chown|chmod|tee|groupadd|usermod|tar)\b)/, CI_SOURCE)
    refute_includes CI_SOURCE, "sync_from_repo_legacy"
  end
  def test_ci_runner_uses_the_fixed_broker_and_bounded_timeout
    runner = File.read(File.join(ROOT, "OPENBSD", "usr", "local", "libexec", "ci-run.ksh"), encoding: "UTF-8")
    assert_includes CI_SOURCE, 'doas /usr/local/sbin/pub4-admin ci-run "$app" "$ci_timeout"'
    assert_includes CI_SOURCE, 'ci_timeout=${PUB4_CI_TIMEOUT:-7200}'
    assert_includes runner, 'exec /usr/bin/su -m "$app" -c "$script"'
    refute_includes CI_SOURCE, 'doas sh -c "su -m'
  end

  def test_ci_uses_the_broker_for_account_and_storage_preparation
    assert_includes CI_SOURCE, 'doas /usr/local/sbin/pub4-admin ci-prepare "$app"'
    assert_includes CI_SOURCE, '[[ -x /usr/local/sbin/pub4-admin ]] || { print -u2 "vps_ci: pub4-admin missing; run reviewed OPENBSD/OPERATOR.sh first"; exit 1 }'
    refute_match(/doas\s+(?:sh\s+-c|(?:rm|mkdir|chown|chmod|tee|groupadd|usermod|tar)\b)/, CI_SOURCE)
  end

  def test_it_refuses_to_run_as_root
    assert_match(/if \[\[ \$\(id -u\) -eq 0 \]\]; then/, SOURCE,
                 "the uid guard is gone — root reaches git pull and fails on a host key instead")
    guard = SOURCE[/if \[\[ \$\(id -u\) -eq 0 \]\]; then.*?^fi$/m]

    assert_match(/exit 2/, guard, "the root guard must exit, not warn")
  end

  # SKIP_CI=1 does not mean no check runs: it takes the ${app}.sh branch, which
  # reaches rails_runtime_check through deploy_tracked_app. The name says otherwise,
  # and a hotfix pushed on that belief is how something bin/ci would have caught
  # gets onto the box. The branch must keep running the app script.
  def test_skip_ci_takes_the_narrower_check_rather_than_no_check
    branch = SOURCE[/if \[\[ \$\{SKIP_CI:-\} == 1 \]\]; then(.*?)^else$/m]

    refute_nil branch, "the SKIP_CI branch is gone — the scan broke, or the path did"
    assert_match(%r{RAILS/\$\{app\}/\$\{app\}\.sh}, branch,
                 "SKIP_CI=1 must still run the app script, which is what reaches rails_runtime_check")
  end

  GUARD = File.read(File.join(ROOT, "OPENBSD", "usr", "local", "bin", "resource_guard.sh"), encoding: "UTF-8")

  def flag_block
    SOURCE[/^deploy_flag=.*?^trap 'exit 143' TERM$/m]
  end

  # resource_guard stops shedding while a .deploying* flag is fresh. rc.d holds
  # one only across the restart, so CI and the checks ran as strikes and the app
  # deployed last was shed on the first tick after its flag came off. The flag
  # this script holds has to be one the guard reads, live across the deploy,
  # and gone when the script exits.
  def test_the_deploy_flag_is_held_for_the_whole_deploy_and_released_on_exit
    refute_nil flag_block, "the deploy flag block is gone — the scan broke, or the flag did"
    guard_glob = GUARD[%r{^DEPLOY_FLAGS="(/home/dev/pub4/\.deploying\S*)"$}, 1]
    assert_includes GUARD, "for _flag in $DEPLOY_FLAGS; do", "the guard no longer loops over DEPLOY_FLAGS"
    refute_nil guard_glob, "resource_guard no longer reads a deploy flag glob"

    Dir.mktmpdir do |repo|
      script = "repo=#{repo}; app=bsdports; deploy_log=#{repo}/deploy.log\nrelease_deploy_lock() { :; }\n#{flag_block}\nhold_deploy_flag\nprint -r -- $deploy_flag\n[[ -e $deploy_flag ]] && print held\n"
      out = IO.popen(["zsh", "-c", script], &:read).lines.map(&:chomp)
      flag = out.first

      assert_equal "held", out.last, "the flag is not on disk while the deploy runs"
      assert File.fnmatch?(guard_glob.sub("/home/dev/pub4", repo), flag, File::FNM_DOTMATCH),
             "#{flag} is not a name resource_guard's #{guard_glob} reads"
      refute File.exist?(flag), "the flag outlived the script, so shedding stays off for 30 minutes"

      rcd_flag = File.read(File.join(ROOT, "OPENBSD", "etc", "rc.d", "bsdports"), encoding: "UTF-8")[%r{touch \S+/(\.deploying\S*)}, 1]
      refute_equal rcd_flag, File.basename(flag),
                   "rc.d removes its own flag after /up, so sharing its name drops the hold mid-deploy"
    end
  end

  def lock_block
    SOURCE[/^lock_dir=.*?^\[\[ -n \$\{VPS_DEPLOY_LOCK_HELD:-\} \]\] \|\| acquire_deploy_lock$/m]
  end

  # Runs the lock block alone in zsh against a scratch directory; returns [output, exit status].
  def lock_run(dir, ttl: 7200, body: "print acquired")
    script = "export VPS_DEPLOY_LOCK_DIR=#{dir}/deploy.lock VPS_DEPLOY_LOCK_TTL=#{ttl}\n#{lock_block}\n#{body}\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def test_a_lock_records_its_owner_and_is_released_on_exit
    refute_nil lock_block, "the lock block is gone — the scan broke, or the lock did"
    Dir.mktmpdir do |dir|
      out, status = lock_run(dir, body: "print -r -- $(<$lock_dir/owner)\nrelease_deploy_lock")
      pid, host, epoch = out.lines.last.split

      assert_equal 0, status
      assert_match(/\A\d+\z/, pid)
      assert_equal Socket.gethostname.split(".").first, host
      assert_in_delta Time.now.to_i, epoch.to_i, 30
      refute Dir.exist?(File.join(dir, "deploy.lock")), "release left the lock behind"
    end
  end

  def test_a_lock_whose_pid_is_gone_is_reaped_and_reported
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner"), "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n")
      out, status = lock_run(dir)

      assert_equal 0, status
      assert_includes out, "reaping stale lock"
      assert_includes out, "owner pid 999999 is not running"
      assert_includes out, "acquired"
    end
  end

  def test_stale_lock_recovery_does_not_touch_a_lock_claimed_by_another_reaper
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n"
      File.write(File.join(lock, "owner"), owner)
      Dir.mkdir(File.join(lock, "reaping"))

      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")),
                   "a competing reaper must not remove the original owner's record"
      assert Dir.exist?(File.join(lock, "reaping")),
             "the first reaper's claim must remain untouched"
    end
  end

  def test_two_simultaneous_stale_lock_reapers_never_both_acquire
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      barrier = File.join(dir, "reapers-ready")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner"), "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n")

      observed_lock = 'before_identity=$(stat -f \'%d:%i\' "$lock_dir" 2>/dev/null) || return 1'
      barrier_step = <<~'ZSH'
        # $(<file) drops the trailing newline, so two pids read back with one.
        print -r -- "$$" >> "$VPS_DEPLOY_TEST_BARRIER"
        local -i waited=0
        while [[ $(<"$VPS_DEPLOY_TEST_BARRIER") != *$'\n'* ]] && (( waited < 200 )); do
          sleep 0.01
          (( waited += 1 ))
        done
        [[ $(<"$VPS_DEPLOY_TEST_BARRIER") == *$'\n'* ]] || return 1
        OBSERVED_LOCK
      ZSH
      barrier_step = barrier_step.sub("OBSERVED_LOCK", observed_lock).strip
      racing_block = lock_block.sub(observed_lock, barrier_step)
      refute_equal lock_block, racing_block, "the two-process barrier did not attach to stale-lock recovery"

      output_paths = 2.times.map { |i| File.join(dir, "reaper-#{i}.log") }
      pids = output_paths.each_with_index.map do |output_path, i|
        script = "#{racing_block}\nsleep 0.2\nprint -r -- acquired-#{i}\n"
        Process.spawn(
          {
            "VPS_DEPLOY_LOCK_DIR" => lock,
            "VPS_DEPLOY_LOCK_TTL" => "7200",
            "VPS_DEPLOY_TEST_BARRIER" => barrier,
          },
          "zsh", "-c", script,
          out: output_path, err: [:child, :out]
        )
      end
      statuses = pids.map { |pid| Process.wait2(pid).last.exitstatus }
      outputs = output_paths.map { |path| File.read(path) }

      assert_equal [0, 75], statuses.sort, outputs.inspect
      assert_equal 1, outputs.count { |out| out.match?(/acquired-\d/) },
                   "exactly one deploy may acquire the lock after simultaneous stale observations"
    end
  end

  def test_a_live_local_owner_is_not_reaped_just_because_the_ttl_elapsed
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i - 9000}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's stale timestamp must not let a second deploy steal its lock"
    end
  end

  def test_a_live_fresh_lock_refuses_the_second_deploy
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's record was disturbed"
    end
  end

  def test_a_bare_fresh_lock_directory_is_left_alone_and_a_stale_one_is_reaped
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      _out, status = lock_run(dir)
      assert_equal 75, status

      File.utime(Time.now - 9000, Time.now - 9000, lock)
      out, status = lock_run(dir)
      assert_equal 0, status
      assert_includes out, "no readable owner"
    end
  end

  def test_the_flag_is_taken_before_ci_and_the_app_is_checked_before_ok
    assert_operator SOURCE.index("\nkeep_deploy_flag\n"), :<, SOURCE.index("OPENBSD/bin/vps_ci.sh")
    assert_operator SOURCE.index("kill $flag_keeper"), :<, SOURCE.index(%(rm -f -- "$deploy_flag"))
    assert_operator SOURCE.rindex(%(admin_service check "$app")), :>, SOURCE.index(%(CHECK_AUTOFIX=0 "$RUBY" "$repo/MASTER/checks/runner.rb"))
  end

  # The copy-tree on vm23 keeps path gems beside app/, so every ../X an app
  # Gemfile names must be a directory vps_ci.sh syncs there. The layout moved
  # (shared became __shared, engines/ became sibling brgen_* directories) and the
  # CI mirror kept building the old one until a deploy died on
  # "The path /home/brgen/__shared does not exist".
  def test_ci_mirror_syncs_every_sibling_path_gem_the_gemfiles_name
    ci = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
    sync = File.read(File.join(ROOT, "OPENBSD", "usr", "local", "libexec", "ci-sync.ksh"), encoding: "UTF-8")
    assert_includes sync, "shared_dir=$app_home/__shared"
    assert_includes sync, "RAILS/brgen_*"
    # The suite outlasts the guard's one-hour default on this box.
    assert_includes ci, "ci_timeout=${PUB4_CI_TIMEOUT:-7200}"
    # A directory the repo no longer has must not survive the sync, or its stale tests keep running.
    assert_includes sync, '[ -d "$src/engines" ] || rm -rf "$app_dir/engines"'

    APPS.each do |app|
      gemfile = File.join(ROOT, "RAILS", app, "Gemfile")
      next unless File.file?(gemfile)

      File.read(gemfile, encoding: "UTF-8").scan(%r{path:\s*"\.\./([^/"]+)}).flatten.uniq.each do |sibling|
        synced = sibling == "__shared" || (app == "brgen" && sibling.start_with?("brgen_"))
        assert synced, "#{app}/Gemfile names ../#{sibling}, which vps_ci.sh does not sync beside app/"
      end
    end
  end

  # The trap block alone, in zsh, with doas and write_stamp stubbed: what a failed
  # deploy says, stamps and leaves behind is the contract an operator reads at 3 a.m.
  def finish_block
    SOURCE[/^deploy_stage=start$.*?^trap 'exit 143' TERM$/m]
  end

  def finish_run(dir, body, down: "amber")
    log = File.join(dir, "deploy.log")
    script = <<~ZSH
      app=brgen; repo=#{dir}; deploy_log=#{log}; deploy_flag=#{dir}/.flag; lock_owner=0
      release_deploy_lock() { print released; }
      write_stamp() { stamp_written=1; print "stamp $1 $2"; }
      doas() { [[ $1 == rcctl && $2 == check && $3 == #{down} ]] && return 1; return 0; }
      admin_service() { doas rcctl "$@"; }
      #{finish_block}
      touch $deploy_flag
      #{body}
    ZSH
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus, File.exist?(log) ? File.read(log) : ""]
  end

  def test_a_failure_after_the_stop_stamps_failed_names_the_stage_and_what_is_down
    refute_nil finish_block, "the terminal-result block is gone — the scan broke, or the block did"
    Dir.mktmpdir do |dir|
      out, status, log = finish_run(dir, "deploy_stage=migrate; app_stopped=1; exit 1")

      assert_equal 1, status
      assert_includes out, "stamp brgen failed"
      assert_includes out, 'brgen FAILED at stage "migrate" (exit 1)'
      assert_includes out, "brgen was stopped for this deploy and is DOWN"
      assert_includes out, "doas /usr/local/sbin/pub4-admin service start brgen"
      assert_includes out, "amber is DOWN"
      refute_includes out, "bsdports is DOWN"
      assert_includes out, "released"
      assert_match(/exit=1 stage=migrate/, log)
      refute File.exist?(File.join(dir, ".flag")), "the deploy flag outlived the script"
    end
  end

  def test_a_failure_before_the_stop_says_the_previous_release_is_still_serving
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "deploy_stage=ci+sync; exit 3", down: "none")

      assert_equal 3, status
      assert_includes out, 'FAILED at stage "ci+sync" (exit 3)'
      assert_includes out, "was not stopped; the previous release is still serving"
      refute_includes out, "is DOWN"
    end
  end

  def test_a_stage_that_already_stamped_is_not_stamped_twice_and_success_is_logged_quietly
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "write_stamp brgen failed; exit 1")
      assert_equal 1, status
      assert_equal 1, out.scan("stamp brgen failed").size

      out, status, log = finish_run(dir, "deploy_stage=final-check; exit 0")
      assert_equal 0, status
      refute_includes out, "FAILED"
      assert_match(/exit=0 stage=final-check/, log)
    end
  end

  def test_a_kill_or_a_dropped_session_is_a_recorded_failure_not_a_silent_end
    Dir.mktmpdir do |dir|
      %w[TERM HUP].each do |signal|
        out, status, log = finish_run(dir, "deploy_stage=precompile; kill -#{signal} $$; sleep 5")
        assert_equal({ "TERM" => 143, "HUP" => 129 }.fetch(signal), status, signal)
        assert_includes out, 'FAILED at stage "precompile"'
        assert_includes log, "stage=precompile"
      end
    end
  end

  # `all` exits from its own loop; a trap installed after that branch never ran for
  # the parent, so every full deploy left its lock to the stale reaper.
  def test_the_terminal_trap_is_installed_before_the_all_branch_can_exit
    assert SOURCE.index("trap finish EXIT") < SOURCE.index("if [[ $app == all ]]; then\n  typeset"),
           "the parent of `vps-deploy all` exits without releasing its lock"
  end

  def disk_block
    SOURCE[/^deploy_stage=preflight-disk$.*?^done$/m]
  end

  def disk_run(dir, free_kb:)
    File.write(File.join(dir, "df"), "#!/bin/sh\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/sd0k 17000000 1000 #{free_kb} 80%% %s\\n' \"$2\"\n")
    File.chmod(0o755, File.join(dir, "df"))
    File.write(File.join(dir, "df"), "#!/bin/sh\nfor last; do :; done\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/x 17000000 1000 #{free_kb} 80%% %s\\n' \"$last\"\n")
    script = "app=brgen; VPS_DEPLOY_DF=#{dir}/df\n#{disk_block}\nprint passed\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def test_a_nearly_full_filesystem_refuses_the_deploy_before_anything_is_stopped
    refute_nil disk_block, "the disk preflight is gone - the scan broke, or the check did"
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 200_000)

      assert_equal 1, status
      assert_includes out, "/home has 195 MB free, the floor is 1024 MB"
      assert_includes out, "Nothing was stopped"
      assert_includes out, "zsh OPENBSD/bin/vps-deploy brgen"
      refute_includes out, "passed"
    end
  end

  def test_enough_free_space_lets_the_deploy_continue
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 4_000_000)

      assert_equal 0, status, out
      assert_includes out, "passed"
    end
  end

  def test_unavailable_disk_measurement_refuses_the_deploy_before_anything_is_stopped
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: "unavailable")

      assert_equal 1, status
      assert_includes out, "free-space measurement for /home is unavailable"
      assert_includes out, "Nothing was stopped"
      refute_includes out, "passed"
    end
  end
  def deploy_setting_result(value, minimum:, maximum:)
    validator = SOURCE[/^validate_deploy_setting\(\) \{.*?^\}/m]
    refute_nil validator, "the deploy setting validator is missing"
    script = <<~ZSH
      #{validator}
      validate_deploy_setting TEST_SETTING "$TEST_VALUE" #{minimum} #{maximum}
    ZSH
    out, status = Open3.capture2e({ "TEST_VALUE" => value }, "zsh", "-c", script)
    [out, status.exitstatus]
  end

  def test_deploy_timing_overrides_reject_zero_negative_and_nondecimal_values
    ["0", "-1", "1.5", "1e3", "01", "", "999999999999999999999"].each do |value|
      out, status = deploy_setting_result(value, minimum: 1, maximum: 60)
      refute_equal 0, status, "accepted invalid timing value #{value.inspect}"
      assert_includes out, "invalid TEST_SETTING"
    end
  end

  def test_deploy_capacity_threshold_allows_only_bounded_decimal_percentages
    out, status = deploy_setting_result("0", minimum: 0, maximum: 100)
    assert_equal 0, status, out
    out, status = deploy_setting_result("100", minimum: 0, maximum: 100)
    assert_equal 0, status, out
    ["-1", "101", "10x", "010"].each do |value|
      out, status = deploy_setting_result(value, minimum: 0, maximum: 100)
      refute_equal 0, status, "accepted invalid percentage #{value.inspect}"
      assert_includes out, "invalid TEST_SETTING"
    end
  end

  def test_every_environment_driven_wait_and_capacity_setting_is_validated_before_locking
    %w[
      VPS_DEPLOY_LOCK_TTL
      VPS_DEPLOY_RESTORE_WAIT
      VPS_DEPLOY_POLL
      VPS_DEPLOY_SETTLE_WAIT
      VPS_DEPLOY_MASTER_MIN_AVAIL
      VPS_DEPLOY_MIN_FREE_KB
    ].each do |name|
      assert_includes SOURCE, "validate_deploy_setting #{name}", "#{name} can influence arithmetic without validation"
    end

    assert_operator SOURCE.index("validate_deploy_setting VPS_DEPLOY_LOCK_TTL"),
                    :<, SOURCE.index("acquire_deploy_lock"),
                    "invalid environment must be rejected before a deployment lock is created"
  end

end
