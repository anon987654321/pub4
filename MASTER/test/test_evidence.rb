# frozen_string_literal: true

require_relative "test_helper"

class TestEvidence < Minitest::Test
  def fixture
    {
      "schema" => 1,
      "sources" => {
        "test_pass" => { "trust" => 0.95 },
        "scan_clean" => { "trust" => 0.80 },
        "user_assertion" => { "trust" => 0.40 },
      },
      "required_for" => %w[modification merge],
      "combine" => { "min_total_trust" => 0.75, "require_at_least_one_strong" => true },
    }
  end

  def evidence = Master::Ground::Evidence.new(fixture, root: Dir.pwd)

  def test_required_actions
    assert evidence.required?("modification")
    refute evidence.required?("idle")
  end

  def test_required_action_rejects_missing_sources
    result = evidence.verify(action: "modification", sources: [])
    assert result.err?
    assert_equal :validation, result.category
  end

  def test_verified_strong_source_passes
    result = evidence.verify(action: "modification", sources: [{ type: "test_pass", exit_code: 0 }])
    assert result.ok?
    assert_in_delta 0.95, result.value![:trust], 0.001
  end

  def test_claim_without_verification_artifact_fails
    result = evidence.verify(action: "modification", sources: [{ type: "test_pass" }])
    assert result.err?
    assert_match(/no source verified/, result.message)
  end

  def test_weak_source_fails_threshold
    result = evidence.verify(action: "modification", sources: [{ type: "user_assertion", confirmed: true }])
    assert result.err?
    assert_match(/trust .* < 0.75/, result.message)
  end

  def test_duplicate_sources_do_not_inflate_trust
    source = { type: "user_assertion", confirmed: true }
    result = evidence.verify(action: "modification", sources: [source, source.dup, source.dup])
    assert result.err?
    assert_match(/trust 0.4 < 0.75/, result.message)
  end

  def test_unknown_source_has_zero_trust
    assert_equal 0.0, evidence.trust_for("imaginary")
  end
end
