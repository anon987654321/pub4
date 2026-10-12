# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The failure this fuse closes: /fix re-asks the model about the same finding in
# the same unchanged file on every pass, and the answer has not changed. The
# counting stub below is that loop; without ToolBreaker it is asked every time.
class TestToolBreaker < Minitest::Test
  Rule = Struct.new(:id, :severity)
  Breaker = Master::Fix::ToolBreaker

  # A RepairLoop whose model call is a counter that always fails to propose.
  class CountingLoop < Master::Fix::RepairLoop
    attr_reader :asked

    def fix_violation(_violation)
      @asked = @asked.to_i + 1
      :no_proposal
    end
  end

  def setup
    Breaker.reset!
    @dir = Dir.mktmpdir("breaker")
    @path = File.join(@dir, "a.rb")
    File.write(@path, "x = 1\n")
    @violation = { file: @path, law: "TEST_RULE", message: "fix me", severity: :warning }
    @loop = CountingLoop.new(law: Rule.new("TEST_RULE", :warning), agent: Object.new, scanner: Object.new, root: Master::ROOT)
  end

  def teardown
    FileUtils.remove_entry(@dir)
    Breaker.reset!
  end

  def batch = @loop.send(:fix_batch, [@violation])

  def test_the_model_is_asked_three_times_for_an_unchanged_file_and_no_more
    out, = capture_io { 6.times { batch } }

    assert_equal 3, @loop.asked
    assert_equal 1, out.scan("fused on a.rb").size, "one dmesg line, at the moment it fuses"
    assert_equal 1, Breaker.fused_count
    assert_equal({ skip_fused: 1 }, @loop.instance_variable_get(:@batch_breakdown))
  end

  def test_a_changed_file_reopens_the_tuple
    capture_io { 3.times { batch } }
    File.write(@path, "x = 2\n")
    capture_io { batch }

    assert_equal 4, @loop.asked
    assert_equal 0, Breaker.fused_count
  end

  def test_a_different_finding_or_law_is_a_different_tuple
    capture_io { 3.times { batch } }

    assert Breaker.refuse?("TEST_RULE", @violation, Breaker.state_of(@violation))
    refute Breaker.refuse?("TEST_RULE", @violation.merge(message: "another"), Breaker.state_of(@violation))
    refute Breaker.refuse?("OTHER", @violation, Breaker.state_of(@violation))
  end

  def test_outages_and_applied_fixes_do_not_count
    state = Breaker.state_of(@violation)
    5.times { Breaker.record("TEST_RULE", @violation, state, :model_failed) }
    refute Breaker.refuse?("TEST_RULE", @violation, state)

    2.times { Breaker.record("TEST_RULE", @violation, state, :rejected) }
    Breaker.record("TEST_RULE", @violation, state, :applied)
    Breaker.record("TEST_RULE", @violation, state, :rejected)
    refute Breaker.refuse?("TEST_RULE", @violation, state)
  end

  def test_best_of_n_sees_a_fused_tuple
    ENV["MASTER_FIX_BEST_OF"] = "3"
    visual = @violation.merge(law: Master::Fix::BestOfN::LAW_ID, file: File.join(@dir, "a.scss"))
    File.write(visual[:file], ".a{}\n")
    assert Master::Fix::BestOfN.active?(visual, Object.new, tool: "LAW")
    state = Breaker.state_of(visual)
    capture_io { 3.times { Breaker.record("LAW", visual, state, :rejected) } }

    refute Master::Fix::BestOfN.active?(visual, Object.new, tool: "LAW")
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end

  def test_run_budget_reports_fused_tuples_at_the_pass_boundary
    said = []
    budget = Master::Fix::RunBudget.new(root: @dir, max_passes: 3, say: ->(text) { said << text }, poll_seconds: 0).start!
    budget.pass_end(1)
    refute said.any? { |line| line.include?("tuples fused") }

    state = Breaker.state_of(@violation)
    capture_io { 3.times { Breaker.record("TEST_RULE", @violation, state, :rejected) } }
    budget.pass_end(2)
    assert_includes said, "fix0: pass 2 1 tuples fused"
  end
end
