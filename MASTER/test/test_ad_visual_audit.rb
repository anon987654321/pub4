# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/visual/ad_audit"

class TestAdVisualAudit < Minitest::Test
  Audit = Master::Visual::AdAudit

  def setup
    @contract = Audit.contract
    @rendered = {
      contrast_pairs: [{ ratio: 7.0, minimum: 4.5 }],
      disclosure: { distance_px: 8, contrast_ratio: 7.0, font_size_px: 14 },
      safe_zone: {
        rect: { "x" => 0, "y" => 0, "width" => 320, "height" => 250 },
        bounds: {
          "headline" => { "x" => 10, "y" => 10, "width" => 180, "height" => 30 },
          "logo" => { "x" => 250, "y" => 10, "width" => 40, "height" => 20 },
          "cta" => { "x" => 200, "y" => 200, "width" => 100, "height" => 30 },
        },
      },
      integrity: { assets_loaded: true, transfer_bytes: 100_000, cumulative_layout_shift: 0.01, rendered: true },
    }
    @html = '<aside class="ad-organ"><span class="ad-organ-disclosure">Sponsored</span><img src="x.png" alt="Blue jacket"></aside>'
    @css = ".ad-organ { color: var(--ad-organ-on-surface); padding: var(--ad-organ-spacing-md); }"
  end

  def test_complete_audit_passes_only_with_measured_render_evidence
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    assert report[:passed], report[:checks].reject { |check| check[:pass] }.inspect
    assert_equal Audit.token_version(@contract), report[:token_version]
    assert Audit.require_pass!(report, current_contract: @contract, placement: "display-320x250")
  end

  def test_audit_receipt_binds_policy_detector_and_survives_json_round_trip
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    provenance = report.fetch(:provenance)

    assert_equal Audit::REPORT_SCHEMA_VERSION, provenance.fetch(:schema_version)
    assert_match(/\\A[0-9a-f]{64}\\z/, provenance.fetch(:policy_sha256))
    assert_match(/\\A[0-9a-f]{64}\\z/, provenance.fetch(:detector_sha256))
    assert_equal "caller_supplied", provenance.dig(:measurement, :mode)
    assert_match(/\\A[0-9a-f]{64}\\z/, report.fetch(:evidence_sha256))
    assert Audit.verify_evidence!(JSON.parse(JSON.generate(report)))
  end

  def test_receipt_rejects_post_audit_mutation
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    report.fetch(:checks).first.fetch(:reasons) << "changed after assessment"

    assert_raises(Audit::VisualAuditRejected) { Audit.verify_evidence!(report) }
  end

  def test_missing_receipt_cannot_pass_the_renderer_gate
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    report.delete(:evidence_sha256)

    assert_raises(Audit::VisualAuditRejected) do
      Audit.require_pass!(report, current_contract: @contract, placement: "display-320x250")
    end
  end

  def test_receipt_covers_measurements_added_after_the_audit
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    report[:measurements] = { "asset_count" => 1 }
    Audit.seal!(report, rendered: @rendered)
    assert Audit.verify_evidence!(report)

    report[:measurements]["asset_count"] = 2
    assert_raises(Audit::VisualAuditRejected) { Audit.verify_evidence!(report) }
  end

  def test_missing_render_evidence_fails_closed
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", token_contract: @contract)
    refute report[:passed]
    assert_raises(Audit::VisualAuditRejected) do
      Audit.require_pass!(report, current_contract: @contract, placement: "display-320x250")
    end
  end

  def test_stale_token_contract_cannot_reuse_audit
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    changed = Marshal.load(Marshal.dump(@contract))
    changed["version"] += 1
    assert_raises(Audit::VisualAuditRejected) do
      Audit.require_pass!(report, current_contract: changed, placement: "display-320x250")
    end
  end

  def test_wrong_placement_cannot_reuse_audit
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered: @rendered, token_contract: @contract)
    assert_raises(Audit::VisualAuditRejected) do
      Audit.require_pass!(report, current_contract: @contract, placement: "social-1080x1080")
    end
  end

  def test_hardcoded_ad_colour_is_rejected
    check = Audit.identity_tokens(html: @html, css: ".ad-organ { color: #fff; }", token_contract: @contract)
    refute check[:pass]
    assert_match(/hardcoded colour/, check[:reasons].join)
  end

  def test_missing_alt_text_is_rejected
    check = Audit.alt_text(html: '<div class="ad-organ"><img src="x.png" alt=""></div>')
    refute check[:pass]
  end

  def test_missing_disclosure_is_rejected
    check = Audit.disclosure(html: '<aside class="ad-organ"><img alt="Product"></aside>', rendered: @rendered, token_contract: @contract)
    refute check[:pass]
  end

  def test_safe_zone_overflow_is_rejected
    evidence = Marshal.load(Marshal.dump(@rendered))
    evidence[:safe_zone][:bounds]["cta"]["x"] = 290
    check = Audit.safe_zone(placement: "display-320x250", rendered: evidence)
    refute check[:pass]
    assert_match(/cta extends outside/, check[:reasons].join)
  end

  def test_broken_asset_and_layout_shift_are_rejected
    evidence = Marshal.load(Marshal.dump(@rendered))
    evidence[:integrity][:assets_loaded] = false
    evidence[:integrity][:cumulative_layout_shift] = 0.5
    check = Audit.render_integrity(rendered: evidence, token_contract: @contract)
    refute check[:pass]
    assert_equal 2, check[:reasons].length
  end

  def test_contrast_calculation_matches_wcag_black_white
    assert_in_delta 21.0, Audit.contrast_ratio("#000000", "#FFFFFF"), 0.01
  end
end
