# frozen_string_literal: true

require_relative "test_helper"

class TestEpisodeLedger < Minitest::Test
  def setup
    @intent = "Fix core loop"
    @episode = Master::Core::Execution::Episode::Record.new(id: "test-id", intent: @intent)
    @trace = Master::Core::Execution::StructuralTrace.new
  end

  def test_unified_ledger
    # Simulate a turn
    entry = @trace.record(
      role: :implementer,
      intent: @intent,
      effect: :write,
      observation: "updated file",
      evidence: Struct.new(:verified?).new(true)
    )
    
    @episode.record_trace_entry(entry)
    @episode.finalize(:success)
    
    data = @episode.to_h
    assert_equal "test-id", data[:id]
    assert_equal @intent, data[:intent]
    assert_equal :success, data[:outcome]
    assert_equal 1, data[:trace].length
    assert_equal :implementer, data[:trace].first[:role]
  end
end
