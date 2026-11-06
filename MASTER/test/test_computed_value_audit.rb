# frozen_string_literal: true

require_relative "test_helper"
require_relative "../checks/lib/rendered/rendered_geometry"

# The computed-value audit: what the browser computed for each element, against tokens.yml,
# reported as one finding per Law. Planted probe payloads, the shape walk.js returns.
class TestComputedValueAudit < Minitest::Test
  CHECK = Deploy::RenderedGeometryCheck
  SURFACE = Deploy::GeometryProbe::Surface.new(app: "brgen", label: "core", viewport: "mobile", width: 390,
                                               height: 844)

  def element(key, **fields)
    { "key" => key, "tag" => "div", "visible" => true, "text" => "Lagre", "font_size" => 16.0,
      "line_height" => 24.0, "border_radius" => "0px", "bg" => "#ffffff", "spacing" => [16, 16, 16, 16, 0, 0, nil, nil],
      "rect" => { "x" => 0, "y" => 0, "w" => 200, "h" => 48 } }.merge(fields.transform_keys(&:to_s))
  end

  def findings(*elements)
    check = CHECK.new
    result = CHECK::Result.new
    check.instance_variable_set(:@result, result)
    check.send(:load_design_rules)
    check.check_computed_values(SURFACE, elements)
    result.soft_failures
  end

  def test_values_on_the_tokens_are_quiet
    assert_empty findings(element("main>section.card"), element("a.button", border_radius: "24px"))
  end

  def test_an_off_rhythm_padding_names_the_element_and_its_law
    found = findings(element("div.card", spacing: [10, 16, 13.5, 16, 0, 0, nil, nil]))

    assert_equal 1, found.size, found.inspect
    assert_match(%r{geometry spacing: brgen/core/mobile 2 computed value\(s\).*div\.card padding-top 10px}, found.first)
    assert_match(/padding-bottom 13\.5px law=EIGHT_PX_RHYTHM/, found.first)
  end

  def test_leading_radius_ground_and_fractional_type_each_report_under_their_law
    found = findings(element("p.lede", line_height: 23.2, font_size: 16.0),
                     element("div.tile", border_radius: "6px"),
                     element("aside.note", bg: "#fafafb"),
                     element("span.meta", font_size: 13.5, line_height: 20.25))
    laws = found.map { |line| line[/law=(\w+)/, 1] }.sort

    assert_equal %w[LINE_HEIGHT_ON_SCALE MAGIC_COLOR PIXEL_EXACT RENDERED_VALUES], laws, found.inspect
  end

  def test_more_distinct_sizes_than_the_type_scale_allows_is_one_finding
    sizes = [12, 14, 16, 18, 20, 24, 28, 32, 40].map do |px|
      element("p.s#{px}", font_size: px.to_f, line_height: px * 1.5)
    end

    assert_match(/9 distinct font sizes over 8.*law=TYPE_HIERARCHY/, findings(*sizes).join)
  end
end
