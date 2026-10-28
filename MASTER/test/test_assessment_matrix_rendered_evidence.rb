# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop/pass_runner/assessment_matrix"

class TestAssessmentMatrixRenderedEvidence < Minitest::Test
  Matrix = Master::Fix::FixLoop::PassRunner::AssessmentMatrix
  LAW_ID = Master::Fix::VisualPass::LAW_ID

  def matrix(receipts = {})
    Object.new.extend(Matrix).tap do |instance|
      instance.instance_variable_set(:@assessment_surface_receipts, receipts)
    end
  end

  def visual_result(findings: [], include_findings: true, error: false)
    payload = {}
    payload[:findings] = findings if include_findings
    Object.new.tap do |result|
      result.define_singleton_method(:err?) { error }
      result.define_singleton_method(:message) { error ? "browser unavailable" : "" }
      result.define_singleton_method(:value!) { payload }
    end
  end

  def rendered_receipt(status: "assessed_clean", surfaces: nil, reason: nil)
    evidence = {}
    evidence["surfaces"] = surfaces unless surfaces.nil?
    {
      "status" => status,
      "reason" => reason,
      "evidence_sha256" => "c" * 64,
      "counts" => { "surfaces" => surfaces&.size || 0 },
      "evidence" => evidence,
    }.compact
  end

  def capture
    {
      "rendered_status" => "assessed_clean",
      "screenshot_sha256" => "a" * 64,
      "geometry_sha256" => "b" * 64,
      "element_count" => 12,
    }
  end

  def assess(instance, visual:)
    instance.send(
      :assessment_cell_result,
      law_id: LAW_ID,
      info: {
        id: LAW_ID,
        source_kind: :canonical,
        streams: [:visual],
        surfaces: [:rendered_ui],
        unmeasurable_reason: nil,
      },
      stream: :visual,
      surface: :rendered_ui,
      pass: 1,
      observation: {},
      signatures_stable: true,
      semantic_gaps: {},
      pending: [],
      evidence: ["source_sha256=" + ("d" * 64)],
      visual:,
      opportunities: nil,
    )
  end

  def test_missing_rendered_receipt_cannot_mark_visual_law_clean
    result = assess(matrix, visual: visual_result)

    assert_equal :inconclusive, result.fetch(:status)
    assert_match(/receipt is missing/, result.fetch(:reason))
  end

  def test_invalid_geometry_receipt_cannot_mark_visual_law_clean
    invalid_geometry = capture.merge("geometry_sha256" => "missing")
    receipts = { "rendered_ui" => rendered_receipt(surfaces: [invalid_geometry]) }
    result = assess(matrix(receipts), visual: visual_result)

    assert_equal :inconclusive, result.fetch(:status)
    assert_match(/screenshot\/geometry evidence/, result.fetch(:reason))
  end

  def test_successful_rendered_receipt_requires_a_law_findings_collection
    receipts = { "rendered_ui" => rendered_receipt(surfaces: [capture]) }
    result = assess(matrix(receipts), visual: visual_result(include_findings: false))

    assert_equal :inconclusive, result.fetch(:status)
    assert_match(/findings collection/, result.fetch(:reason))
  end

  def test_visual_findings_are_attributed_only_to_the_matching_law
    receipts = { "rendered_ui" => rendered_receipt(surfaces: [capture]) }
    findings = [
      { law: "OTHER_LAW", message: "not this law" },
      { law: LAW_ID, message: "misaligned rendered control" },
    ]
    result = assess(matrix(receipts), visual: visual_result(findings:))

    assert_equal :violation_found, result.fetch(:status)
    assert_equal [findings.last], result.fetch(:findings)
  end

  def test_clean_visual_law_cell_retains_geometry_receipt_digest
    receipts = { "rendered_ui" => rendered_receipt(surfaces: [capture]) }
    result = assess(matrix(receipts), visual: visual_result)

    assert_equal :assessed_clean, result.fetch(:status)
    assert_equal "c" * 64, result.fetch(:evidence).last.fetch("evidence_sha256")
    assert_equal({ "surfaces" => 1 }, result.fetch(:evidence).last.fetch("counts"))
  end
  def cell(instance, spec)
    law_id, stream, surface = spec.values_at(:law_id, :stream, :surface)
    row = { id: law_id, source_kind: :canonical, streams: Master::Fix::FourStreamAssessment::STREAMS,
            surfaces: [surface], unmeasurable_reason: nil, mode: :violation,
            unowned_streams: [:lexical_opportunities], unmeasurable_streams: [] }.merge(spec.fetch(:info, {}))
    instance.send(:assessment_cell_result, law_id:, info: row, stream:, surface:, pass: 1, observation: {},
                  signatures_stable: true, semantic_gaps: {}, pending: [], evidence: ["fixture"],
                  visual: nil, opportunities: nil)
  end

  def test_a_stream_the_mode_does_not_own_is_not_applicable_with_evidence
    result = cell(matrix, law_id: "OTHER_LAW", stream: :lexical_opportunities, surface: :lines)

    assert_equal :not_applicable, result.fetch(:status)
    assert_equal ["law_catalogue OTHER_LAW mode=violation"], result.fetch(:evidence)
  end

  def test_an_owned_stream_without_a_detector_is_unmeasurable_not_clean
    result = cell(matrix, law_id: "OTHER_LAW", stream: :lexical_violations, surface: :lines,
                          info: { unmeasurable_streams: [:lexical_violations] })

    assert_equal [:inconclusive, true], result.values_at(:status, :unmeasurable)
  end

  # The rendered evaluator gives no verdict per Law, so a Law's visual cell on
  # rendered UI is unmeasurable, and on a source surface it does not apply.
  def test_a_laws_visual_cell_is_unmeasurable_on_rendered_ui_and_absent_on_source
    instance = matrix
    instance.instance_variable_set(:@assessment_surface_presence, { rendered_ui: true })

    rendered = cell(instance, law_id: "OTHER_LAW", stream: :visual, surface: :rendered_ui)
    source = cell(instance, law_id: "OTHER_LAW", stream: :visual, surface: :lines)

    assert_equal [:inconclusive, true], rendered.values_at(:status, :unmeasurable)
    assert_equal :not_applicable, source.fetch(:status)
  end
end
