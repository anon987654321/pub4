# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "gate_probe_harness"
require_relative "../../gates/lib/rendered/web_vitals_budget"

# PERF-100, and the clearest case in this batch of a gate that reported ok while
# measuring nothing.
#
# The gate has two halves. The source half reads hotwire.js and asserts the field
# sampler still observes LCP, CLS and INP; the live half loads a page in Chrome and
# judges the two paint metrics against a budget. The budget is the gate — the pass
# line is "LCP and CLS within budget" — and the source half is its blindness alarm.
#
# Counting the source half as measurement meant that on any machine without Chrome
# the gate read three strings out of a JavaScript file, measured neither metric, and
# reported PASSED under a line claiming both were within budget. The runner never
# named it either: it only collects skip reasons from gates whose outcome is
# inconclusive. The last two tests hold the corrected shape.
class WebVitalsBudgetGateTest < Minitest::Test
  include GateProbe

  GATE = Deploy::WebVitalsBudget
  PROBE = Deploy::GeometryProbe

  SAMPLER = <<~JS
    observe({ type: "largest-contentful-paint", buffered: true })
    observe({ type: "layout-shift", buffered: true })
    observe({ type: "first-input", buffered: true })
  JS

  def with_sampler(body = SAMPLER)
    Dir.mktmpdir("web-vitals") do |dir|
      path = File.join(dir, "hotwire.js")
      File.write(path, body)
      with_const(GATE, :HOTWIRE, path) { yield }
    end
  end

  def surface
    PROBE::Surface.new(app: "brgen", label: "core", host: nil, path: "/", viewport: "mobile",
                       width: 390, height: 844, snapshot: false, port: 38_182)
  end

  # lcp in ms, cls unitless; nil for "the page reported no entry".
  def measured(lcp:, cls:)
    rows = [surface]
    with_methods(
      PROBE,
      available?: proc { true },
      surfaces: proc { |*, **| rows },
      unreachable_apps: proc { |*, **| [] },
      reachable: proc { |list, **| list },
      with_browser: proc { |*, **, &block| block.call(FakeCdp.new { |_js, _| JSON.generate("lcp" => lcp, "cls" => cls) }) }
    ) { GATE.run }
  end

  def dark = with_methods(PROBE, available?: proc { false }) { GATE.run }

  def test_a_page_over_the_lcp_budget_is_named_with_its_number
    with_sampler do
      result = measured(lcp: 4200.4, cls: 0.0)

      assert_equal :failed, result.outcome
      assert_match(/web_vitals_budget: core LCP 4200ms over 2500ms/, result.failures.join(" | "))
    end
  end

  def test_a_page_over_the_cls_budget_is_named_with_its_number
    with_sampler do
      assert_match(/CLS 0\.25 over 0\.1/, measured(lcp: 900.0, cls: 0.25).failures.join(" | "))
    end
  end

  def test_a_page_inside_both_budgets_passes
    with_sampler do
      result = measured(lcp: 900.0, cls: 0.02)

      assert_equal :passed, result.outcome, result.failures.join(" | ")
      assert_equal 2, result.checks_ran, "both metrics were judged, so both are counted"
    end
  end

  # A missing metric is not a passing one. LCP is absent on a page that painted
  # nothing large enough to qualify, and calling that "within budget" is the same
  # false green one page down.
  def test_a_page_that_reported_no_lcp_entry_is_unchecked_rather_than_under_budget
    with_sampler do
      result = measured(lcp: nil, cls: 0.0)

      assert_match(/reported no LCP entry/, result.unchecked.join(" | "))
      assert_empty result.failures
    end
  end

  # The field half is what stops the fleet going blind between gate runs, and it
  # is the one half that runs everywhere.
  def test_a_sampler_that_stopped_observing_a_metric_is_named_with_the_metric
    with_sampler(SAMPLER.lines.reject { |l| l.include?("first-input") }.join) do
      assert_match(/no longer observes first-input — INP stopped being collected in the field/,
                   dark.failures.join(" | "))
    end
  end

  def test_a_missing_hotwire_js_is_named_rather_than_read_as_a_clean_sampler
    with_const(GATE, :HOTWIRE, "/nonexistent/hotwire.js") do
      assert_match(/missing — nothing collects vitals in the field/, dark.failures.join(" | "))
    end
  end

  # The third state. Reading the sampler is not measuring the budget.
  def test_without_chrome_it_reports_inconclusive_rather_than_a_budget_it_never_measured
    with_sampler do
      result = dark

      assert_equal :inconclusive, result.outcome,
                   "three strings found in hotwire.js are not LCP and CLS within budget"
      assert_match(/no Chrome\/Chromium — LCP and CLS not measured/, result.unchecked.join(" | "))
      assert_equal 0, result.checks_ran
    end
  end

  def test_with_no_app_listening_it_reports_inconclusive
    with_sampler do
      rows = [surface]
      result = with_methods(
        PROBE,
        available?: proc { true },
        surfaces: proc { |*, **| rows },
        unreachable_apps: proc { |*, **| ["brgen"] },
        reachable: proc { |*, **| [] }
      ) { GATE.run }

      assert_equal :inconclusive, result.outcome
      assert_match(/no app reachable — paint budget not measured/, result.unchecked.join(" | "))
    end
  end

  # A sampler failure must still block when the browser half could not run, or the
  # alarm is only audible on the one machine that does not need it.
  def test_a_sampler_failure_blocks_even_with_no_browser_to_confirm_it
    with_sampler(SAMPLER.lines.reject { |l| l.include?("layout-shift") }.join) do
      assert_equal :failed, dark.outcome
    end
  end
end
