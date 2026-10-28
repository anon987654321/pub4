# frozen_string_literal: true

require_relative "test_helper"

# /fix --plan takes the read-only check baseline and prints the worklist, blockers first, writing nothing.
class TestFixPlan < Minitest::Test
  Focus = Master::Fix::CheckFocus

  def setup
    @deep_trace = ENV["MASTER_FIX_DEEP_TRACE"]
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"
  end

  def teardown
    @deep_trace ? ENV["MASTER_FIX_DEEP_TRACE"] = @deep_trace : ENV.delete("MASTER_FIX_DEEP_TRACE")
    Focus.restore_plan(false)
  end

  def test_plan_is_a_dry_run_that_holds_for_its_own_dispatch
    seen = nil
    # The real baseline runs every check stage; this test asserts what the flag selects.
    ::Operator::CheckChain.stub(:baseline, {}) do
      recorder = ->(_deps, **kwargs) { seen = [Focus.plan?, kwargs[:apply]] }

      Master::CLI::CommandRegistry.stub(:run_pass, recorder) do
        Master::CLI::CommandRegistry.dispatch_fix(
          scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil,
          ctx: { args: "MASTER --plan --only critique" }
        )
      end
    end

    assert_equal [true, false], seen
    refute Focus.plan?
  end

  # Prints a preview the way the pass does.
  class Previewing < Master::CLI::Pipeline::Pass
    def initialize = nil
    def show(value) = preview_lines(value)
  end

  def test_the_preview_names_the_blockers_first
    lines = Previewing.new.show({ total: 3, files: {}, blockers: %w[lib/fix/c.rb] }).lines

    assert_equal "preview blockers: 1 file(s) named by a red check, first: lib/fix/c.rb\n", lines.first
  end

  def test_the_preview_does_not_hide_semantic_reads_left_pending_by_its_budget
    lines = Previewing.new.show({
      total: 5, files: {},
      gaps: { semantic_pending: { "a.rb" => "budget", "b.rb" => "budget" } }
    })

    assert_includes lines, "preview semantic: PENDING 2 file(s); model-backed coverage incomplete"
  end
end
