# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/lib/rendered/rendered_geometry"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "gate_probe_harness"

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

  def glyph_findings(rows)
    result = Deploy::GateResult.new
    TYPE.check_glyphs(result, surface, { "glyphs" => rows })
    result.soft_failures
  end

  def test_glyphs_names_a_face_that_draws_latin_but_not_aeoa
    found = glyph_findings([{ "stack" => '"Caprasimo", serif', "family" => "Caprasimo", "covered" => false },
                            { "stack" => "Inter, sans-serif", "family" => "Inter", "covered" => true }])

    assert_equal 1, found.size, found.inspect
    assert_match(/draws æøå from a fallback face — Caprasimo lacks them/, found.first)
  end

  # No named face the browser has means a generic renders the stack, and a generic draws æøå.
  def test_glyphs_spares_covered_faces_and_stacks_left_to_a_generic
    assert_empty glyph_findings([{ "stack" => "Inter, sans-serif", "family" => "Inter", "covered" => true },
                                 { "stack" => "system-ui", "family" => nil, "covered" => nil }])
    assert_empty glyph_findings([])
  end

  def walk_with(glyphs)
    cdp = GateProbe::FakeCdp.new do |js, awaited|
      next glyphs.call(awaited) if js == Deploy::GeometryProbe::GLYPHS
      next true if js.include?("document.fonts.status")

      js == Deploy::GeometryProbe::WALK ? { "elements" => [] } : {}
    end
    Deploy::GeometryProbe.walk(cdp, surface)
  end

  def test_walk_awaits_the_glyph_probe_and_merges_its_rows
    payload = walk_with(->(awaited) { { "glyphs" => [{ "family" => "Inter", "covered" => awaited }] } })

    assert_equal [{ "family" => "Inter", "covered" => true }], payload["glyphs"]
    assert_equal [], payload["elements"]
  end

  def test_walk_keeps_the_surface_when_the_glyph_probe_throws
    payload = walk_with(->(_) { raise Deploy::CdpSession::JsError, "fonts.load rejected" })

    assert_nil payload["error"]
    assert_equal 200, payload["status"]
    refute payload.key?("glyphs")
  end

  GATE = Deploy::RenderedGeometryGate

  def gate_findings
    gate = GATE.new
    result = GATE::Result.new
    gate.instance_variable_set(:@result, result)
    gate.instance_variable_set(:@rules, Operator::MasterDesign.blocks(GATE::MASTER_RULES))
    yield gate
    result.soft_failures
  end

  # rect is [x, y, w, h].
  def box(key, rect, fill: "#1a1a1a", under: "#000000", **extra)
    { "key" => key, "tag" => extra.delete(:tag) || "div", "visible" => true, "onscreen" => true,
      "frect" => %w[x y w h].zip(rect).to_h,
      "fill" => !fill.nil?, "bg" => fill || under, "under" => fill && under }.merge(extra.transform_keys(&:to_s))
  end

  def page(*boxes) = [box("header.page-header", [0, 0, 390, 56]), *boxes]

  def dominance(elements) = gate_findings { |gate| gate.check_dominance(surface, elements) }

  def test_dominance_names_a_white_banner_that_outweighs_the_screen
    found = dominance(page(box("div.promo-banner", [0, 80, 390, 300], fill: "#ffffff"),
                           box("button.btn.btn--primary", [16, 400, 120, 44], fill: "#f2f2f2")))

    assert_equal 1, found.size, found.inspect
    assert_match(/div\.promo-banner carries \d+% of the visual weight of 3 painted boxes/, found.first)
  end

  def test_dominance_spares_the_primary_action_when_it_is_the_heaviest_box
    assert_empty dominance(page(box("button.btn.btn--primary", [16, 400, 358, 120], fill: "#ffffff"),
                                box("span.badge", [16, 80, 60, 24], fill: "#333333")))
  end

  # The shell or a full-bleed main paints the ground, and a ground always wins.
  def test_dominance_reads_a_viewport_sized_box_as_ground_not_figure
    assert_empty dominance(page(box("main#main-content", [0, 0, 390, 844], fill: "#ffffff"),
                                box("div.promo-banner", [0, 80, 390, 150], fill: "#ffffff"),
                                box("button.btn.btn--primary", [0, 400, 390, 200], fill: "#ffffff")))
  end

  # A subtle header is most of a page that paints almost nothing, and still light.
  def test_dominance_ignores_a_large_share_of_a_quiet_page
    assert_empty dominance(page(box("span.badge", [16, 80, 60, 24], fill: "#333333"),
                                box("span.chip", [90, 80, 60, 24])))
  end

  def test_dominance_needs_three_painted_boxes_to_call_a_share
    assert_empty dominance([box("div.promo-banner", [0, 80, 390, 300], fill: "#ffffff"),
                            box("span.badge", [16, 400, 60, 24])])
  end

  def action(key, x, w, fill, parent: "div.actions", font_weight: "400")
    box(key, [x, 700, w, 44], fill: fill, tag: "button", parent: parent, font_weight: font_weight)
  end

  def action_weight(elements) = gate_findings { |gate| gate.check_action_weight(surface, elements) }

  def test_action_weight_names_a_ghost_heavier_than_its_primary
    found = action_weight([action("div.actions>button.btn.btn--primary", 16, 100, "#333333"),
                           action("div.actions>button.btn.btn-ghost", 132, 140, "#ffffff")])

    assert_equal 1, found.size, found.inspect
    assert_match(/button\.btn\.btn-ghost over div\.actions>button\.btn\.btn--primary/, found.first)
  end

  # Larger but paler is a trade, and a trade is the operator's to make.
  def test_action_weight_leaves_a_trade_between_axes_alone
    assert_empty action_weight([action("div.actions>button.btn.btn--primary", 16, 100, "#ffffff"),
                                action("div.actions>button.btn.btn-ghost", 132, 160, "#333333")])
  end

  def test_action_weight_compares_siblings_only
    assert_empty action_weight([action("div.actions>button.btn.btn--primary", 16, 100, "#333333"),
                                action("nav>button.btn", 132, 140, "#ffffff", parent: "nav")])
  end

  def test_action_weight_counts_a_heavier_font_as_an_axis
    found = action_weight([action("div.actions>button.btn.btn--primary", 16, 100, "#333333"),
                           action("div.actions>button.btn", 132, 100, "#ffffff", font_weight: "700")])

    assert_match(/button\.btn over/, found.join)
  end

  def test_layout_runs_the_weight_and_grammar_checks
    elements = page(box("div.promo-banner", [0, 80, 390, 300], fill: "#ffffff"),
                    action("div.actions>button.btn.btn--primary", 16, 100, "#333333"),
                    action("div.actions>button.btn.btn-ghost", 132, 140, "#ffffff"),
                    search_field("header>form>input"), search_field("main>form>input"))
    found = gate_findings { |gate| gate.check_layout(surface, { "elements" => elements }) }

    %w[dominance action_weight duplicate_search].each do |check|
      assert found.any? { |m| m.start_with?("geometry #{check}:") }, "#{check} did not run: #{found.inspect}"
    end
  end

  def grammar(check, *args)
    gate_findings { |gate| gate.public_send(check, surface, *args) }
  end

  def bar(sel, hrefs, onscreen: true, nested: false)
    { "sel" => sel, "hrefs" => hrefs, "onscreen" => onscreen, "nested" => nested }
  end

  TABS = %w[/ /search /notifications /profile].freeze

  def navs(*bars) = grammar(:check_duplicate_nav, { "groups" => [bar("nav.tab-bar", TABS), *bars] })

  def test_duplicate_nav_names_two_bars_offering_the_same_places
    assert_match(/duplicate_nav: .*nav\.tab-bar and nav\.top/, navs(bar("nav.top", TABS + %w[/tv])).join)
  end

  # A closed drawer repeats the tab bar by design, and a tablist inside a bar is the bar.
  def test_duplicate_nav_spares_a_drawer_off_screen_and_a_bar_inside_a_bar
    assert_empty navs(bar("aside>nav", TABS, onscreen: false))
    assert_empty navs(bar("nav>div", TABS, nested: true))
    assert_empty navs(bar("nav.verticals", %w[/tv /dating /maps]))
  end

  def search_field(key, input_type: "search")
    { "key" => key, "tag" => "input", "input_type" => input_type, "search" => true,
      "visible" => true, "onscreen" => true }
  end

  def test_duplicate_search_names_two_search_fields
    found = grammar(:check_duplicate_search, [search_field("header>form>input"), search_field("main>form>input")])

    assert_match(/lays out 2 search fields — header>form>input; main>form>input/, found.join)
  end

  # A search form's own submit button is not a second field.
  def test_duplicate_search_counts_fields_not_their_buttons
    assert_empty grammar(:check_duplicate_search, [search_field("header>form>input"),
                                                   search_field("header>form>input[2]", input_type: "submit")])
  end

  # Each block is [selector, width].
  def drift(*blocks)
    grammar(:check_width_drift, { "main_blocks" => blocks.map { |sel, w| { "sel" => sel, "x" => 0, "w" => w } } })
  end

  def test_width_drift_names_a_section_a_few_pixels_off_the_column
    found = drift(["section.feed", 600], ["section.composer", 600], ["section.trending", 584])

    assert_match(/600px column and 1 block\(s\).*section\.trending 584px/, found.join)
  end

  # A form capped far inside the column is an inset somebody chose; one pixel is rounding.
  def test_width_drift_spares_a_deliberate_inset_and_rounding
    assert_empty drift(["section.feed", 600], ["section.a", 601], ["form.narrow", 400])
  end

  # size is [w, h]; the card is 358 wide at y, h tall.
  def control_in(card_sel, key, size, card_y: 64, card_h: 600)
    { "key" => key, "tag" => "button", "interactive" => true, "visible" => true, "onscreen" => true,
      "card" => { "sel" => card_sel, "x" => 16, "y" => card_y, "w" => 358, "h" => card_h },
      "frect" => { "x" => 16, "y" => 600, "w" => size[0], "h" => size[1] } }
  end

  def lost(*controls) = grammar(:check_lost_action, controls)

  def test_lost_action_names_a_small_button_alone_in_a_screen_sized_card
    found = lost(control_in("section.signup-card", "div>button.btn", [44, 44]))

    assert_match(/lost_action: .*section\.signup-card \(358x600\) holds div>button\.btn/, found.join)
  end

  def test_lost_action_spares_a_full_width_action_a_small_card_and_a_list
    assert_empty lost(control_in("section.signup-card", "div>button.btn", [326, 48]))
    assert_empty lost(control_in("div.mini-card", "div>button.btn", [44, 44], card_h: 120))
    assert_empty lost(control_in("article.feed-card", "footer>button", [44, 44]),
                      control_in("article.feed-card", "footer>button[2]", [44, 44], card_y: 700))
  end
end
