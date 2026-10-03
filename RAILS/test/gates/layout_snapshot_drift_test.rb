# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/lib/rendered/layout_snapshot"

# layout_snapshot's comparison, over hand-built snapshots. Nothing here launches
# Chrome: the gate distils a probe payload into this shape, and every judgement
# it makes about two snapshots is pure Ruby.
#
# The first six tests are the flat comparison's contract, moved here from
# rendered_gates_test.rb when classification arrived; they pass unchanged, which
# is the proof that sorting the differences dropped none of them.
class LayoutSnapshotDriftTest < Minitest::Test
  def element(key, tag, rect, **style)
    {
      "key" => key, "tag" => tag, "rect" => rect.transform_keys(&:to_s),
      "color" => "#ffffff", "bg" => "#000000", "font_size" => 16.0,
      "line_height" => 24.0, "display" => "block", "position" => "static",
    }.merge(style.transform_keys(&:to_s))
  end

  def snapshot(overrides = {})
    {
      "title" => "Listings", "viewport" => [390, 844], "scroll_width" => 390, "h1_count" => 1,
      "landmarks" => { "main" => true, "nav" => true, "skip" => true },
      "elements" => [element("nav.tab-bar", "nav", { x: 0, y: 0, w: 390, h: 48 }, display: "flex", position: "fixed")],
    }.merge(overrides)
  end

  # A phone page with a heading, body copy set in a nav and main, two actions
  # and a landmark order, so the derived ratios have something to derive from.
  def page(h1_size: 32.0, buy: { x: 16, y: 300, w: 358, h: 56 }, cancel_colour: "#666666")
    snapshot("elements" => [
      element("nav.tab-bar", "nav", { x: 0, y: 0, w: 390, h: 48 }),
      element("#main-content", "main", { x: 0, y: 48, w: 390, h: 700 }),
      element("footer.legal", "footer", { x: 0, y: 748, w: 390, h: 96 }),
      element("#main-content>h1", "h1", { x: 16, y: 64, w: 358, h: 40 }, font_size: h1_size, line_height: 40.0),
      element("#main-content>p.lede", "p", { x: 16, y: 120, w: 358, h: 24 }),
      element("#main-content>button.buy", "button", buy),
      element("#main-content>button.cancel", "button", { x: 16, y: 372, w: 120, h: 44 }, color: cancel_colour, bg: "#ffffff"),
    ])
  end

  def compare(a, b)
    Deploy::LayoutSnapshotGate.new.send(:compare, a, b)
  end

  def moved(snap, key, **rect)
    snap["elements"] = snap["elements"].map do |el|
      el["key"] == key ? el.merge("rect" => el["rect"].merge(rect.transform_keys(&:to_s))) : el
    end
    snap
  end

  def test_identical_snapshots_do_not_drift
    assert_empty compare(snapshot, snapshot)
  end

  def test_sub_pixel_movement_is_tolerated
    moved = snapshot
    moved["elements"] = [moved["elements"].first.merge("rect" => { "x" => 0, "y" => 1, "w" => 390, "h" => 49 })]
    assert_empty compare(snapshot, moved), "a 1px shift is rounding, not a regression"
  end

  def test_a_real_move_is_reported_with_both_values
    moved = snapshot
    moved["elements"] = [moved["elements"].first.merge("rect" => { "x" => 0, "y" => 0, "w" => 390, "h" => 32 })]
    diffs = compare(snapshot, moved)
    assert_equal 1, diffs.size
    assert_match(/h 48→32/, diffs.first, "the diff must name the old and new value, not just 'changed'")
  end

  def test_colour_change_is_reported
    recoloured = snapshot
    recoloured["elements"] = [recoloured["elements"].first.merge("color" => "#969696")]
    assert_match(/color "#ffffff" → "#969696"/, compare(snapshot, recoloured).first)
  end

  def test_lost_landmark_is_reported
    assert_match(/landmark skip: true → false/,
                 compare(snapshot, snapshot("landmarks" => { "main" => true, "nav" => true, "skip" => false })).first)
  end

  def test_added_and_removed_elements_are_reported
    empty = snapshot("elements" => [])
    assert_match(/removed: nav.tab-bar/, compare(snapshot, empty).join(" "))
    assert_match(/added: nav.tab-bar/, compare(empty, snapshot).join(" "))
  end

  def test_every_difference_names_its_class
    diffs = compare(page, moved(page(h1_size: 18.0), "#main-content>p.lede", y: 126))
    classes = Deploy::LayoutSnapshotGate::Drift::CLASSES

    assert diffs.all? { |diff| classes.include?(diff[/\A\w+/]) }, diffs.inspect
  end

  # The case the classes exist for: a heading that fell to body size, reported
  # under a pile of small moves. It leads the list, stated as the ratio.
  def test_a_collapsed_hierarchy_leads_a_list_of_nudges
    after = page(h1_size: 17.9)
    { "nav.tab-bar" => 4, "#main-content>p.lede" => 124, "#main-content>button.cancel" => 376 }.each { |key, y| moved(after, key, y:) }
    diffs = compare(page, after)

    assert_equal "hierarchy: h1/body ratio 2.00 → 1.12", diffs.first
    assert_match(/\Anudge: /, diffs.last)
  end

  def test_the_report_leads_with_the_tally_most_severe_first
    result = Struct.new(:fails) { def fail(msg, **) = fails << msg }.new([])
    gate = Deploy::LayoutSnapshotGate.new
    gate.instance_variable_set(:@result, result)
    surface = Struct.new(:id).new("brgen-core-mobile")
    diffs = compare(page, moved(page(h1_size: 17.9), "#main-content>p.lede", y: 126))
    gate.send(:report, surface, diffs, "/tmp/x.json")

    assert_match(/drifted from \S+ — hierarchy 1, style 1, nudge 1 — hierarchy: h1\/body ratio/, result.fails.first)
  end

  def test_a_line_more_of_text_is_a_wrap_not_a_move
    diffs = compare(page, moved(page, "#main-content>p.lede", h: 48))

    assert_equal ["wrap: #main-content>p.lede: +1 line(s) (h 24→48)"], diffs.grep(/p\.lede/)
  end

  def test_padding_that_is_not_a_whole_line_is_not_a_wrap
    diffs = compare(page, moved(page, "#main-content>p.lede", h: 36))

    assert_equal ["reflow: #main-content>p.lede: h 24→36"], diffs.grep(/p\.lede/), "12px is half a 24px line and more than a nudge"
  end

  def test_crossing_into_another_landmark_is_a_reflow
    diffs = compare(page, moved(page, "#main-content>p.lede", y: 780))

    assert_equal ["reflow: #main-content>p.lede: #main-content → footer.legal (y 120→780)"], diffs
  end

  def test_a_small_move_inside_its_landmark_is_a_nudge
    assert_equal ["nudge: #main-content>p.lede: y 120→126"], compare(page, moved(page, "#main-content>p.lede", y: 126))
  end

  def test_a_shrunken_primary_action_is_a_hierarchy_change
    diffs = compare(page, page(buy: { x: 16, y: 300, w: 140, h: 44 }))

    assert_includes diffs, "hierarchy: primary action size ratio 3.80 → 1.17"
  end

  def test_primary_action_contrast_is_judged_against_its_siblings
    diffs = compare(page, page(cancel_colour: "#000000"))

    assert_equal "hierarchy: primary action contrast ratio 3.66 → 1.00", diffs.first
  end

  def test_losing_a_third_of_the_elements_is_density
    after = page
    after["elements"] = after["elements"].reject { |el| el["tag"] == "button" }
    diffs = compare(page, after)

    assert_includes diffs, "density: elements 7 → 5"
    assert_includes diffs, "density: removed: #main-content>button.buy"
  end

  def test_landmarks_that_swap_reading_order_are_a_hierarchy_change
    after = moved(moved(page, "nav.tab-bar", y: 796), "footer.legal", y: 0)
    diffs = compare(page, after)

    assert_equal "hierarchy: landmark order nav.tab-bar, #main-content, footer.legal → footer.legal, #main-content, nav.tab-bar",
                 diffs.first
  end
end
