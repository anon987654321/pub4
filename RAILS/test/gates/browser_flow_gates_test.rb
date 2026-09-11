# frozen_string_literal: true

require "minitest/autorun"
require_relative "gate_probe_harness"
require_relative "../../gates/lib/rendered/occlusion"
require_relative "../../gates/lib/rendered/reflow"
require_relative "../../gates/lib/rendered/keyboard_flow"
require_relative "../../gates/lib/rendered/mobile_flow"

# The four browser-backed journey gates, proved on planted measurements.
#
# One file because the four share one shape and one harness. Each needs Chrome
# and a listening app, so on this machine each one's own `.run` returns after the
# precondition check — which is why a test that calls `.run` against the real tree
# and asserts "passes" proves nothing: it passes equally against `return ok`.
#
# So each gate is asked three questions. Given a measurement carrying a defect,
# does it name the defect? Given a clean one, does it pass? And given no browser
# or no listening app, does it say it measured nothing — rather than reporting the
# green that this whole family of gates exists to prevent?
#
# The third question has teeth beyond the precondition check. occlusion, reflow
# and keyboard_flow each counted the surfaces they *attempted*, and a navigation
# timeout is a warning in all three, so a run where Chrome opened and every page
# timed out reported PASSED having pressed, swept and walked nothing. Those cases
# are the last test of each group.
class BrowserFlowGatesTest < Minitest::Test
  include GateProbe

  PROBE = Deploy::GeometryProbe

  # keyboard_flow picks desktop surfaces and the other three pick mobile ones, so
  # the viewport is part of what each gate is handed.
  def surface(app: "brgen", label: "core", path: "/", viewport: "mobile")
    PROBE::Surface.new(app: app, label: label, host: nil, path: path, viewport: viewport,
                       width: 390, height: 844, snapshot: false, port: 38_182)
  end

  # Everything a rendered gate reaches the browser through, answered from here.
  # `answer` receives the JavaScript the gate chose to evaluate, so a gate that
  # stops asking its own question gets nil rather than a convenient fixture.
  def live_run(gate, surfaces: [surface], walk: { "status" => 200 }, method: :run, &answer)
    cdp = FakeCdp.new(&answer)
    with_methods(
      PROBE,
      available?: proc { true },
      surfaces: proc { |*, **| surfaces },
      unreachable_apps: proc { |*, **| [] },
      reachable: proc { |rows, **| rows },
      walk: proc { |*, **| walk },
      wait_for_fonts: proc { |*, **| true },
      with_browser: proc { |*, **, &block| block.call(cdp) }
    ) { gate.public_send(method) }
  end

  def dark_run(gate, method: :run)
    with_methods(PROBE, available?: proc { false }) { gate.public_send(method) }
  end

  def parked_run(gate, method: :run, viewport: "mobile")
    rows = [surface(viewport: viewport)]
    with_methods(
      PROBE,
      available?: proc { true },
      surfaces: proc { |*, **| rows },
      unreachable_apps: proc { |*, **| ["brgen"] },
      reachable: proc { |*, **| [] }
    ) { gate.public_send(method) }
  end

  # occlusion — does a press at this control's centre reach this control?

  OCCLUDED = [{ "control" => "a.nav_link", "label" => "Hjem", "covered_by" => "div.theme_toggle",
                "at" => [100, 200], "size" => [40, 40] }].freeze

  def test_occlusion_names_the_control_a_press_misses
    result = live_run(Deploy::OcclusionGate) { |_js, _| OCCLUDED }

    assert_names_defect(result, /a\.nav_link .*covered by div\.theme_toggle at 100,200/)
  end

  def test_occlusion_passes_when_every_control_answers_its_own_press
    assert_clean live_run(Deploy::OcclusionGate) { |_js, _| [] }
  end

  def test_occlusion_without_chrome_presses_nothing_and_says_so
    assert_inconclusive dark_run(Deploy::OcclusionGate), /no Chrome/
  end

  def test_occlusion_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::OcclusionGate), /no app reachable/
  end

  # A timeout is a warning, not a failure, so a run of nothing but timeouts has
  # an empty failure list and used to read as a pass.
  def test_occlusion_that_reached_no_surface_is_inconclusive_not_green
    result = live_run(Deploy::OcclusionGate, walk: { "error" => "Timeout: navigate" }) { |_js, _| [] }

    assert_inconclusive result, %r{reached 0/1 surface}
  end

  # reflow — the width sweep. run_once, because `run` wraps the measurement in
  # GateAutofix's remeasure loop, which writes to the stylesheets.

  def reflow_sample(scroll_width:, offenders: [])
    { "scroll_width" => scroll_width, "client_width" => 390, "columns" => 2, "tab_bar" => true,
      "sidebar" => false, "main_width" => 360, "offenders" => offenders }
  end

  def reflow_run(sample)
    with_methods(PROBE, reflow_widths: proc { |*, **| [320, 390] }) do
      live_run(Deploy::ReflowGate, method: :run_once) do |js, _|
        js.include?("document.fonts") ? true : sample
      end
    end
  end

  def test_reflow_names_the_width_and_the_element_that_hangs_off_the_edge
    result = reflow_run(reflow_sample(scroll_width: 500, offenders: ["div.deal_grid@500"]))

    assert_names_defect(result, /scrolls horizontally at 320, 390px.*div\.deal_grid/m)
  end

  def test_reflow_passes_when_nothing_spills_at_any_swept_width
    assert_clean reflow_run(reflow_sample(scroll_width: 390))
  end

  def test_reflow_without_chrome_sweeps_nothing_and_says_so
    assert_inconclusive dark_run(Deploy::ReflowGate, method: :run_once), /no Chrome/
  end

  def test_reflow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::ReflowGate, method: :run_once), /no app reachable/
  end

  def test_reflow_whose_every_width_raised_is_inconclusive_not_green
    result = with_methods(PROBE, reflow_widths: proc { |*, **| [320, 390] }) do
      live_run(Deploy::ReflowGate, method: :run_once) do |js, _|
        raise Deploy::CdpSession::Error, "socket closed" unless js.include?("document.fonts")

        true
      end
    end

    assert_inconclusive result, %r{0/1 surface}
  end

  # keyboard_flow — the tab order, walked by pressing Tab.

  def stop(sel:, order:, href: nil, ring: true, onscreen: true)
    { "sel" => sel, "tag" => sel.split(/[.#]/).first, "href" => href, "text" => sel,
      "tabindex" => nil, "rect" => { "x" => 0, "y" => 0, "w" => 80, "h" => 44 },
      "doc_order" => order, "ring" => ring, "ring_kind" => ring ? "outline" : "none",
      "onscreen" => onscreen }
  end

  SKIP_LINK = { sel: "a.skip-link", order: 1, href: "#main-content" }.freeze

  def keyboard_run(stops)
    queue = stops.dup
    live_run(Deploy::KeyboardFlowGate, surfaces: [surface(viewport: "desktop")]) do |js, _|
      next true if js.include?("document.body.setAttribute")

      queue.shift
    end
  end

  def test_keyboard_flow_names_a_skip_link_that_is_not_the_first_tab_stop
    result = keyboard_run([stop(sel: "input#email", order: 4), stop(sel: "button.send", order: 5),
                           stop(**SKIP_LINK)])

    assert_names_defect(result, /skip link is tab stop #3, not first.*input#email/)
  end

  def test_keyboard_flow_names_a_focus_stop_that_renders_no_ring
    result = keyboard_run([stop(**SKIP_LINK), stop(sel: "button.send", order: 5, ring: false)])

    assert_names_defect(result, /focus stops render no visible ring.*button\.send \(none\)/)
  end

  def test_keyboard_flow_passes_a_tab_order_that_starts_at_the_skip_link_and_rings
    assert_clean keyboard_run([stop(**SKIP_LINK), stop(sel: "a.feed", order: 9)])
  end

  def test_keyboard_flow_without_chrome_walks_nothing_and_says_so
    assert_inconclusive dark_run(Deploy::KeyboardFlowGate), /no Chrome/
  end

  def test_keyboard_flow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::KeyboardFlowGate, viewport: "desktop"), /no app reachable/
  end

  # An autofocus field that will not give focus back makes the walk start
  # mid-document, which reads as a misplaced skip link. The gate declines to
  # measure — and when that is every surface, it has walked nothing.
  def test_keyboard_flow_that_never_released_focus_is_inconclusive_not_green
    result = live_run(Deploy::KeyboardFlowGate, surfaces: [surface(viewport: "desktop")]) do |js, _|
      js.include?("document.body.setAttribute") ? false : nil
    end

    assert_inconclusive result, /would not release focus/
  end

  # mobile_flow — the phone journey floor at 390x844.

  def mobile_measure(has_main: true, has_skip: true, overflow: false, chrome: [])
    { "has_main" => has_main, "has_skip" => has_skip, "has_tab_bar" => true, "overflow" => overflow,
      "scroll_width" => overflow ? 500 : 390, "client_width" => 390, "chrome" => chrome,
      "title" => "Bergen" }
  end

  def mobile_run(measure)
    live_run(Deploy::MobileFlowGate) { |_js, _| measure }
  end

  def test_mobile_flow_names_a_missing_landmark_and_a_phone_overflow
    result = mobile_run(mobile_measure(has_main: false, overflow: true))

    assert_names_defect(result, /missing main landmark/)
    assert_match(/horizontal overflow scroll=500 client=390/, result.failures.join(" | "))
  end

  # 44px is the floor; a primary action under it is hard, the rest soft.
  def test_mobile_flow_names_a_primary_action_under_the_touch_floor
    tiny = [{ "label" => "Logg inn", "w" => 40, "h" => 28, "min" => 28, "top" => 10, "bottom" => 38 }]
    result = mobile_run(mobile_measure(chrome: tiny))

    assert_names_defect(result, /touch target "Logg inn" is 40×28 \(min 44px\)/)
  end

  def test_mobile_flow_passes_a_phone_surface_that_meets_the_floor
    ok = [{ "label" => "Logg inn", "w" => 88, "h" => 44, "min" => 44, "top" => 10, "bottom" => 54 }]

    assert_clean mobile_run(mobile_measure(chrome: ok))
  end

  def test_mobile_flow_without_chrome_measures_no_phone_viewport_and_says_so
    assert_inconclusive dark_run(Deploy::MobileFlowGate), /no Chrome/
  end

  def test_mobile_flow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::MobileFlowGate), /no app reachable/
  end

  def test_mobile_flow_that_navigated_no_surface_is_inconclusive_not_green
    result = live_run(Deploy::MobileFlowGate, walk: { "error" => "Timeout: navigate" }) { |_js, _| nil }

    assert_inconclusive result, %r{navigated 0/1 surfaces}
  end
end
