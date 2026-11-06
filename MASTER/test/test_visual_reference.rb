# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/fix/visual_reference"

class TestVisualReference < Minitest::Test
  def test_profiles_are_descriptive_lenses
    profiles = Master::Fix::VisualReference.profiles

    assert_equal %w[bol joi kaufland pangram x], profiles.keys.sort
    profiles.each_value do |profile|
      assert profile[:name]
      assert_operator profile[:signals].length, :>, 0
    end
  end

  def test_context_keeps_master_as_authority
    context = Master::Fix::VisualReference.context

    assert_includes context, "MASTER laws remain authoritative"
    assert_includes context, "not a scorecard, ranking"
    assert_includes context, "x:"
    assert_includes context, "joi:"
    assert_includes context, "kaufland:"
    assert_includes context, "bol:"
    assert_includes context, "pangram:"
  end

  def element(tag, text, rect:, **extra)
    { "tag" => tag, "text" => text, "frect" => %w[x y w h].zip(rect).to_h, "font_size" => 16.0,
      "color" => "#111111" }.merge(extra.transform_keys(&:to_s))
  end

  # Elements pair by role or tag and text, whatever their order; the report leads with the largest
  # difference and names every axis that moved.
  def test_elements_pair_by_role_and_text_and_report_their_deltas
    ours = [element("h1", "Markedsplass", rect: [16, 24, 358, 40], font_size: 28.0),
            element("button", "Selg", rect: [16, 600, 120, 44], color: "#ff0000"),
            element("p", "Bare hos oss", rect: [0, 0, 1, 1])]
    theirs = [element("button", "selg", rect: [16, 596, 120, 48]),
              element("h1", "Markedsplass", rect: [16, 16, 358, 40])]
    pairs = Master::Fix::VisualReference.compare(ours, theirs)
    report = Master::Fix::VisualReference.report(pairs)

    assert_equal [%w[h1 markedsplass], %w[button selg]], pairs.map(&:key)
    assert_match(/matched 2\)\nh1 markedsplass: y 8.0, font_size 12.0\nbutton selg: y 4.0, h -4.0, color/, report)
  end
end
