# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/support/geometry_probe"
require_relative "../../gates/support/geometry_type"
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
end
