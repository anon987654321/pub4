# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"
require_relative "../../lib/ops/process_budget"
require_relative "../../lib/ops/loop_slot"

class ProcessBudgetSpec < Minitest::Test
  LOOP_ENVS = %w[MASTER_AUTOFIX MASTER_WATCH MASTER_WATCHER MASTER_BACKGROUND MASTER_HEARTBEAT].freeze

  def with_clean_loop_env
    saved = LOOP_ENVS.to_h { |key| [key, ENV[key]] }
    LOOP_ENVS.each { |key| ENV.delete(key) }
    yield
  ensure
    LOOP_ENVS.each { |key| saved[key].nil? ? ENV.delete(key) : ENV[key] = saved[key] }
    Master::Ops::ProcessBudget.reload!
  end

  def test_loop_slot_rejects_multiple_active_loops
    with_clean_loop_env do
      ENV["MASTER_AUTOFIX"] = "1"
      ENV["MASTER_WATCHER"] = "1"
      refute Master::Ops::LoopSlot.valid?
      assert_raises(ArgumentError) { Master::Ops::LoopSlot.validate! }
    end
  end

  def test_process_budget_rejects_multiple_active_slots
    with_clean_loop_env do
      ENV["MASTER_AUTOFIX"] = "1"
      ENV["MASTER_WATCHER"] = "1"
      refute Master::Ops::ProcessBudget.valid_loop_slot?
      assert_raises(ArgumentError) { Master::Ops::ProcessBudget.validate_loop_slot! }
    end
  end

  def test_heartbeat_does_not_consume_loop_slot
    with_clean_loop_env do
      ENV["MASTER_BACKGROUND"] = "1"
      assert Master::Ops::ProcessBudget.valid_loop_slot?
      refute_includes Master::Ops::ProcessBudget.active_loops, "heartbeat"
    end
  end

  def test_compact_status_uses_severity_prefix
    with_clean_loop_env do
      assert_match(/\AOK process:/, Master::Ops::ProcessBudget.compact_status)
    end
  end
end
