# frozen_string_literal: true

require_relative "test_helper"

class VisualLanguageTest < Minitest::Test
  Surface = Struct.new(:app, :label, :host, :path) do
    def id = "#{app}/#{label}/desktop"
  end

  def surface(app: "master", label: "chat", path: "/")
    Surface.new(app, label, nil, path)
  end

  def payload
    {
      "elements" => [
        {
          "tag" => "article",
          "key" => "main>article.card",
          "font_family" => "system-ui, sans-serif",
          "font_size" => 18,
          "text_align" => "left",
          "border_radius" => "16px",
          "box_shadow" => true,
          "background_gradient" => false,
          "visual_filter" => false,
        },
        {
          "tag" => "button",
          "key" => "main>button",
          "font_family" => "system-ui, sans-serif",
          "font_size" => 16,
          "text_align" => "center",
          "border_radius" => "999px",
          "box_shadow" => true,
          "background_gradient" => true,
          "visual_filter" => false,
        },
      ],
      "colors" => {"#111111" => 10, "#ffffff" => 7},
      "gaps" => [{"gap" => 16}],
      "proximity" => [{"pad" => 16, "gap" => 32}],
      "visual" => {
        "first_screen" => {
          "text_blocks" => 4,
          "interactive" => 3,
          "largest_element_area_ratio" => 0.24,
          "painted_area_ratio_approx" => 0.5,
          "centered_long_text" => 1,
          "small_text" => 0,
          "primary_candidates" => [{"tag" => "button", "text" => "Send", "aria" => nil}],
        },
        "typography" => {
          "distinct_font_sizes" => [16, 18],
          "body_median_px" => 16,
          "heading_sizes" => [{"px" => 28}],
        },
      },
    }
  end

  def test_direction_is_intent_not_a_quality_score
    brief = Master::Design::VisualLanguage.brief(surface:, payload:)
    assert_includes brief, "aesthetic_direction=conversational"
    assert_includes brief, "design_coordinates="
    assert_includes brief, "Direction is an intent hypothesis"
    refute_match(/score|rank|winner/i, brief)
  end

  def test_fingerprint_captures_rendered_language
    fingerprint = Master::Design::VisualLanguage.fingerprint(payload)
    assert_equal ["system-ui", 2], [fingerprint.dig(:typography, :families).first&.first, fingerprint.dig(:typography, :families).first&.last]
    assert_equal 2, fingerprint.dig(:shape, :rounded)
    assert_equal 1, fingerprint.dig(:shape, :pills)
    assert_equal 2, fingerprint.dig(:effects, :shadows)
    assert_equal 1, fingerprint.dig(:effects, :gradients)
    assert_includes fingerprint[:genericity_signals], "gradient_focal_area"
  end

  def test_drift_compares_rendered_fingerprints
    before = payload
    after = Marshal.load(Marshal.dump(payload))
    after["visual"]["typography"]["distinct_font_sizes"] = [16, 20]
    after["elements"][1]["border_radius"] = "4px"
    drift = Master::Design::VisualLanguage.design_drift(before, after)
    assert drift.any? { |row| row.include?("type sizes changed") }
    persisted_before = JSON.parse(JSON.generate(Master::Design::VisualLanguage.fingerprint(before)))
    persisted_after = JSON.parse(JSON.generate(Master::Design::VisualLanguage.fingerprint(after)))
    persisted_drift = Master::Design::VisualLanguage.design_drift(
      {"design_fingerprint" => persisted_before},
      {"design_fingerprint" => persisted_after},
    )
    assert persisted_drift.any? { |row| row.include?("type sizes changed") }
    assert drift.any? { |row| row.include?("shape language changed") }
  end
end
