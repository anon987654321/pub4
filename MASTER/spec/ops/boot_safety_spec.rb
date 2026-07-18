# frozen_string_literal: true

require "minitest/autorun"

class BootSafetySpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  # apply_process_defaults!/install_process_guards! moved out of master.rb into
  # these focused modules (extend MasterRuntime / extend MasterBoot in master.rb).
  MASTER_RUNTIME = File.join(ROOT, "lib", "boot", "runtime.rb")
  MASTER_BOOT = File.join(ROOT, "lib", "boot", "master_boot.rb")
  CLI = File.join(ROOT, "bin", "cli")

  def test_master_boot_sets_safe_defaults
    source = File.read(MASTER_RUNTIME)
    assert_includes source, "def apply_process_defaults!"
    assert_includes source, '"MASTER_SAFE_MODE" => "1"'
    assert_includes source, '"MASTER_AUTOFIX" => "0"'
    assert_includes source, '"MASTER_WATCH" => "0"'
    assert_includes source, '"MASTER_WATCHER" => "0"'
    assert_includes source, '"MASTER_HEARTBEAT" => "0"'
    assert_includes source, '"MASTER_DRIFT" => "0"'
  end

  def test_master_boot_installs_process_guards
    source = File.read(MASTER_RUNTIME)
    assert_includes source, "def install_process_guards!"
    assert_includes source, "Ops::LoopSlot.validate!"
    assert_includes source, "Ops::ProcessBudget.validate_loop_slot!"
    assert_includes source, "Ops::RuntimeLoopGuards.install!"
  end

  # Guards install twice: once indirectly via prepare_runtime! (called before
  # any Master.boot call) and once explicitly right after boot returns — not
  # as two literal calls in the same file, which is what this spec used to
  # (too brittle) assert.
  def test_cli_installs_guards_before_and_after_boot
    source = File.read(CLI)
    assert_includes source, "Master.prepare_runtime!"
    assert_includes source, "RuntimeLoopGuards.install!"
    assert_operator source.index("Master.prepare_runtime!"), :<, source.index("Master.boot")
    assert_operator source.index("Master.boot"), :<, source.index("RuntimeLoopGuards.install!")

    runtime_source = File.read(MASTER_RUNTIME)
    assert_includes runtime_source, "install_process_guards!"
    assert_operator runtime_source.index("apply_process_defaults!"), :<,
      runtime_source.index("install_process_guards!", runtime_source.index("def prepare_runtime!"))
  end

  def test_constitution_drift_requires_explicit_env
    source = File.read(MASTER_BOOT)
    assert_includes source, "def start_constitution_drift"
    assert_includes source, 'return unless ENV["MASTER_DRIFT"] == "1"'
    assert_includes source, "start_constitution_drift(container)"
  end
end
