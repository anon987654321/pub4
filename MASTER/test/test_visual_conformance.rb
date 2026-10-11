# frozen_string_literal: true

require_relative "test_helper"
require File.expand_path("../lib/fix/visual_conformance", __dir__)

# Synthetic geometry payloads: the rule engine reads computed font stacks and
# selector keys, so each case is one element with the stack under test.
class VisualConformanceTest < Minitest::Test
  Surface = Struct.new(:id, :viewport)
  VC = Master::Fix::VisualConformance

  def run_on(app, *elements)
    VC.check_payload(Surface.new("#{app}/home/mobile", "mobile"), "elements" => elements)
  end

  def el(key, family, text: "hei")
    { "key" => key, "font_family" => family, "text" => text, "visible" => true }
  end

  def test_house_sans_passes
    assert_empty run_on("brgen", el("body>p.lede", '"Helvetica Neue Pro", "Helvetica Neue", Arial, sans-serif'))
  end

  def test_serif_generic_and_named_fail
    found = run_on("brgen", el("body>h1.title", "Georgia, serif"), el("body>h2.sub", "Arial, serif"))
    assert_equal %w[body>h1.title body>h2.sub], found.map(&:selector).uniq.sort
    assert(found.any? { |f| f.detail.include?("named face georgia") })
    assert(found.all? { |f| f.surface == "brgen/home/mobile" && f.viewport == "mobile" })
  end

  def test_other_head_family_fails
    found = run_on("brgen", el("body>p.x", "Inter, Arial, sans-serif"))
    assert_match(/outside the house stack/, found.first.detail)
  end

  def test_monospace_allowed_in_terminal_chat_only
    assert_empty run_on("brgen", el("body>div.terminal-chat>p", "ui-monospace, monospace"))
    found = run_on("brgen", el("body>p.price", "monospace"))
    assert_match(/outside code and terminal chat/, found.first.detail)
    assert_empty run_on("brgen", el("body>pre.sample", "Menlo, monospace"))
  end

  def test_scope_skips_other_apps
    assert_empty run_on("amber", el("body>h1", "Georgia, serif"))
  end

  def test_context_lists_directive_and_violations
    capture = { surface: Surface.new("brgen/home/mobile", "mobile"), payload: { "elements" => [el("body>h1", "Georgia, serif")] } }
    text = VC.context([capture])
    assert_match(/swiss_sans_only \(brgen_typography_swiss_only\)/, text)
    assert_match(/Measured violations \(/, text)
  end

  def test_every_rule_names_a_registered_probe_check_and_directive
    keys = Array(YAML.safe_load_file(File.expand_path("../data/project_context.yml", __dir__))["entries"]).map { |e| e["key"] }
    VC.rules.each do |rule|
      assert_includes VC::PROBES, rule["probe"]
      assert_includes keys, rule["directive"]
      assert_empty rule["checks"].keys - VC::CHECKS.keys
    end
  end
end
