# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class BootSafetySpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # apply_process_defaults!/install_process_guards! live in these modules,
  # which master.rb extends as MasterRuntime and MasterBoot.
  MASTER_RUNTIME = File.join(ROOT, "lib", "boot", "runtime.rb")
  MASTER_BOOT = File.join(ROOT, "lib", "boot", "master_boot.rb")
  CLI = File.join(ROOT, "bin", "master")

  # Called, not grepped: running it in a clean environment and reading ENV back
  # proves the defaults land, and proves the opt-out and the "||=" semantics
  # with them.
  def test_master_boot_sets_safe_defaults
    with_clean_process_env do
      Master.apply_process_defaults!

      Master::MasterRuntime::PROCESS_DEFAULTS.each do |key, value|
        assert_equal value, ENV.fetch(key, nil), "#{key} was not defaulted"
      end
    end
  end

  def test_an_operator_set_value_survives_the_defaults
    with_clean_process_env do
      ENV["MASTER_AUTOFIX"] = "1"
      Master.apply_process_defaults!

      assert_equal "1", ENV.fetch("MASTER_AUTOFIX"),
                   "the defaults overwrote a value the operator set"
    end
  end

  def test_the_unsafe_opt_out_applies_nothing
    with_clean_process_env do
      ENV["MASTER_UNSAFE_PROCESS_DEFAULTS"] = "1"
      Master.apply_process_defaults!

      assert_nil ENV.fetch("MASTER_SAFE_MODE", nil),
                 "MASTER_UNSAFE_PROCESS_DEFAULTS=1 still applied the safe defaults"
    end
  end

  # Every key the defaults touch, plus the opt-out and the loop var
  # apply_master_loop! reads, cleared and restored around the block.
  def with_clean_process_env
    keys = Master::MasterRuntime::PROCESS_DEFAULTS.keys +
           %w[MASTER_UNSAFE_PROCESS_DEFAULTS MASTER_LOOP]
    saved = keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    keys.each { |key| ENV.delete(key) }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_master_boot_installs_process_guards
    source = File.read(MASTER_RUNTIME)
    assert_includes source, "def install_process_guards!"
    assert_includes source, "Ops::LoopSlot.validate!"
    assert_includes source, "Ops::ProcessBudget.validate_loop_slot!"
    assert_includes source, "Ops::RuntimeLoopGuards.install!"
  end

  # Guards install twice: once indirectly via prepare_runtime! (called before
  # any Master.boot call) and once explicitly right after boot returns.
  def test_cli_installs_guards_before_and_after_boot
    source = File.read(CLI)
    assert_includes source, "RuntimeLoopGuards.install!"
    assert_operator source.index("Master.boot"), :<, source.index("RuntimeLoopGuards.install!")
    boot = File.read(MASTER_BOOT)
    # Master.boot runs boot_container inside Dmesg.booting; the runtime is prepared first thing there.
    assert_includes boot[boot.index("def boot(root"), 120], "boot_container(root:)"
    assert_includes boot[boot.index("def boot_container(root"), 80], "prepare_runtime!",
                    "Master.boot prepares the runtime before it boots"

    runtime_source = File.read(MASTER_RUNTIME)
    assert_includes runtime_source, "install_process_guards!"
    assert_operator runtime_source.index("apply_process_defaults!"), :<,
      runtime_source.index("install_process_guards!", runtime_source.index("def prepare_runtime!"))
  end

  def test_stale_process_lock_can_reclaim_a_dilla_player_only
    source = File.read(File.expand_path("../lib/ops.rb", __dir__))
    assert_includes source, "reclaim_detached_media_holders"
    assert_includes source, "STUDIO/dilla"
    assert_includes source, 'ps", "-ax", "-o", "pid=,ppid=,pgid=,command="'
    refute_includes source, "return false if pid.positive? && process_alive?(pid)"
    assert_includes source, "0.25"
  end

  def test_constitution_drift_requires_explicit_env
    source = File.read(MASTER_BOOT)
    assert_includes source, "def start_constitution_drift"
    assert_includes source, 'return unless ENV["MASTER_DRIFT"] == "1"'
    assert_includes source, "start_constitution_drift(container)"
  end
end
