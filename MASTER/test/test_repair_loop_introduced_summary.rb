# frozen_string_literal: true

require_relative "test_helper"

# A repair rejected for "new_violations" used to be retried with only that phrase, so the
# model could not know which law it had broken. The retry note now names them.
class TestRepairLoopIntroducedSummary < Minitest::Test
  def loop_for_summary = Master::Fix::RepairLoop.allocate

  def test_names_each_law_the_repair_added_with_its_lines
    before = [{ law: "ABC_SIZE", line: 3 }]
    after = [{ law: "ABC_SIZE", line: 3 }, { law: "ABC_SIZE", line: 12 }, { law: "THIN_CONTROLLER", line: 7 }]

    assert_equal "ABC_SIZE +1 (line 3, 12); THIN_CONTROLLER +1 (line 7)", loop_for_summary.introduced_summary(before, after)
  end

def test_quotes_the_first_offending_line_when_given_the_repaired_source
  source = "a = 1\nuser.profile.name\n"
  after = [{ law: "LAW_OF_DEMETER", line: 2 }]

  assert_equal "LAW_OF_DEMETER +1 (line 2: `user.profile.name`)", loop_for_summary.introduced_summary([], after, source:)
end

  def test_a_law_that_did_not_grow_is_not_named
    before = [{ law: "LONG_LINE", line: 4 }, { law: "LONG_LINE", line: 9 }]
    after = [{ law: "LONG_LINE", line: 4 }, { law: "STRONG_PARAMETERS", line: 2 }]

    assert_equal "STRONG_PARAMETERS +1 (line 2)", loop_for_summary.introduced_summary(before, after)
  end

  def test_at_most_three_laws_are_named
    after = %w[A B C D].map { |law| { law:, line: 1 } }

    assert_equal 3, loop_for_summary.introduced_summary([], after).split("; ").size
  end

# The semantic stream (an LLM) invents law names no registry holds and need not repeat itself between
# two scans of one file, so its findings can be left out of the new-violations count on request.
def test_the_semantic_gate_can_be_limited_to_registered_mechanical_laws
  mechanical = Struct.new(:id).new("ABC_SIZE")
  semantic = Class.new { def id = "semantic"; def set_agent(_agent) = nil }.new
  loop = Master::Fix::RepairLoop.allocate
  scanner = Struct.new(:laws).new([mechanical, semantic])
  loop.instance_variable_set(:@scanner, scanner)
  rows = [{ law: "ABC_SIZE", line: 3 }, { law: "RATE_LIMITING_MISSING", line: 25 }]
  previous = ENV.delete("MASTER_FIX_SEMANTIC_GATE")

  assert_equal rows, loop.gate_findings(rows)

  ENV["MASTER_FIX_SEMANTIC_GATE"] = "0"

  assert_equal [{ law: "ABC_SIZE", line: 3 }], loop.gate_findings(rows)
ensure
  previous ? ENV["MASTER_FIX_SEMANTIC_GATE"] = previous : ENV.delete("MASTER_FIX_SEMANTIC_GATE")
end
end
