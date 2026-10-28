# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/visual/ad_audit"
require_relative "../tools/visual/browserless_measurements"

class TestBrowserlessVisualMeasurements < Minitest::Test
  Audit = Master::Visual::AdAudit
  Measure = Master::Visual::BrowserlessMeasurements

  def setup
    @contract = Audit.contract
    @html = <<~HTML
      <!doctype html>
      <html><body>
        <aside class="ad-organ">
          <h1 class="ad-organ-headline">Strong offer</h1>
          <img class="ad-organ-logo" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" alt="Brand logo" width="40" height="20">
          <span class="ad-organ-disclosure">Sponsored</span>
          <a class="ad-organ-cta">Shop now</a>
        </aside>
      </body></html>
    HTML
    @css = <<~CSS
      html, body { margin: 0; padding: 0; }
    .ad-organ { position: relative; width: 320px; height: 250px; background-color: var(--ad-organ-surface); color: var(--ad-organ-on-surface); }
      .ad-organ-headline { margin: 0; position: absolute; left: 16px; top: 16px; width: 180px; height: 40px; font-size: 18px; line-height: 1.2; color: var(--ad-organ-on-surface); }
      .ad-organ-logo { position: absolute; left: 260px; top: 12px; width: 40px; height: 20px; }
      .ad-organ-disclosure { display: inline-block; position: absolute; left: 16px; top: 60px; width: 86px; height: 24px; font-size: 14px; line-height: 1.2; color: var(--ad-organ-disclosure-foreground); background-color: var(--ad-organ-disclosure-background); }
      .ad-organ-cta { display: block; position: absolute; left: 200px; top: 200px; width: 100px; height: 32px; font-size: 14px; line-height: 1.2; color: var(--ad-organ-on-surface); background-color: var(--ad-organ-surface); }
    CSS
  end

  def measure(html: @html, css: @css, placement: "display-320x250", **options)
    Measure.measure(html:, css:, placement:, token_contract: @contract, asset_root: Dir.pwd, **options)
  end

  def test_explicit_geometry_and_text_fit_are_measured_without_a_browser
    measured = measure
    evidence = measured.fetch(:rendered)
    assert_equal "browserless_static", evidence.fetch("measurement_mode")
    assert_equal({ "width" => 320, "height" => 250 }, evidence.fetch("viewport"))
    assert_equal "high", evidence.dig("safe_zone", "geometry_confidence")
    assert_equal 16.0, evidence.dig("safe_zone", "bounds", "headline", "x")
    assert_equal 200.0, evidence.dig("safe_zone", "bounds", "cta", "y")
    assert measured.fetch(:measurements).fetch("text_fit").all? { |item| item.fetch("pass") }
  end

  def test_browserless_structural_proof_is_not_mislabelled_as_measured_cls
    rendered = measure.fetch(:rendered)
    integrity = rendered.fetch("integrity")
    assert_equal "browserless_structural_proxy_not_measured_cls", integrity.dig("layout_stability", "basis")
    assert_equal true, integrity["source_analyzed"]
    refute integrity.key?("rendered")
    refute integrity.key?("cumulative_layout_shift")
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered:, token_contract: @contract)
    assert report.fetch(:checks).find { |check| check.fetch(:law) == "VISUAL_RENDER_INTEGRITY" }.fetch(:pass),
           report.fetch(:checks).inspect
  end

  def test_full_static_audit_can_pass_for_supported_explicit_layout
    rendered = measure.fetch(:rendered)
    report = Audit.audit(html: @html, css: @css, placement: "display-320x250", rendered:, token_contract: @contract)
    assert report.fetch(:passed), report.fetch(:checks).reject { |check| check.fetch(:pass) }.inspect
    assert Audit.require_pass!(report, current_contract: @contract, placement: "display-320x250")
  end


  def test_overlapping_key_elements_fail_the_structural_proof
    css = @css.sub("left: 200px; top: 200px", "left: 16px; top: 16px")
    result = measure(css:)
    collisions = result.fetch(:measurements).fetch("collisions")
    assert collisions.any? { |item| item["first"] == "headline" && item["second"] == "cta" }
    refute result.dig(:rendered, "integrity", "static_layout_complete")
  end

  def test_missing_body_reset_fails_closed
    css = @css.sub("html, body { margin: 0; padding: 0; }", "")
    result = measure(css:)
    assert_includes result.fetch(:measurements).fetch("unsupported_features").join(" "), "body margin/padding reset"
    refute result.dig(:rendered, "integrity", "layout_stability", "pass")
  end

  def test_canonical_token_override_fails_closed
    result = measure(css: @css + "\n.ad-organ { --ad-organ-on-surface: #FFFFFF; }")
    assert_includes result.fetch(:measurements).fetch("unsupported_features").join(" "), "canonical ad tokens may not be redefined"
  end

  def test_remote_asset_is_not_claimed_as_loaded
    html = @html.sub("data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", "https://cdn.example.invalid/logo.png")
    result = measure(html:)
    assert_equal false, result.dig(:rendered, "integrity", "assets_loaded")
    assert_includes result.fetch(:measurements).fetch("unsupported_features").join(" "), "not inspectable without network access"
  end

  def test_custom_web_font_prevents_high_confidence_static_proof
    result = measure(css: @css + "\n@font-face { font-family: CustomBrand; src: url(brand.woff2); }")
    assert_includes result.fetch(:measurements).fetch("unsupported_features").join(" "), "web-font loading"
    refute result.dig(:rendered, "integrity", "layout_stability", "pass")
  end

  def test_grid_and_calc_are_explicitly_outside_supported_subset
    result = measure(css: @css + "\n.ad-organ { display: grid; grid-template-columns: 1fr 1fr; width: calc(100% - 8px); }")
    unsupported = result.fetch(:measurements).fetch("unsupported_features").join(" ")
    assert_includes unsupported, "CSS Grid"
    assert_includes unsupported, "complex CSS geometry"
  end

  def test_layout_that_cannot_fit_text_fails_structural_proof
    css = @css.sub("height: 40px; font-size: 18px", "height: 12px; font-size: 30px")
    result = measure(css:)
    headline = result.fetch(:measurements).fetch("text_fit").find { |item| item.fetch("role") == "headline" }
    refute headline.fetch("pass")
    refute result.dig(:rendered, "integrity", "layout_stability", "pass")
  end


  def test_browserless_mode_cannot_smuggle_a_numeric_cls_score
    [0.0, false].each do |value|
      evidence = measure.fetch(:rendered)
      evidence.fetch("integrity")["cumulative_layout_shift"] = value
      check = Audit.render_integrity(rendered: evidence, token_contract: @contract)
      refute check.fetch(:pass)
      assert_includes check.fetch(:reasons).join(" "), "cannot claim measured CLS"
    end
  end

  def test_nonzero_padding_on_a_key_element_fails_closed
    result = measure(css: @css + "\n.ad-organ-cta { padding: 8px; }")
    unsupported = result.fetch(:measurements).fetch("unsupported_features").join(" ")
    assert_includes unsupported, "non-zero margin/padding/border"
  end

  def test_placement_requires_dimensions_or_explicit_viewport
    assert_raises(ArgumentError) { measure(placement: "campaign-banner") }
    result = measure(placement: "campaign-banner", viewport: { width: 320, height: 250 })
    assert_equal 320, result.dig(:rendered, "viewport", "width")
  end
end
