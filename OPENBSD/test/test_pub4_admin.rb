# frozen_string_literal: true

require "minitest/autorun"
load File.expand_path("../usr/local/sbin/pub4-admin", __dir__)

class Pub4AdminTest < Minitest::Test
  ADMIN = Pub4Admin

  def test_disk_usage_broker_accepts_only_deploy_mount_roots
    assert_equal ["/usr/bin/du", "-xk", "/home"],
                 ADMIN.command_for(["disk-usage", "/home"])
    assert_equal ["/usr/bin/du", "-xk", "/var"],
                 ADMIN.command_for(["disk-usage", "/var"])
    assert_nil ADMIN.command_for(["disk-usage", "/home/dev/pub4"])
    assert_nil ADMIN.command_for(["disk-usage", "/etc"])
    assert_nil ADMIN.command_for(["disk-usage", ";id"])
  end
  def test_relayd_restart_is_the_only_brokered_relayd_mutation
    assert_equal ["/usr/sbin/rcctl", "restart", "relayd"],
                 ADMIN.command_for(%w[service restart relayd])
    assert_equal ["/usr/sbin/rcctl", "check", "relayd"],
                 ADMIN.command_for(%w[service check relayd])
    assert_nil ADMIN.command_for(%w[service stop relayd])
  end
  def test_service_action_maps_to_fixed_argv
    assert_equal ["/usr/sbin/rcctl", "restart", "brgen"],
                 ADMIN.command_for(%w[service restart brgen])
    assert_equal ["/usr/sbin/rcctl", "check", "master"],
                 ADMIN.command_for(%w[service check master])
  end

  def test_relayd_health_check_is_read_only
    assert_equal ["/usr/sbin/rcctl", "check", "relayd"],
                 ADMIN.command_for(%w[service check relayd])
    assert_nil ADMIN.command_for(%w[service restart relayd])
  end
  def test_only_known_service_targets_are_admitted
    %w[master brgen amber bsdports brgen_jobs amber_jobs bsdports_jobs].each do |service|
      refute_nil ADMIN.command_for(["service", "check", service])
    end

    assert_nil ADMIN.command_for(%w[service restart relayd])
    assert_nil ADMIN.command_for(%w[service restart sshd])
    assert_nil ADMIN.command_for(["service", "restart", "../root"])
  end

  def test_service_verb_and_argument_shape_are_closed
    assert_nil ADMIN.command_for(%w[service set brgen flags arbitrary])
    assert_nil ADMIN.command_for(%w[service shell brgen])
    assert_nil ADMIN.command_for(%w[service restart brgen extra])
    assert_nil ADMIN.command_for(%w[service restart])
    assert_nil ADMIN.command_for(%w[run sh -c id])
    assert_nil ADMIN.command_for(%w[stamp brgen abc1234 ok])
  end

  def test_deploy_status_is_a_fixed_atomic_app_record
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    core = File.read(File.expand_path("../../RAILS/_core.sh", __dir__))

    assert_includes source, 'args.length == 4 && args[0] == "deploy-status"'
    assert_includes source, "def write_deploy_status(app, step, state)"
    assert_includes source, 'File.join(directory, "#{app}.json")'
    assert_includes source, "File::CREAT | File::EXCL"
    assert_includes source, "File.link(temporary, target)"
    assert_includes source, 'raise "#{target} is a symlink; refusing status write"'
    assert_includes core, 'pub4-admin deploy-status "$app" "$step" "$state"'
  end

  def test_ci_lock_is_a_fixed_broker_verb
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    assert_includes source, 'return ensure_ci_lock if args == ["ci-lock"]'
    assert_includes source, 'path = File.join(STAMP_DIR, "ci.lock")'
    assert_includes source, 'raise "#{path} is not a regular file" unless lock.file? && !lock.symlink?'
  end

  def test_ensure_secret_is_an_atomic_fixed_app_operation
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, 'args[0] == "ensure-secret" && APPS.include?(args[1])'
    assert_includes source, "def ensure_app_secret(app, emit: true)"
    assert_includes source, "File.lstat(path)"
    assert_includes source, "SecureRandom.hex(64)"
    assert_includes source, "File::CREAT | File::EXCL"
    assert_includes source, "File.link(temporary, target)"
    assert_includes source, "already exists without a valid SECRET_KEY_BASE; refusing to replace the environment file"
    assert_includes source, "File.chmod(0o640, temporary)"
  end
  def test_bundle_cache_broker_accepts_only_fixed_actions_versions_and_paths
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, 'args.length == 4 && args[0] == "bundle-cache"'
    assert_includes source, "def bundle_cache(app, action, ruby_key)"
    assert_includes source, 'BUNDLE_CACHE_BASE = "/var/cache/pub4/bundle"'
    assert_includes source, "%w[prepare import capture].include?(action)"
    assert_includes source, "File.link(temporary, target)"
    assert_includes source, "File::CREAT | File::EXCL"
    assert_includes source, "128 * 1024 * 1024"
    assert_includes source, "bundle cache import exceeds 500 files"
  end
  def test_master_web_preparation_is_fixed_path_and_symlink_safe
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, 'MASTER_WEB_ROOT = "/home/dev/pub4/RAILS/master"'
    assert_includes source, 'args == ["master-web-assets-reset"]'
    assert_includes source, 'args == ["master-web-runtime-dirs"]'
    assert_includes source, "def master_web_root!"
    assert_includes source, "MASTER_WEB_ROOT.split(File::SEPARATOR)"
    assert_includes source, "File.join(MASTER_WEB_ROOT, \"public\")"
    assert_includes source, "def master_web_tree_paths!(root)"
    assert_includes source, "File.lstat(path)"
    assert_includes source, "Find.find(root)"
    assert_includes source, "raise \"symlink refused in MASTER web path: #{path}\" if stat.symlink?"
    assert_includes source, "File.chown(dev.uid, master.gid, entry)"
  end
  def test_ci_timeout_is_a_real_process_group_deadline
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    assert_includes source, "def valid_ci_timeout?(value)"
    assert_includes source, "def run_ci(app, duration)"
    assert_includes source, "Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration"
    assert_includes source, 'Process.kill("TERM", -pid)'
    assert_includes source, 'Process.kill("KILL", -pid)'
    assert_includes source, "return 124"
    assert_includes source, "unsetenv_others: true"
  end

  def test_relayd_broker_only_verifies_root_approved_routes
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, 'args.length == 4 && args[0] == "relayd-check"'
    assert_includes source, "def relayd_check(app, domain, requested_port)"
    assert_includes source, "File.lstat(RELAYD_CONFIG)"
    assert_includes source, 'no operator-approved Host route for #{domain}'
    assert_includes source, "requested port does not match the root-configured backend"
    refute_includes source, "def relayd_add(app, domain, requested_port)"
    refute_includes source, "File.rename(temporary, RELAYD_CONFIG)"
  end
  def test_first_deploy_secret_does_not_replace_a_racing_secret
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    method = source[/def ensure_app_secret\(app, emit: true\).*?^  end/m]
    refute_nil method
    assert_includes method, "File.link(temporary, target)"
    refute_includes method, "File.rename(temporary, target)"
    assert_includes method, "rescue Errno::EEXIST"
  end
  def test_rails_task_bootstraps_missing_secret_without_printing_it
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, "ensure_app_secret(app, emit: false)"
    assert_includes source, 'rescue RuntimeError => error'
    assert_includes source, 'raise unless error.message == "no valid SECRET_KEY_BASE for #{app}"'
    assert_includes source, "puts secret if emit"
  end
  def test_rails_secret_is_passed_in_environment_not_command_text
    broker = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    assert_includes broker, 'environment["SECRET_KEY_BASE"] = environment_secret if environment_secret'
    assert_includes broker, "environment_secret = app_secret_value(app)"
    assert_includes helper, "export SECRET_KEY_BASE"
    refute_includes helper, 'command="SECRET_KEY_BASE=$secret'
  end
  def test_rails_sync_stages_only_git_tracked_head
    helper = File.read(File.expand_path("../usr/local/libexec/rails-sync.ksh", __dir__))
    assert_includes helper, 'git -c safe.directory="$repo" -C "$repo" archive HEAD "RAILS/$source_rel"'
    assert_includes helper, 'archive_tracked_tree "$source_dir" "$stage"'
    refute_includes helper, 'tar cf - -C "$source_dir" .'
    assert_includes helper, 'source_rel=${source_dir#"$rails_root"/}'
  end
  def test_rails_task_uses_its_own_app_allowlist
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, "known_apps = helper == RAILS_TASK ? RAILS_TASK_APPS : RAILS_APPS"
    assert_includes source, "RAILS_TASK_APPS = %w[master brgen amber bsdports].freeze"
  end
  def test_npm_cache_task_is_app_owned_and_symlink_safe
    broker = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    assert_includes broker, "npm-cache"
    assert_includes helper, "npm-cache)"
    assert_includes helper, 'for cache_dir in "$app_home/.npm" "$app_home/.cache" "$app_home/.bundle"; do'
    assert_includes helper, '[ "$(stat -f %u "$cache_dir")" = "$app_uid" ]'
    assert_includes helper, 'command="mkdir -p /home/$app/.npm /home/$app/.cache"'
  end
  def test_rails_task_refuses_symlinked_database_ancestors
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    assert_includes helper, '[ ! -L "$app_dir/db" ]'
    assert_includes helper, '[ ! -L "$app_dir/storage" ]'
    assert_includes helper, '[ "$(stat -f %u "$app_dir/storage")" = "$app_uid" ]'
  end
  def test_bundle_cas_hydration_copies_root_objects_as_the_app
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    runtime = File.read(File.expand_path("../../RAILS/_runtime_gate.sh", __dir__))
    bundle = File.read(File.expand_path("../../RAILS/_bundle.sh", __dir__))
    assert_includes helper, "bundle-cas-hydrate)"
    assert_includes helper, 'export PUB4_TASK_RUBY=$ruby_path'
    assert_includes helper, 'ruby_version=$("$PUB4_TASK_RUBY" -e "print RUBY_VERSION.split(46.chr).first(2).join")'
    refute_includes helper, 'ruby_version=$("$ruby_path"'
    assert_includes helper, 'cp "$source" "$target"'
    assert_includes helper, 'sha256 -q "$source"'
    refute_includes helper, 'ln "$source" "$target"'
    assert_includes runtime, "bundle-cas-hydrate"
    assert_includes bundle, 'pub4-admin bundle-cache "$app_name" capture "$RUBY_CACHE_KEY"'
    cas_block = bundle[/bundle_cas_prepare\(\) \{.*?^\}/m]
    refute_nil cas_block
    refute_match(/\$\{_PRIV\}\s+(?:mkdir|cp|ln|chown)\b/, cas_block)
  end
  def test_rails_task_accepts_only_closed_app_task_arguments
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    assert_includes source, 'args[0] == "rails-task" && RAILS_TASK_APPS.include?(args[1])'
    assert_includes source, 'args[0] == "ensure-secret" && APPS.include?(args[1])'
    assert_includes source, "RAILS_TASK_APPS = %w[master brgen amber bsdports].freeze"
    assert_includes helper, "master|brgen|amber|bsdports"
    assert_includes helper, "bundle-install|bundle-check|ci-bundle-install|db-prepare|db-seed|assets-precompile|ci"
    assert_includes source, "db-storage-migrate"
    assert_includes helper, "db-storage-migrate)"
    assert_includes helper, '[ ! -L db ]'
    assert_includes helper, '[ ! -L storage ]'
    assert_includes helper, "case \"$database\" in cache|queue|cable)"
    assert_includes helper, "secondary-db-check)"
    assert_includes helper, 'table=$("$ruby_path" -e '
    assert_includes source, '%w[schema-load secondary-db-check].include?(task)'
    assert_includes helper, "export SECRET_KEY_BASE"
    refute_includes helper, 'command="SECRET_KEY_BASE=$secret'
    refute_includes helper, "sh -c \"$command\""
  end
  def test_ci_run_accepts_only_fixed_apps_and_bounded_timeouts
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/ci-run.ksh", __dir__))

    assert_includes source, 'args[0] == "ci-run" && RAILS_APPS.include?(args[1])'
    assert_includes source, "supervised_helper(CI_RUN, app, duration)"
    assert_includes helper, 'brgen|amber|bsdports'
    assert_includes helper, '[ "$timeout" -le 7200 ]'
    assert_includes helper, 'exec /usr/bin/su -m "$app" -c "$script"'
    assert_equal 1, helper.scan('exec /usr/bin/su -m "$app" -c "$script"').length
    assert helper.end_with?("exec /usr/bin/su -m \"$app\" -c \"$script\"\\n")
    refute_includes helper, "EOF_KEY"
    assert_equal 1, helper.scan("exec /usr/bin/su -m").length
    refute_includes helper, 'sh -c "$script"'
  end

  def test_shell_syntax_gate_covers_privileged_libexec_helpers
    source = File.read(File.expand_path("../gates/shell_syntax_gate.rb", __dir__))
    assert_includes source, 'Dir.glob("OPENBSD/usr/local/libexec/**/*.ksh")'
  end
  def test_ci_sync_pins_git_safe_directory
    helper = File.read(File.expand_path("../usr/local/libexec/ci-sync.ksh", __dir__))

    assert_operator helper.scan('git -c safe.directory="$repo" -C "$repo"').length, :>=, 3
    refute_includes helper, 'git -C "$repo"'
    assert_includes helper, "GIT_CONFIG_NOSYSTEM"
    assert_includes helper, "GIT_CONFIG_GLOBAL=/dev/null"
  end

  def test_bundle_cache_preparation_is_app_owned_and_fixed
    broker = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    deploy = File.read(File.expand_path("../../RAILS/_deploy.sh", __dir__))
    runtime = File.read(File.expand_path("../../RAILS/_runtime_gate.sh", __dir__))

    assert_includes broker, "bundle-cache-prepare"
    assert_includes helper, "bundle-cache-prepare)"
    assert_includes helper, 'bundle_home="$home/.bundle"'
    assert_includes helper, 'target="$bundle_home/$part"'
    assert_includes helper, 'stat -f %u "$bundle_home"'
    assert_includes deploy, 'run_rails_as_app "$app_name" "$APP_DIR" "bundle-cache-prepare"'
    assert_includes runtime, 'bundle-cache-prepare|db-storage-migrate'
    refute_includes deploy, 'doas mkdir -p "$bundle_home"'
    refute_includes deploy, 'doas chown -R "${app_name}:${app_name}" "$bundle_home"'
  end

  def test_production_bundle_uses_the_fixed_rails_task
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))

    assert_includes source, 'args[0] == "rails-task" && RAILS_TASK_APPS.include?(args[1])'
    assert_includes source, "run_rails_task(args[1], args[2])"
    assert_includes helper, 'bundle-install|bundle-check|ci-bundle-install|db-prepare|db-seed|assets-precompile|ci'
    assert_includes helper, 'BUNDLE_PATH: /home/$app/.bundle/gems'
    assert_includes helper, 'RAILS_ENV=production $bundle install'
    assert_includes helper, 'exec /usr/bin/su -m "$app" -c "$script"'
    refute_includes helper, 'sh -c "$script"'
  end

  def test_shared_overlays_are_app_user_fixed_tasks
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    runtime = File.read(File.expand_path("../../RAILS/_runtime_gate.sh", __dir__))
    sync = File.read(File.expand_path("../../RAILS/_sync.sh", __dir__))

    assert_includes source, "overlay-initializers overlay-public"
    assert_includes helper, "overlay-initializers|overlay-public"
    assert_includes helper, 'shared=/home/dev/pub4/RAILS/__shared/config/initializers'
    assert_includes helper, "icon.svg|icon.png|icon-192.png|apple-touch-icon.png|favicon.ico|manifest.json|manifest.webmanifest"
    assert_includes runtime, "overlay-initializers|overlay-public"
    assert_includes sync, 'run_rails_as_app "$app_name" "$app_dir" "overlay-initializers"'
    assert_includes sync, 'run_rails_as_app "$app_name" "$app_dir" "overlay-public"'
    refute_match(/^\s*\$\{_PRIV\}\s+(?:mkdir|cp)/, sync)
  end

  def test_ci_sync_runs_only_as_the_selected_app
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/ci-sync.ksh", __dir__))

    assert_includes source, 'args[0] == "ci-sync" && RAILS_APPS.include?(args[1])'
    assert_includes source, "supervised_helper(CI_SYNC, app, 900)"
    assert_includes source, "spawn_options[:uid] = account.uid"
    assert_includes source, "spawn_options[:gid] = account.gid"
    assert_includes source, "spawn_options[:groups] = [account.gid, shared_gid].uniq"
    assert_includes helper, 'repo=/home/dev/pub4'
    assert_includes helper, '[ "$(id -un)" = "$app" ]'
    refute_match(/^\s*(?:doas|sudo|chown)\b/, helper)
  end

  def test_ci_prepare_validates_app_ancestors_before_storage_chmod
    helper = File.read(File.expand_path("../usr/local/libexec/ci-prepare.ksh", __dir__))

    assert_includes helper, 'app_uid=$(/usr/bin/id -u "$app")'
    assert_includes helper, '[ ! -L "$app_home" ]'
    assert_includes helper, '[ ! -L "$app_dir" ]'
    assert_includes helper, '[ "$(stat -f %u "$storage")" = "$app_uid" ]'
    assert_operator helper.index('[ ! -L "$app_dir" ]'), :<, helper.index('/bin/chmod 750 "$storage"')
  end

  def test_ci_prepare_creates_group_before_changing_checkout_parent
    helper = File.read(File.expand_path("../usr/local/libexec/ci-prepare.ksh", __dir__))
    group_create_at = helper.index("/usr/sbin/groupadd _pub4ci")
    usermod_at = helper.index("/usr/sbin/usermod -G _pub4ci \"$app\"")
    chgrp_at = helper.index("/bin/chgrp _pub4ci /home/dev")

    assert_operator group_create_at, :<, usermod_at
    assert_operator usermod_at, :<, chgrp_at
  end
  def test_ci_prepare_is_one_fixed_app_scoped_operation
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/ci-prepare.ksh", __dir__))

    assert_includes source, 'args[0] == "ci-prepare" && RAILS_APPS.include?(args[1])'
    assert_includes source, 'trusted_script!(CI_PREPARE)'
    assert_includes source, 'exec("/bin/ksh", CI_PREPARE, args[1])'
    assert_includes helper, 'brgen|amber|bsdports'
    assert_includes helper, 'storage="$app_dir/storage"'
    assert_includes helper, '[ ! -L /home/dev ]'
    assert_includes helper, '[ -L "$storage" ]'
  end

  def test_legacy_service_retirement_maps_only_rails_apps
    assert_equal "brgen_rails", ADMIN.legacy_service_name("brgen")
    assert_equal "amber_rails", ADMIN.legacy_service_name("amber")
    assert_equal "bsdports_rails", ADMIN.legacy_service_name("bsdports")
    assert_nil ADMIN.legacy_service_name("master")
    assert_nil ADMIN.legacy_service_name("../root")
  end

  def test_started_service_inventory_is_a_fixed_read_operation
    assert_equal ["/usr/sbin/rcctl", "ls", "started"],
                 ADMIN.command_for(%w[service list-started])
  end

  def test_started_services_are_filtered_to_the_broker_allowlist
    output = "sshd\nrelayd\nmaster\nbrgen\ncron\nbsdports_jobs\n"

    assert_equal "master\nbrgen\nbsdports_jobs",
                 ADMIN.filter_started_services(output)
  end

  def test_privileged_action_set_excludes_service_configuration_mutation
    refute_includes ADMIN::SERVICE_ACTIONS, "enable"
    refute_includes ADMIN::SERVICE_ACTIONS, "disable"
    refute_nil ADMIN.command_for(%w[service restart brgen])
    assert_nil ADMIN.command_for(%w[service enable brgen])
    assert_nil ADMIN.command_for(%w[service disable brgen])
  end

  def test_root_script_does_not_evaluate_shell_command_strings
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    refute_match(/system\s*\(|Open3\.|%x/, source)
    assert_equal 1, source.scan("Process.spawn").length
    assert_match(/Process\.spawn\(environment, "\/bin\/ksh", helper, \*arguments, \*\*spawn_options\)/, source)
    assert_includes source, "raise \"unknown helper\" unless [CI_RUN, CI_SYNC, RAILS_TASK].include?(helper)"
    assert_includes source, "spawn_options[:uid] = account.uid"
    assert_includes source, "spawn_options[:groups] = [account.gid, shared_gid].uniq"
    assert_includes source, "exec(*command)"
    assert_includes source, 'raise "must run as root through doas" unless Process.euid.zero?'
  end

  def test_privileged_helpers_must_be_root_owned_and_non_writable
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    assert_includes source, "stat.symlink? || !stat.uid.zero? || (stat.mode & 0o022).positive?"
    assert_includes source, "File.lstat(current)"
    assert_includes source, "trusted_script!(RESOURCE_GUARD)"
    assert_includes source, "trusted_script!(SOLID_QUEUE_PROOF)"
  end
end
