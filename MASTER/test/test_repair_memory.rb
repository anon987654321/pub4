# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# /fix asked the model again, every run, about findings it had declined on
# files that had not changed, and kept sending rules it declined nearly always.
class TestRepairMemory < Minitest::Test
  Memory = Master::Fix::RepairMemory

  def finding(rule) = { rule:, line: 1, message: "m" }

  def test_a_decline_holds_until_the_file_changes
    Dir.mktmpdir do |root|
      path = File.join(root, "a.rb")
      File.write(path, "x = 1\n")
      memory = Memory.new(root:)
      memory.record(path, %w[FEATURE_ENVY], { no_proposal: 1 })

      assert_empty memory.fresh(path, [finding("FEATURE_ENVY")])
      assert_equal 1, memory.fresh(path, [finding("CQS")]).size, "another rule is still asked"

      File.write(path, "x = 2\n")
      assert_equal 1, memory.fresh(path, [finding("FEATURE_ENVY")]).size, "a changed file is asked again"
    end
  end

  def test_a_rule_declined_nearly_always_is_retired
    Dir.mktmpdir do |root|
      memory = Memory.new(root:)
      path = File.join(root, "a.rb")
      File.write(path, "x = 1\n")
      17.times { memory.record(path, %w[NOISY], { no_proposal: 1 }) }
      3.times { memory.record(path, %w[NOISY], { applied: 1 }) }
      15.times { memory.record(path, %w[USEFUL], { no_proposal: 1 }) }
      5.times { memory.record(path, %w[USEFUL], { applied: 1 }) }

      assert memory.retired?("NOISY"), "17 of 20 declined"
      refute memory.retired?("USEFUL"), "15 of 20 is below the line"
    end
  end
end

# The verdict can come from a cheaper model than the repair, past MASTER_MODEL.
class TestVerifierModelOverride < Minitest::Test
  def dispatcher = Master::Review::LLMDispatcher.allocate

  def test_the_override_wins_inside_the_block_only
    previous = ENV["MASTER_MODEL"]
    ENV["MASTER_MODEL"] = "claude-cli:claude-opus-5-5"
    inside = Master::Review::LLMDispatcher::ModelPin.with("claude-cli:claude-sonnet-5") do
      dispatcher.send(:answering_model, "x", nil)
    end

    assert_equal "claude-cli:claude-sonnet-5", inside
    assert_equal "claude-cli:claude-opus-5-5", dispatcher.send(:answering_model, "x", nil)
  ensure
    ENV["MASTER_MODEL"] = previous
  end

  def test_no_override_leaves_the_forced_model
    previous = ENV["MASTER_MODEL"]
    ENV["MASTER_MODEL"] = "claude-cli:claude-opus-5-5"

    assert_equal "claude-cli:claude-opus-5-5",
                 Master::Review::LLMDispatcher::ModelPin.with("") { dispatcher.send(:answering_model, "x", nil) }
  ensure
    ENV["MASTER_MODEL"] = previous
  end
end
