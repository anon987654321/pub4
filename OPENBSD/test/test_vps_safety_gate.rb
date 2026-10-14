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
      FileUtils.mkdir_p(File.join(openbsd, "usr", "local", "sbin"))
      FileUtils.cp(File.join(ROOT, "usr", "local", "sbin", "pub4-admin"),
                   File.join(openbsd, "usr", "local", "sbin", "pub4-admin"))
      FileUtils.mkdir_p(File.join(openbsd, "usr", "local", "libexec"))
      FileUtils.cp(File.join(ROOT, "usr", "local", "libexec", "ci-prepare.ksh"),
                   File.join(openbsd, "usr", "local", "libexec", "ci-prepare.ksh"))
      FileUtils.cp(File.join(ROOT, "usr", "local", "libexec", "ci-run.ksh"),
                   File.join(openbsd, "usr", "local", "libexec", "ci-run.ksh"))
      FileUtils.cp(File.join(ROOT, "usr", "local", "libexec", "ci-sync.ksh"),
                   File.join(openbsd, "usr", "local", "libexec", "ci-sync.ksh"))
      FileUtils.cp(File.join(ROOT, "usr", "local", "libexec", "rails-task.ksh"),
                   File.join(openbsd, "usr", "local", "libexec", "rails-task.ksh"))
      FileUtils.cp(File.join(ROOT, "OPERATOR.sh"), File.join(openbsd, "OPERATOR.sh"))
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

  def test_broker_sources_must_not_be_symlinks
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "sbin", "pub4-admin")
      File.unlink(path)
      File.symlink("/tmp/pub4-admin", path)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "usr/local/sbin/pub4-admin must not be a symlink"
    end
  end
  def test_operator_install_refuses_symlinked_system_destinations
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "OPERATOR.sh")
      text = File.read(path).sub("refusing symlinked privileged destination file",
                                 "symlinked target check weakened")
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "OPERATOR.sh must refuse symlinked privileged destinations before copying"
    end
  end

  def test_operator_install_preflights_privileged_source_files
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "OPERATOR.sh")
      text = File.read(path).sub('if [[ ! -f $src/$rel || -L $src/$rel ]]; then',
                              'if [[ ! -f $src/$rel ]]; then')
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "OPERATOR.sh must preflight privileged sources before copying"
    end
  end
  def test_ci_prepare_path_validation_is_required
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "libexec", "ci-prepare.ksh")
      File.write(path, File.read(path).sub('[ ! -L "$app_dir" ]', '[ -d "$app_dir" ]'))
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "ci-prepare helper must check app-owned real path components before chmod"
    end
  end

  def test_ci_runner_must_keep_its_timeout_bounded
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "libexec", "ci-run.ksh")
      File.write(path, File.read(path).sub('[ "$timeout" -le 7200 ]', '[ "$timeout" -le 7201 ]'))
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "ci-run helper must use fixed app paths, bounded timeout and sanitized Ruby environment"
    end
  end

  def test_operator_install_refuses_symlinked_broker_helpers
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "OPERATOR.sh")
      text = File.read(path).sub('if [[ -L $f ]]; then', 'if [[ -L $unused ]]; then')
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "OPERATOR.sh must reject symlinked privileged entrypoints"
    end
  end

  def test_relayd_broker_must_not_modify_root_routing_policy
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "sbin", "pub4-admin")
      text = File.read(path).sub(
        '    puts "relayd0: verified root-approved route #{domain} -> #{app}:#{requested_port}"',
        "    File.rename(temporary, RELAYD_CONFIG)"
      )
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "relayd broker must be verification-only and reject unapproved Host routes"
    end
  end
  def test_broker_must_keep_legacy_retirement_fixed
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "sbin", "pub4-admin")
      text = File.read(path).sub('return nil unless RAILS_APPS.include?(app)', 'return nil unless APPS.include?(app)')
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "pub4-admin must expose only fixed app-scoped CI helper verbs"
    end
  end

  def test_broker_must_keep_ci_spawn_fixed_and_supervised
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "sbin", "pub4-admin")
      text = File.read(path).sub("Process.spawn(", 'Process.spawn("sh", "-c", "unsafe", ')
      File.write(path, text)
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "pub4-admin must not evaluate shell command strings or widen its CI spawn"
    end
  end

  def test_broker_must_keep_ci_lock_fixed_and_symlink_safe
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "usr", "local", "sbin", "pub4-admin")
      File.write(path, File.read(path).sub('return ensure_ci_lock if args == ["ci-lock"]', "return ensure_ci_lock if args.first == \"ci-lock\""))
      out, status = run_gate(dir)

      refute status.success?
      assert_includes out, "pub4-admin CI lock must use one fixed path and refuse symlinks"
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

  def test_fast_deploy_ack_is_allowlisted
    with_fixture do |dir, doas|
      text = File.read(doas).sub(" I_UNDERSTAND_FAST_DEPLOY RUN_PRODUCTION_SEEDS", " RUN_PRODUCTION_SEEDS")
      File.write(doas, text)
      out, status = run_gate(dir)
      refute status.success?
      assert_includes out, "setenv-allowlist I_UNDERSTAND_FAST_DEPLOY"
    end
  end

  def test_master_scan_skip_requires_explicit_fast_deploy_ack
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "OPERATOR.sh")
      text = File.read(path).sub(
        '[[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]',
        '[[ -n ${SKIP_MASTER_SCAN:-} ]]'
      )
      File.write(path, text)
      out, status = run_gate(dir)
      refute status.success?
      assert_includes out, "MASTER scan bypass requires SKIP_MASTER_SCAN=1 plus I_UNDERSTAND_FAST_DEPLOY=1"
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
