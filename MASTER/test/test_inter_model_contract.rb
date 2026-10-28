# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/master"
require_relative "../lib/review/council/inter_model_contract"

class TestInterModelContract < Minitest::Test
  Contract = Master::Review::Council::InterModelContract

  def setup
    @root = Dir.mktmpdir("inter-model-contract")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def valid_response(overrides = {})
    {
      "position" => "independent",
      "position_reason" => "The supplied artifact was reviewed independently against the named Laws.",
      "position_evidence" => [
        { "location" => "MASTER/lib/example.rb:4", "evidence" => "The supplied source contains the observed call." },
      ],
      "findings" => [
        {
          "severity" => "warning",
          "location" => "MASTER/lib/example.rb:4",
          "evidence" => "The call site sends an unbounded input into the parser.",
          "claim" => "The parser input has no declared size bound.",
          "proposed_repair" => "Reject inputs over the documented maximum before parsing.",
        },
      ],
    }.merge(overrides).to_json
  end

  def test_loads_the_versioned_contract
    config = Contract.config
    assert_equal 1, config.fetch("schema")
    assert_equal "1.0.0", config.fetch("version")
    assert_includes config.dig("response", "required"), "position_evidence"
  end

  def test_validates_and_normalizes_a_structured_response
    result = Contract.validate_response(valid_response)
    assert result.fetch("ok"), result.fetch("errors").inspect
    assert_includes result.fetch("feedback"), "WARNING MASTER/lib/example.rb:4"
    assert_equal "independent", result.dig("data", "position")
  end

  def test_rejects_free_prose_and_malformed_json
    result = Contract.validate_response("This looks mostly good.")
    refute result.fetch("ok")
    assert_includes result.fetch("errors"), "invalid_json"
  end

  def test_rejects_missing_fields_and_unknown_fields
    missing = Contract.validate_response({ "position" => "independent" }.to_json)
    refute missing.fetch("ok")
    assert missing.fetch("errors").any? { |error| error.start_with?("missing_response_field:") }

    extra = JSON.parse(valid_response).merge("friendly_summary" => "Looks good").to_json
    result = Contract.validate_response(extra)
    refute result.fetch("ok")
    assert_includes result.fetch("errors"), "unexpected_response_field"
  end

  def test_position_must_be_independent_without_prior_findings
    data = JSON.parse(valid_response).merge("position" => "concur").to_json
    result = Contract.validate_response(data)

    refute result.fetch("ok")
    assert_includes result.fetch("errors"), "position_must_be_independent_without_prior_findings"
  end

  def test_concurrence_requires_prior_findings_and_evidence
    data = JSON.parse(valid_response).merge(
      "position" => "concur",
      "position_evidence" => [],
    ).to_json
    result = Contract.validate_response(data, prior_findings: [{ "claim" => "a prior claim" }])
    refute result.fetch("ok")
    assert_includes result.fetch("errors"), "position_evidence_missing"
  end

  def test_no_actionable_issue_must_be_a_single_info_finding
    no_issue = {
      "severity" => "info", "location" => "general",
      "evidence" => "The supplied artifact was checked against the assigned charge.",
      "claim" => "no actionable issue under charge", "proposed_repair" => "none"
    }
    valid = JSON.parse(valid_response).merge("findings" => [no_issue]).to_json
    assert Contract.validate_response(valid).fetch("ok")

    invalid = JSON.parse(valid_response).merge("findings" => [no_issue, JSON.parse(valid_response)["findings"].first]).to_json
    result = Contract.validate_response(invalid)
    refute result.fetch("ok")
    assert_includes result.fetch("errors"), "no_actionable_must_be_single_info_finding"
  end

  def test_outbound_envelope_uses_a_content_hash_and_required_fields
    envelope = Contract.outbound_message(
      role: "critic", task: "Review a bounded artifact.",
      success_criteria: "Return schema-valid findings.",
      constraints: %w[ROBUSTNESS INTER_MODEL_CONTRACT],
      artifact: "puts :ok\n"
    )
    assert_equal %w[role authority_boundary task success_criteria constraints artifact_ref],
                 envelope.keys
    assert_match(/\Asha256:[0-9a-f]{64}\z/, envelope.fetch("artifact_ref"))
  end

  def test_measurement_ledger_stores_outcomes_not_raw_model_text
    Contract.record_turn(
      root: @root, role: "critic", model: "test-model", outbound_schema_valid: true,
      first_response_valid: true, accepted: true, repair_attempted: false,
      response_hashes: ["a" * 64]
    )
    Contract.record_turn(
      root: @root, role: "critic", model: "test-model", outbound_schema_valid: true,
      first_response_valid: false, accepted: true, repair_attempted: true,
      response_hashes: ["b" * 64, "c" * 64]
    )

    report = Contract.measure(root: @root)
    assert_equal "measured", report.fetch("status")
    assert_equal 2, report.fetch("turns")
    assert_equal 0.5, report.fetch("handoff_cleanliness_rate")
    assert_equal 1.0, report.fetch("schema_compliance_rate")
    assert_equal 0.5, report.fetch("first_response_schema_compliance_rate")
    raw = File.read(File.join(@root, Contract::LEDGER_RELATIVE_PATH))
    refute_includes raw, "The parser input has no declared size bound."
  end

  def test_wrap_prompt_includes_a_structured_request_and_response_contract
    prompt = Contract.wrap_prompt(
      "Review the source.",
      role: "critic", task: "Find evidence-backed problems.",
      success_criteria: "Schema-valid response.",
      constraints: ["INTER_MODEL_CONTRACT"], artifact: "source bytes"
    )
    assert_includes prompt, "REQUEST ENVELOPE (JSON)"
    assert_includes prompt, "sha256:"
    assert_includes prompt, "RESPONSE CONTRACT (JSON ONLY"
  end
end
