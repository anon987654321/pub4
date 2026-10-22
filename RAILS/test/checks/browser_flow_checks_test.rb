# frozen_string_literal: true

require "minitest/autorun"
require_relative "check_probe_harness"
require_relative "../../../MASTER/checks/lib/rendered/occlusion"
require_relative "../../../MASTER/checks/lib/rendered/reflow"
require_relative "../../../MASTER/checks/lib/rendered/keyboard_flow"
require_relative "../../../MASTER/checks/lib/rendered/mobile_flow"

# The four browser-backed journey checks, proved on planted measurements.
#
# One file because the four share one shape and one harness. Each needs Chrome
# and a listening app, so on this machine each one's own `.run` returns after the
# precondition check — which is why a test that calls `.run` against the real tree
# and asserts "passes" proves nothing: it passes equally against `return ok`.
#
# So each check is asked three questions. Given a measurement carrying a defect,
# does it name the defect? Given a clean one, does it pass? And given no browser
# or no listening app, does it say it measured nothing — rather than reporting the
# green that this whole family of checks exists to prevent?
#
# The third question has teeth beyond the precondition check. occlusion, reflow
# and keyboard_flow each counted the surfaces they *attempted*, and a navigation
# timeout is a warning in all three, so a run where Chrome opened and every page
# timed out reported PASSED having pressed, swept and walked nothing. Those cases
# are the last test of each group.
class BrowserFlowChecksTest < Minitest::Test
  include CheckProbe

  PROBE = Deploy::GeometryProbe

  # keyboard_flow picks desktop surfaces and the other three pick mobile ones, so
  # the viewport is part of what each check is handed.
  def surface(app: "brgen", label: "core", path: "/", viewport: "mobile")
    PROBE::Surface.new(app: app, label: label, host: nil, path: path, viewport: viewport,
                       width: 390, height: 844, snapshot: false, port: 38_182)
  end

  # Everything a rendered check reaches the browser through, answered from here.
  # `answer` receives the JavaScript the check chose to evaluate, so a check that
  # stops asking its own question gets nil rather than a convenient fixture.
  def live_run(check, surfaces: [surface], walk: { "status" => 200 }, method: :run, &answer)
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
    ) { check.public_send(method) }
  end

  def dark_run(check, method: :run)
    with_methods(PROBE, available?: proc { false }) { check.public_send(method) }
  end

  def parked_run(check, method: :run, viewport: "mobile")
    rows = [surface(viewport: viewport)]
    with_methods(
      PROBE,
      available?: proc { true },
      surfaces: proc { |*, **| rows },
      unreachable_apps: proc { |*, **| ["brgen"] },
      reachable: proc { |*, **| [] }
    ) { check.public_send(method) }
  end

  # occlusion — does a press at this control's centre reach this control?

  OCCLUDED = [{ "control" => "a.nav_link", "label" => "Hjem", "covered_by" => "div.theme_toggle",
                "at" => [100, 200], "size" => [40, 40] }].freeze

  def test_occlusion_names_the_control_a_press_misses
    result = live_run(Deploy::OcclusionCheck) { |_js, _| OCCLUDED }

    assert_names_defect(result, /a\.nav_link .*covered by div\.theme_toggle at 100,200/)
  end

  def test_occlusion_passes_when_every_control_answers_its_own_press
    assert_clean live_run(Deploy::OcclusionCheck) { |_js, _| [] }
  end

  def test_occlusion_without_chrome_presses_nothing_and_says_so
    assert_inconclusive dark_run(Deploy::OcclusionCheck), /no Chrome/
  end

  def test_occlusion_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::OcclusionCheck), /no app reachable/
  end

  # A timeout is a warning, not a failure, so a run of nothing but timeouts has
  # an empty failure list and used to read as a pass.
  def test_occlusion_that_reached_no_surface_is_inconclusive_not_green
    result = live_run(Deploy::OcclusionCheck, walk: { "error" => "Timeout: navigate" }) { |_js, _| [] }

    assert_inconclusive result, %r{reached 0/1 surface}
  end

  # reflow — the width sweep. run_once, because `run` wraps the measurement in
  # CheckAutofix's remeasure loop, which writes to the stylesheets.

  def reflow_sample(scroll_width:, offenders: [])
    { "scroll_width" => scroll_width, "client_width" => 390, "columns" => 2, "tab_bar" => true,
      "sidebar" => false, "main_width" => 360, "offenders" => offenders }
  end

  def reflow_run(sample)
    with_methods(PROBE, reflow_widths: proc { |*, **| [320, 390] }) do
      live_run(Deploy::ReflowCheck, method: :run_once) do |js, _|
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

  # One sample per swept width, in sweep order, so the reading type can move.
  def reflow_type_run(*type)
    queue = type.map do |size, line_height, reading = "p.lede"|
      reflow_sample(scroll_width: 390).merge(typeset(size, line_height, reading: reading))
    end
    with_methods(PROBE, reflow_widths: proc { |*, **| [320, 390, 768, 1440].first(queue.size) }) do
      live_run(Deploy::ReflowCheck, method: :run_once) { |js, _| js.include?("document.fonts") ? true : queue.shift }
    end
  end

  def typeset(size, line_height, reading: "p.lede")
    { "reading" => reading, "reading_size" => size, "reading_line_height" => line_height }
  end

  def reading_type_findings(result) = result.soft_failures.grep(/reflow type:/)

  def test_reflow_names_reading_type_that_shrinks_as_the_viewport_widens
    found = reading_type_findings(reflow_type_run([18.0, 27.0], [16.0, 24.0]))

    assert_match(/p\.lede gets smaller as the viewport widens — 18\.0px at 320 → 16\.0px at 390/, found.join)
  end

  # Fluid type under a px line height: each step is a fraction of a pixel, so only the narrowest width shows it.
  def test_reflow_names_a_fixed_line_height_under_fluid_type
    found = reading_type_findings(reflow_type_run([16.0, 24.0], [16.4, 24.0], [17.2, 24.0], [18.0, 24.0]))

    assert_match(/fixed line height while its size changes — 16\.0px at 320 → 17\.2px at 768 under 24\.0px/, found.join)
  end

  def test_reflow_passes_type_that_grows_with_its_leading
    assert_empty reading_type_findings(reflow_type_run([16.0, 24.0], [16.4, 24.6], [17.2, 25.8], [18.0, 27.0]))
  end

  # A paragraph hidden at one width leaves the body to be measured, and the body is not the paragraph.
  def test_reflow_compares_reading_type_only_on_the_same_element
    assert_empty reading_type_findings(reflow_type_run([18.0, 27.0], [16.0, 24.0, "body"]))
  end

  def test_reflow_without_chrome_sweeps_nothing_and_says_so
    assert_inconclusive dark_run(Deploy::ReflowCheck, method: :run_once), /no Chrome/
  end

  def test_reflow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::ReflowCheck, method: :run_once), /no app reachable/
  end

  def test_reflow_whose_every_width_raised_is_inconclusive_not_green
    result = with_methods(PROBE, reflow_widths: proc { |*, **| [320, 390] }) do
      live_run(Deploy::ReflowCheck, method: :run_once) do |js, _|
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
    live_run(Deploy::KeyboardFlowCheck, surfaces: [surface(viewport: "desktop")]) do |js, _|
      next true if js.include?("document.body.setAttribute")

      queue.shift
    end
  end

  def test_keyboard_flow_focus_probe_counts_visible_pseudo_element_rings
    probe = Deploy::KeyboardFlowCheck::ACTIVE

    assert_includes probe, "getComputedStyle(el, pseudo)"
    assert_includes probe, "hasPseudoOutline"
    assert_includes probe, "hasPseudoShadow"
    assert_includes probe, "'pseudo-outline'"
    assert_includes probe, "'pseudo-box-shadow'"

    upload_css = File.read(File.join(Deploy::KeyboardFlowCheck::ROOT, "RAILS", "master", "public", "chat_upload.css"))
    assert_match(/#photo-button:focus-visible\s*\{\s*outline:\s*none;/m, upload_css)
    assert_match(/#photo-button:focus-visible::before\s*\{[^}]*outline:\s*1px solid/m, upload_css)
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
    assert_inconclusive dark_run(Deploy::KeyboardFlowCheck), /no Chrome/
  end

  def test_keyboard_flow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::KeyboardFlowCheck, viewport: "desktop"), /no app reachable/
  end

  # An autofocus field that will not give focus back makes the walk start
  # mid-document, which reads as a misplaced skip link. The check declines to
  # measure — and when that is every surface, it has walked nothing.
  def test_keyboard_flow_that_never_released_focus_is_inconclusive_not_green
    result = live_run(Deploy::KeyboardFlowCheck, surfaces: [surface(viewport: "desktop")]) do |js, _|
      js.include?("document.body.setAttribute") ? false : nil
    end

    assert_inconclusive result, /would not release focus/
  end

  # The walk itself — Chrome answers a refused connection with a page of its own.

  def test_a_chrome_error_page_is_not_a_measurement
    cdp = FakeCdp.new { |js, _| js.include?("chrome-error:") }
    payload = PROBE.walk(cdp, surface)

    assert_match(/chrome error page/, payload["error"])
    refute PROBE.ok?(payload), "a page nothing answered must not read as measured"
  end

  # keyboard_flow states — pressed, disabled and busy, each read off the page.

  STATE_ROW = { "sel" => "button.send", "rest" => "rest", "active" => "pressed",
                "disabled" => "greyed", "busy" => "working" }.freeze

  def states_verdict(rows)
    Deploy::KeyboardFlowCheck.new.judge_states("brgen/core", rows, result: Deploy::CheckResult.new)
  end

  def test_keyboard_flow_names_a_control_that_paints_no_pressed_state
    result = states_verdict([STATE_ROW.merge("active" => "rest")])

    assert_match(/1\/1 controls paint no active state.*button\.send/, result.soft_failures.join(" | "))
  end

  def test_keyboard_flow_names_a_disabled_control_that_looks_enabled_and_a_busy_one_that_looks_idle
    result = states_verdict([STATE_ROW.merge("disabled" => "rest", "busy" => "rest")])

    assert_match(/paint no disabled state/, result.soft_failures.join(" | "))
    assert_match(/paint no busy state/, result.soft_failures.join(" | "))
  end

  def test_keyboard_flow_passes_controls_that_paint_every_state_and_leaves_unread_states_out
    assert_empty states_verdict([STATE_ROW, STATE_ROW.merge("active" => nil)]).soft_failures
  end

  # The pressed state can only come from CDP, so the read has to force it, paint,
  # and release it; a read that skips the force would score :active as rest.
  def test_keyboard_flow_forces_active_over_cdp_and_releases_it
    fake = nil
    fake = FakeCdp.new do |js, _|
      next ["button.send"] if js.include?("data-check-state', String(index)")

      mutation = js[/const mutation = '(\w+)'/, 1]
      pressed = fake.forced.last&.last == ["active"]
      pressed ? "pressed" : { "disabled" => "greyed", "busy" => "working" }.fetch(mutation, "rest")
    end
    rows = Deploy::KeyboardFlowCheck.new.send(:read_states, fake)

    assert_equal [STATE_ROW], rows
    assert_equal [[%([data-check-state="0"]), ["active"]], [%([data-check-state="0"]), []]], fake.forced
  end

  # mobile_flow — the phone journey floor at 390x844.

  def mobile_measure(has_main: true, has_skip: true, overflow: false, chrome: [])
    { "has_main" => has_main, "has_skip" => has_skip, "has_tab_bar" => true, "overflow" => overflow,
      "scroll_width" => overflow ? 500 : 390, "client_width" => 390, "chrome" => chrome,
      "title" => "Bergen" }
  end

  def mobile_run(measure)
    live_run(Deploy::MobileFlowCheck) { |_js, _| measure }
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
    assert_inconclusive dark_run(Deploy::MobileFlowCheck), /no Chrome/
  end

  def test_mobile_flow_with_every_app_parked_reports_nothing_reachable
    assert_inconclusive parked_run(Deploy::MobileFlowCheck), /no app reachable/
  end

  def test_mobile_flow_that_navigated_no_surface_is_inconclusive_not_green
    result = live_run(Deploy::MobileFlowCheck, walk: { "error" => "Timeout: navigate" }) { |_js, _| nil }

    assert_inconclusive result, %r{navigated 0/1 surfaces}
  end

  # One threshold for all four: a session that drops out part way is not a
  # floor that held, and a run with fewer reachable surfaces measures them all.
  def test_too_few_measured_is_one_line_for_the_four_checks
    assert Deploy::GeometryProbe.too_few_measured?(2, 8)
    refute Deploy::GeometryProbe.too_few_measured?(3, 8)
    assert Deploy::GeometryProbe.too_few_measured?(1, 2)
    refute Deploy::GeometryProbe.too_few_measured?(2, 2)
  end
end
