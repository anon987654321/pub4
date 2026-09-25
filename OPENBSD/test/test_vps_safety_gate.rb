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
