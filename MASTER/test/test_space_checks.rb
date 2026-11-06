# frozen_string_literal: true

require_relative "test_helper"
require_relative "../checks/lib/rendered/rendered_geometry"

# Negative space, grouping and heading details on the first screen of a phone, planted payloads.
class TestSpaceChecks < Minitest::Test
  CHECK = Deploy::RenderedGeometryCheck
  PHONE = Deploy::GeometryProbe::Surface.new(app: "brgen", label: "core", viewport: "mobile", width: 390, height: 844)

  # rect is [x, y, w, h].
  def text(key, rect, tag: "p", **fields)
    { "key" => key, "tag" => tag, "visible" => true, "text" => "Tekst", "font_size" => 16.0, "text_lines" => 1,
      "frect" => %w[x y w h].zip(rect).to_h, "color" => "#111111", "bg" => "#ffffff" }
      .merge(fields.transform_keys(&:to_s))
  end

  def run_space(*elements)
    check = CHECK.new
    result = CHECK::Result.new
    check.instance_variable_set(:@result, result)
    check.check_space(PHONE, elements)
    result
  end

  def found(*elements) = run_space(*elements).soft_failures.join("\n")

  def calm_page
    [text("h1.title", [16, 16, 358, 40], tag: "h1", font_size: 32.0), text("p.lede", [16, 64, 358, 48]),
     text("h2.section", [16, 160, 358, 28], tag: "h2", font_size: 24.0), text("p.body", [16, 196, 358, 96]),
     text("p.more", [16, 300, 358, 96])]
  end

  def test_a_calm_page_is_quiet_and_reports_its_counts
    result = run_space(*calm_page)

    assert_empty result.soft_failures
    assert_match(/geometry minimalism: brgen\/core\/mobile elements=5 colours=2 shadows=0 left_edges=1 empty=\d+%/,
                 result.warnings.join)
  end

  def test_a_heading_nearer_the_block_above_than_its_own_text_is_a_proximity_finding
    page = [text("p.intro", [16, 16, 358, 96]), text("h2.section", [16, 120, 358, 28], tag: "h2"),
            text("p.body", [16, 180, 358, 96])]

    assert_match(/heading_proximity.*h2\.section\ sits\ 8px\ under\ the\ block\ above\ and\ 32px\ over\ its\ text
                  \ law=NEGATIVE_SPACE_GROUPING/x,
                 found(*page))
  end

  def test_a_two_line_heading_without_balance_is_a_line_break_finding
    assert_match(/heading_wrap.*law=HEADING_WRAP_BALANCE/,
                 found(text("h1.title", [16, 16, 358, 80], tag: "h1", text_lines: 2, text_wrap: "wrap")))
    assert_empty found(text("h1.title", [16, 16, 358, 80], tag: "h1", text_lines: 2, text_wrap: "balance"))
  end

  def test_six_body_sizes_are_one_too_many
    page = [12, 13, 14, 15, 16, 18].each_with_index.map do |px, index|
      text("p.s#{px}", [16, 16 + index * 40, 358, 24], font_size: px.to_f)
    end

    assert_match(/body_sizes.*6 body-side sizes over 5.*law=TYPE_HIERARCHY/, found(*page))
  end

  def test_text_against_a_phone_edge_and_an_empty_band_are_whitespace_findings
    page = [text("p.tight", [2, 16, 300, 24]), text("p.far", [16, 500, 358, 24])]
    report = found(*page)

    assert_match(/edge_crowding.*p\.tight 2px from the edge law=WHITESPACE_RHYTHM/, report)
    assert_match(/void.*460px empty band above y=500 law=NEGATIVE_SPACE_GROUPING/, report)
  end
end
