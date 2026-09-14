# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/lib/rendered/rendered_geometry"
require_relative "../../../OPENBSD/lib/gate_result"

# The rendered-geometry detectors that read the probe's element list, proved on
# planted payloads. Each needs Chrome and a booted app to measure anything real,
# so every test here hands a detector the shape the probe returns and asks two
# questions: does a payload carrying the defect name it, and does the nearest
# correct payload stay quiet?
class GeometryDetectorsTest < Minitest::Test
  TYPE = Deploy::GeometryType

  def surface(width: 390, label: "core")
    Deploy::GeometryProbe::Surface.new(app: "brgen", label: label, host: nil, path: "/",
                                       viewport: width > 480 ? "desktop" : "mobile",
                                       width: width, height: 844, snapshot: false, port: 38_182)
  end

  def element(key, tag:, lines:, **extra)
    { "key" => key, "tag" => tag, "text" => "Lagre endringer", "text_lines" => lines,
      "visible" => true, "onscreen" => true, "inline_in_text" => false,
      "frect" => { "x" => 16, "y" => 100, "w" => 120, "h" => 44 }, "line_height" => 20.0 }.merge(extra)
  end

  def wrap_findings(elements, width: 390)
    result = Deploy::GateResult.new
    TYPE.check_wrap(result, surface(width: width), { "elements" => elements })
    result.soft_failures
  end

  # --- wrapped control labels and headings at phone width -------------------

  def test_wrap_names_a_button_label_on_two_lines
    found = wrap_findings([element("form>button.btn", tag: "button", lines: 2)])

    assert_equal 1, found.size, found.inspect
    assert_match(/breaks 1 control label.*form>button\.btn \(2 lines\)/, found.first)
  end

  # The case height over line-height gets wrong: 44px of box around one 20px line.
  def test_wrap_passes_a_padded_button_whose_label_is_one_line
    assert_empty wrap_findings([element("form>button.btn", tag: "button", lines: 1)])
  end

  def test_wrap_reads_a_span_inside_a_button_as_the_label
    found = wrap_findings([element("div.actions>a.btn>span", tag: "span", lines: 2)])

    assert_match(/a\.btn>span/, found.join)
  end

  def test_wrap_counts_a_repeated_label_once_with_its_instances
    found = wrap_findings([element("li>button.chip", tag: "button", lines: 2),
                           element("li>button.chip[2]", tag: "button", lines: 3)])

    assert_match(/breaks 1 control label.*li>button\.chip \(3 lines x2\)/, found.first)
  end

  def test_wrap_names_a_heading_past_three_lines_and_spares_one_at_three
    found = wrap_findings([element("main>h1", tag: "h1", lines: 4), element("main>h2", tag: "h2", lines: 3)])

    assert_equal 1, found.size, found.inspect
    assert_match(/heading.*main>h1 \(4 lines\)/, found.first)
  end

  def test_wrap_leaves_running_text_and_wide_viewports_alone
    assert_empty wrap_findings([element("article>p", tag: "p", lines: 6)])
    assert_empty wrap_findings([element("form>button.btn", tag: "button", lines: 2)], width: 1440)
  end

  def test_wrap_runs_as_part_of_the_worn_type_check
    result = Deploy::GateResult.new
    TYPE.check(result, surface, { "elements" => [element("form>button.btn", tag: "button", lines: 2)] })

    assert result.soft_failures.any? { |m| m.start_with?("geometry wrap:") }, result.soft_failures.inspect
  end

  # --- visual weight: the dominant box and the inverted action pair ---------

  GATE = Deploy::RenderedGeometryGate

  def gate_findings
    gate = GATE.new
    result = GATE::Result.new
    gate.instance_variable_set(:@result, result)
    gate.instance_variable_set(:@rules, Operator::MasterDesign.blocks(GATE::MASTER_RULES))
    yield gate
    result.soft_failures
  end

  def box(key, x:, y:, w:, h:, fill: "#1a1a1a", under: "#000000", **extra)
    { "key" => key, "tag" => extra.delete(:tag) || "div", "visible" => true, "onscreen" => true,
      "frect" => { "x" => x, "y" => y, "w" => w, "h" => h },
      "fill" => !fill.nil?, "bg" => fill || under, "under" => fill && under }.merge(extra.transform_keys(&:to_s))
  end

  def page(*boxes) = [box("header.page-header", x: 0, y: 0, w: 390, h: 56), *boxes]

  def dominance(elements)
    gate_findings { |gate| gate.check_dominance(surface, elements) }
  end

  def test_dominance_names_a_white_banner_that_outweighs_the_screen
    found = dominance(page(box("div.promo-banner", x: 0, y: 80, w: 390, h: 300, fill: "#ffffff"),
                           box("button.btn.btn--primary", x: 16, y: 400, w: 120, h: 44, fill: "#f2f2f2")))

    assert_equal 1, found.size, found.inspect
    assert_match(/div\.promo-banner carries \d+% of the visual weight of 3 painted boxes/, found.first)
  end

  def test_dominance_spares_the_primary_action_when_it_is_the_heaviest_box
    assert_empty dominance(page(box("button.btn.btn--primary", x: 16, y: 400, w: 358, h: 120, fill: "#ffffff"),
                                box("span.badge", x: 16, y: 80, w: 60, h: 24, fill: "#333333")))
  end

  # The shell or a full-bleed main paints the ground, and a ground always wins.
  def test_dominance_reads_a_viewport_sized_box_as_ground_not_figure
    assert_empty dominance(page(box("main#main-content", x: 0, y: 0, w: 390, h: 844, fill: "#ffffff"),
                                box("div.promo-banner", x: 0, y: 80, w: 390, h: 150, fill: "#ffffff"),
                                box("button.btn.btn--primary", x: 0, y: 400, w: 390, h: 200, fill: "#ffffff")))
  end

  # A subtle header is most of a page that paints almost nothing, and still light.
  def test_dominance_ignores_a_large_share_of_a_quiet_page
    assert_empty dominance(page(box("span.badge", x: 16, y: 80, w: 60, h: 24, fill: "#333333"),
                                box("span.chip", x: 90, y: 80, w: 60, h: 24)))
  end

  def test_dominance_needs_three_painted_boxes_to_call_a_share
    assert_empty dominance([box("div.promo-banner", x: 0, y: 80, w: 390, h: 300, fill: "#ffffff"),
                            box("span.badge", x: 16, y: 400, w: 60, h: 24)])
  end

  def action(key, parent: "div.actions", font_weight: "400", **geometry)
    box(key, y: 700, h: 44, tag: "button", parent: parent, font_weight: font_weight, **geometry)
  end

  def action_weight(elements)
    gate_findings { |gate| gate.check_action_weight(surface, elements) }
  end

  def test_action_weight_names_a_ghost_heavier_than_its_primary
    found = action_weight([action("div.actions>button.btn.btn--primary", x: 16, w: 100, fill: "#333333"),
                           action("div.actions>button.btn.btn-ghost", x: 132, w: 140, fill: "#ffffff")])

    assert_equal 1, found.size, found.inspect
    assert_match(/button\.btn\.btn-ghost over div\.actions>button\.btn\.btn--primary/, found.first)
  end

  # Larger but paler is a trade, and a trade is the operator's to make.
  def test_action_weight_leaves_a_trade_between_axes_alone
    assert_empty action_weight([action("div.actions>button.btn.btn--primary", x: 16, w: 100, fill: "#ffffff"),
                                action("div.actions>button.btn.btn-ghost", x: 132, w: 160, fill: "#333333")])
  end

  def test_action_weight_compares_siblings_only
    assert_empty action_weight([action("div.actions>button.btn.btn--primary", x: 16, w: 100, fill: "#333333"),
                                action("nav>button.btn", parent: "nav", x: 132, w: 140, fill: "#ffffff")])
  end

  def test_action_weight_counts_a_heavier_font_as_an_axis
    found = action_weight([action("div.actions>button.btn.btn--primary", x: 16, w: 100, fill: "#333333"),
                           action("div.actions>button.btn", x: 132, w: 100, fill: "#ffffff", font_weight: "700")])

    assert_match(/button\.btn over/, found.join)
  end

  def test_placement_runs_both_weight_checks
    elements = page(box("div.promo-banner", x: 0, y: 80, w: 390, h: 300, fill: "#ffffff"),
                    action("div.actions>button.btn.btn--primary", x: 16, w: 100, fill: "#333333"),
                    action("div.actions>button.btn.btn-ghost", x: 132, w: 140, fill: "#ffffff"))
    found = gate_findings { |gate| gate.check_placement(surface, { "elements" => elements }) }

    assert(%w[dominance action_weight].all? { |check| found.any? { |m| m.start_with?("geometry #{check}:") } }, found.inspect)
  end
end
