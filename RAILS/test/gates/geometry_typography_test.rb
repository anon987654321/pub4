# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../MASTER/gates/support/geometry_type"
require_relative "../../../MASTER/gates/support/geometry_probe"
require_relative "../../../OPENBSD/lib/gate_result"

class GeometryTypographyTest < Minitest::Test
  Surface = Data.define(:id, :label, :path, :width)

  def surface(path: "/feed", label: "feed")
    Surface.new(id: "test", label:, path:, width: 1440)
  end

  def test_rag_extreme_final_line_is_reported
    result = Deploy::GateResult.new
    Deploy::GeometryType.check_rag(
      result,
      surface,
      {
        "prose" => [
          { "sel" => ".prose", "line_count" => 6, "rag_ratio" => 0.08, "text_align" => "left" },
        ],
      },
      {}
    )

    assert result.soft_failures.any? { |message| message.include?("geometry rag") }
  end

  def test_unavailable_glyph_probe_is_inconclusive_not_a_clean_glyph_result
    cdp = Object.new
    def cdp.evaluate(*, **)
      nil
    end

    payload = Deploy::GeometryProbe.glyph_coverage(cdp)
    result = Deploy::GateResult.new
    Deploy::GeometryType.check_glyphs(result, surface, payload)

    assert_match(/unverified/, payload.fetch("glyphs_status"))
    assert result.incomplete?
    assert_equal :inconclusive, result.outcome
    assert_match(/geometry glyphs: test coverage not measured/, result.unchecked.join)
  end

  def test_micro_typography_failure_is_inconclusive_not_silent
    previous_strict = ENV.delete("GATE_STRICT_INCONCLUSIVE")
    result = Deploy::GateResult.new
    broken_data = Class.new(Hash) do
      def dig(*) = raise(IOError, "fixture read failed")
    end.new

    Deploy::GeometryType.check_micro_typography(result, surface, broken_data, {})

    assert result.incomplete?
    assert_equal :inconclusive, result.outcome
    assert_match(/geometry micro_type: test could not be measured \(IOError: fixture read failed\)/,
                 result.unchecked.join)
  ensure
    previous_strict.nil? ? ENV.delete("GATE_STRICT_INCONCLUSIVE") : ENV["GATE_STRICT_INCONCLUSIVE"] = previous_strict
  end

  def test_micro_typography_accepts_explicit_browser_contract
    result = Deploy::GateResult.new
    Deploy::GeometryType.check_micro_typography(
      result,
      surface(path: "/privacy", label: "privacy"),
      {
        "typography" => {
          "prose" => [
            {
              "text_wrap" => "pretty",
              "font_feature_settings" => %("kern", "liga"),
              "font_kerning" => "normal",
            },
          ],
        },
      },
      {}
    )

    assert_empty result.soft_failures
  end
end
