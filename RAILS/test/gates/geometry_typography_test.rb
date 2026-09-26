# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../MASTER/gates/support/geometry_type"
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
