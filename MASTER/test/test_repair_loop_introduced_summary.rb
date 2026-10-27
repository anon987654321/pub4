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
  # two scans of one file, so by default its findings are read loosely: left out of the count, logged only.
  def test_the_semantic_check_is_loose_by_default_and_strict_on_request
    mechanical = Struct.new(:id).new("ABC_SIZE")
    semantic = Class.new { def id = "semantic"; def set_agent(_agent) = nil }.new
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@scanner, Struct.new(:laws).new([mechanical, semantic]))
    rows = [{ law: "ABC_SIZE", line: 3 }, { law: "RATE_LIMITING_MISSING", line: 25 }]
    previous = ENV.delete("MASTER_FIX_SEMANTIC_CHECK")

    assert_equal [{ law: "ABC_SIZE", line: 3 }], loop.check_findings(rows)

    ENV["MASTER_FIX_SEMANTIC_CHECK"] = "strict"

    assert_equal rows, loop.check_findings(rows)
  ensure
    previous ? ENV["MASTER_FIX_SEMANTIC_CHECK"] = previous : ENV.delete("MASTER_FIX_SEMANTIC_CHECK")
  end

  # A model's reading names its findings after registered laws too: NO_CHANGELOG_COMMENT and
  # WHY_NOT_WHAT on comments a repair never touched refused it as new violations.
  def test_a_model_read_named_after_a_registered_law_is_not_counted
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@scanner, Struct.new(:laws).new([Struct.new(:id).new("ABC_SIZE")]))
    rows = [{ law: "ABC_SIZE", line: 3 }, { law: "ABC_SIZE", line: 9, stream: :semantic }]

    assert_equal [{ law: "ABC_SIZE", line: 3 }], loop.check_findings(rows)
  end

  def test_what_the_semantic_stream_added_is_logged_not_gated
    mechanical = Struct.new(:id).new("ABC_SIZE")
    semantic = Class.new { def id = "semantic"; def set_agent(_agent) = nil }.new
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@scanner, Struct.new(:laws).new([mechanical, semantic]))
    said = []

    Master::Trace::Dmesg.stub(:status, ->(unit, text) { said << [unit, text] }) do
      loop.note_semantic_drift("/x/home_controller.rb", [{ law: "ABC_SIZE" }], [{ law: "ABC_SIZE" }, { law: "RATE_LIMITING_MISSING" }])
    end

    assert_equal [["fix0", "semantic findings noted, not gated: home_controller.rb RATE_LIMITING_MISSING +1"]], said
  end

  def test_scan_agreement_separates_mechanical_from_semantic_findings
    mechanical = Struct.new(:id).new("ABC_SIZE")
    semantic = Class.new { def id = "semantic"; def set_agent(_agent) = nil }.new
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@scanner, Struct.new(:laws).new([mechanical, semantic]))
    first = [{ law: "ABC_SIZE", line: 1 }, { law: "RATE_LIMITING_MISSING", line: 9 }]
    second = [{ law: "ABC_SIZE", line: 1 }, { law: "ONE_SOURCE_LLM", line: 3 }, { law: "ONE_SOURCE_LLM", line: 4 }]

    line = loop.scan_agreement_line("f.rb", first, second)

    assert_equal "scan agreement f.rb: mechanical 1 vs 1 same; semantic 1 vs 2 (second minus first: RATE_LIMITING_MISSING -1, ONE_SOURCE_LLM +2)", line
  end
end
