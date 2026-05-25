# frozen_string_literal: true

require "minitest/autorun"

class BootSafetySpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  MASTER = File.join(ROOT, "lib", "master.rb")
  CLI = File.join(ROOT, "bin", "cli")

  def test_master_boot_sets_safe_defaults
    source = File.read(MASTER)
    assert_includes source, "def self.apply_process_defaults!"
    assert_includes source, 'ENV["MASTER_SAFE_MODE"] ||= "1"'
    assert_includes source, 'ENV["MASTER_AUTOFIX"] ||= "0"'
    assert_includes source, 'ENV["MASTER_WATCH"] ||= "0"'
    assert_includes source, 'ENV["MASTER_WATCHER"] ||= "0"'
    assert_includes source, 'ENV["MASTER_HEARTBEAT"] ||= "0"'
    assert_includes source, 'ENV["MASTER_DRIFT"] ||= "0"'
  end

  def test_master_boot_installs_process_guards
    source = File.read(MASTER)
    assert_includes source, "def self.install_process_guards!"
    assert_includes source, "Ops::LoopSlot.validate!"
    assert_includes source, "Ops::ProcessBudget.validate_loop_slot!"
    assert_includes source, "Ops::RuntimeLoopGuards.install!"
  end

  def test_cli_installs_guards_before_and_after_boot
    source = File.read(CLI)
    assert_includes source, 'require "ops/runtime_loop_guards"'
    assert_operator source.scan("RuntimeLoopGuards.install!").size, :>=, 2
    assert_operator source.index("RuntimeLoopGuards.install!"), :<, source.index("Master.boot")
  end

  def test_constitution_drift_requires_explicit_env
    source = File.read(MASTER)
    assert_includes source, "def self.start_constitution_drift"
    assert_includes source, 'return unless ENV["MASTER_DRIFT"] == "1"'
    assert_includes source, "start_constitution_drift(container)"
  end
end
