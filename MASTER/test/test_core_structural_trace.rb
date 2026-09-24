# frozen_string_literal: true

require_relative "test_helper"

class TestStructuralTrace < Minitest::Test
  def setup
    @trace = Master::Core::Execution::StructuralTrace.new
  end

  def test_record_and_retrieve
    evidence = Struct.new(:verified?).new(true)
    entry = @trace.record(
      role: :implementer,
      intent: "Fix bug",
      effect: :write,
      observation: "File updated",
      evidence:,
    )

    assert_equal :implementer, entry.role
    assert_equal evidence, @trace.last_evidence_for(:implementer)
  end

  def test_verified_chain
    evidence_ok = Struct.new(:verified?).new(true)
    evidence_fail = Struct.new(:verified?).new(false)

    @trace.record(role: :arch, intent: "G", effect: :p, observation: "O", evidence: evidence_ok)
    assert_equal true, @trace.verified_chain?("G")

    @trace.record(role: :impl, intent: "G", effect: :w, observation: "O", evidence: evidence_fail)
    assert_equal false, @trace.verified_chain?("G")
  end

  def test_clear
    @trace.record(role: :arch, intent: "G", effect: :p, observation: "O", evidence: nil)
    @trace.clear!
    assert_empty @trace.entries
  end
end
