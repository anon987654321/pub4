# frozen_string_literal: true

require "minitest/autorun"
load File.expand_path("../usr/local/sbin/pub4-admin", __dir__)

class Pub4AdminTest < Minitest::Test
  ADMIN = Pub4Admin

  def test_service_action_maps_to_fixed_argv
    assert_equal ["/usr/sbin/rcctl", "restart", "brgen"],
                 ADMIN.command_for(%w[service restart brgen])
    assert_equal ["/usr/sbin/rcctl", "check", "master"],
                 ADMIN.command_for(%w[service check master])
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

  def test_ci_lock_is_a_fixed_broker_verb
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    assert_includes source, 'return ensure_ci_lock if args == ["ci-lock"]'
    assert_includes source, 'path = File.join(STAMP_DIR, "ci.lock")'
    assert_includes source, 'raise "#{path} is not a regular file" unless lock.file? && !lock.symlink?'
  end

  def test_ensure_secret_is_an_atomic_fixed_app_operation
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    assert_includes source, 'args[0] == "ensure-secret" && APPS.include?(args[1])'
    assert_includes source, "def ensure_app_secret(app)"
    assert_includes source, "File.lstat(path)"
    assert_includes source, "SecureRandom.hex(64)"
    assert_includes source, "File::CREAT | File::EXCL"
    assert_includes source, "File.rename(temporary, target)"
    assert_includes source, "File.chmod(0o640, temporary)"
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

  def test_rails_task_accepts_only_closed_app_task_arguments
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))
    assert_includes source, 'args[0] == "rails-task" && RAILS_TASK_APPS.include?(args[1])'
    assert_includes source, 'args[0] == "ensure-secret" && APPS.include?(args[1])'
    assert_includes source, "RAILS_TASK_APPS = %w[master brgen amber bsdports].freeze"
    assert_includes helper, "master|brgen|amber|bsdports"
    assert_includes helper, "bundle-install|bundle-check|db-prepare|db-seed|assets-precompile|ci"
    assert_includes helper, "case \"$database\" in cache|queue|cable)"
    assert_includes helper, "SECRET_KEY_BASE=$secret"
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
    assert_includes helper, 'GIT_CONFIG_GLOBAL="/dev/null"'
  end

  def test_production_bundle_uses_the_fixed_rails_task
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/rails-task.ksh", __dir__))

    assert_includes source, 'args[0] == "rails-task" && RAILS_APPS.include?(args[1])'
    assert_includes source, "run_rails_task(args[1], args[2])"
    assert_includes helper, 'bundle-install|bundle-check|db-prepare|db-seed|assets-precompile|ci'
    assert_includes helper, 'BUNDLE_PATH: /home/$app/.bundle/gems'
    assert_includes helper, 'RAILS_ENV=production $bundle install'
    assert_includes helper, 'exec /usr/bin/su -m "$app" -c "$script"'
    refute_includes helper, 'sh -c "$script"'
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

  def test_ci_prepare_is_one_fixed_app_scoped_operation
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))
    helper = File.read(File.expand_path("../usr/local/libexec/ci-prepare.ksh", __dir__))

    assert_includes source, 'args[0] == "ci-prepare" && RAILS_APPS.include?(args[1])'
    assert_includes source, 'trusted_script!(CI_PREPARE)'
    assert_includes source, 'exec("/bin/ksh", CI_PREPARE, args[1])'
    assert_includes helper, 'brgen|amber|bsdports'
    assert_includes helper, 'storage="/home/$app/app/storage"'
    assert_includes helper, '[ ! -L /home/dev ]'
    assert_includes helper, '[ -L "$storage" ]'
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
    assert_includes source, "raise \"unknown helper\" unless [CI_RUN, CI_SYNC].include?(helper)"
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
