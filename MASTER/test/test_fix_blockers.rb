# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/gate_focus"

# /fix --blockers repairs only the files a red gate names, and reads none of them semantically.
class TestFixBlockers < Minitest::Test
  Focus = Master::Fix::GateFocus

  # The execution trace needs live collaborators; this file asserts what the flag selects.
  def setup
    @deep_trace = ENV["MASTER_FIX_DEEP_TRACE"]
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"
    Focus.reset!
  end

  def teardown
    @deep_trace ? ENV["MASTER_FIX_DEEP_TRACE"] = @deep_trace : ENV.delete("MASTER_FIX_DEEP_TRACE")
    Focus.reset!
    Focus.restore_blockers(false)
  end

  def test_the_flag_holds_for_its_own_dispatch_and_not_the_next
    seen = nil
    Master::CLI::CommandRegistry.stub(:run_pass, ->(_deps, **kwargs) { seen = [Focus.blockers?, kwargs[:target]] }) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil,
        ctx: { args: "RAILS --blockers --only critique" }
      )
    end

    assert_equal [true, "RAILS"], seen
    refute Focus.blockers?, "the next command repairs as usual"
  end

  def test_the_corpus_is_only_the_named_files
    Focus.note(["lib/fix/c.rb:3:in 'z'"])

    assert_equal %w[/r/lib/fix/c.rb], Focus.only(%w[/r/lib/a.rb /r/lib/fix/c.rb])
  end

  # Exposes the semantic decision for a file with a finding.
  class Processor < Master::Fix::Scan::FileProcessor
    def due? = semantic_due?([{ law: "CQS" }], "lib/a.rb")
  end

  def test_blocker_files_are_not_read_semantically
    Focus.blockers!

    refute Processor.new.due?
  end
end
