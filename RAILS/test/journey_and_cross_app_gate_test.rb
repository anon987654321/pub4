# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/method_swap"
require_relative "../gates/lib/rendered/journey_invariant"
require_relative "../gates/lib/rendered/cross_app"

# Two browser-backed gates whose findings are decided in Ruby, not in Chrome.
# journey_invariant compares two walks of the same surface; cross_app compares
# one chrome payload per app. Both comparisons take plain hashes, so both can be
# handed a defect on a machine with no browser and no fleet.
#
# The two tests named "without_chrome" are the ones worth the most. Off the
# deploy host these gates measure nothing, and a gate that measured nothing and
# reported ok is the exact false green the third state was added to close.
class JourneyAndCrossAppGateTest < Minitest::Test
  include MethodSwap

  J = Deploy::JourneyInvariantGate
  C = Deploy::CrossAppEquivalenceGate
  P = Deploy::GeometryProbe

  def surface(app: "brgen", path: "/", port: 38182)
    P::Surface.new(app: app, label: "core", host: "#{app}.test", path: path,
                   viewport: "mobile", width: 390, height: 844, port: port)
  end

  # One walk payload. Defects are planted by changing a field of the second.
  def walk(title: "Brgen", h1: 1, landmarks: { "main" => true, "nav" => true }, elements: [])
    { "title" => title, "h1_count" => h1, "scroll_width" => 390,
      "landmarks" => landmarks, "elements" => elements, "status" => 200 }
  end

  def element(key, width: 100, height: 44)
    { "key" => key, "visible" => true, "onscreen" => true, "rect" => { "w" => width, "h" => height } }
  end

  def diff(a, b) = J.new.send(:structural_diff, a, b)

  def assert_names(result, pattern)
    assert result.failures.any? { |f| f.match?(pattern) },
           "no failure matched #{pattern.inspect}; got:\n  #{result.failures.join("\n  ")}"
  end

  def test_journey_invariant_without_chrome_is_inconclusive_and_never_passes
    result = swap_value(P, :available?, false) { J.run }

    assert_equal :inconclusive, result.outcome
    assert_equal 0, result.checks_ran
    assert_empty result.failures
    assert_match(/no Chrome/i, result.unchecked.join(" "))
  end

  # Chrome present, nothing listening. Still nothing measured, and the reason
  # the runner prints has to say which of the two it was.
  def test_journey_invariant_with_no_app_reachable_is_inconclusive
    result = swap_value(P, :available?, true) do
      swap_value(P, :surfaces, []) { J.run }
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/no app reachable/, result.unchecked.join(" "))
  end

  def test_two_identical_walks_of_one_surface_produce_no_finding
    assert_empty diff(walk(elements: [element("main>h1")]), walk(elements: [element("main>h1")]))
  end

  # Idempotence. A surface that lays out differently on two consecutive loads
  # makes every other visual assertion on it flaky, which is why this runs first.
  def test_a_box_that_changes_width_between_two_loads_is_named_with_both_values
    found = diff(walk(elements: [element("main>button", width: 92)]),
                 walk(elements: [element("main>button", width: 101)]))

    assert_includes found, "main>button w 92→101"
  end

  def test_a_title_that_changes_between_two_loads_is_a_finding
    assert_includes diff(walk(title: "Brgen"), walk(title: "Bergen")), "title \"Brgen\"→\"Bergen\""
  end

  def test_a_landmark_that_disappears_between_two_loads_is_a_finding
    found = diff(walk, walk(landmarks: { "main" => true, "nav" => false }))

    assert_includes found, "landmark nav true→false"
  end

  def test_an_element_that_vanishes_between_two_loads_is_a_finding
    found = diff(walk(elements: [element("main>h1"), element("main>nav")]), walk(elements: [element("main>h1")]))

    assert_includes found, "vanished: main>nav"
  end

  def test_a_second_competing_h1_between_two_loads_is_a_finding
    assert_includes diff(walk(h1: 1), walk(h1: 2)), "h1_count 1→2"
  end

  # A live feed legitimately differs between two loads. Reporting that would
  # make the gate a false-positive factory and teach people to skip it.
  def test_a_volatile_feed_card_changing_size_is_not_a_finding
    found = diff(walk(elements: [element("main>div.feed-card", width: 300)]),
                 walk(elements: [element("main>div.feed-card", width: 340)]))

    assert_empty found
  end

  # Sub-pixel movement is rounding. Two pixels is the declared tolerance.
  def test_a_two_pixel_difference_is_below_the_tolerance
    assert_empty diff(walk(elements: [element("main>p", width: 100)]),
                      walk(elements: [element("main>p", width: 102)]))
  end

  # progressive_enhancement, measured rather than grepped for the string
  # "jquery": the server HTML has to carry the landmarks before any script runs.
  def test_server_html_without_a_main_landmark_fails_no_js_parity
    body = "<html><body><div class='nav'>x</div><a href='#main-content'>skip</a></body></html>"
    result = no_js_verdict(body)

    assert_names result, /no_js: brgen server HTML has no main landmark/
    assert_names result, /progressive_enhancement/
  end

  def test_server_html_without_a_skip_link_fails_no_js_parity
    body = "<html><body><nav></nav><main></main></body></html>"

    assert_names no_js_verdict(body), /no_js: brgen server HTML has no skip landmark/
  end

  def test_server_html_carrying_every_landmark_passes_no_js_parity
    body = "<html><body><a class='skip-link' href='#main-content'>x</a><nav></nav><main id='main-content'></main></body></html>"

    assert_empty no_js_verdict(body).failures
  end

  def no_js_verdict(body)
    gate = J.new
    result = Deploy::GateResult.new
    gate.instance_variable_set(:@result, result)
    response = Struct.new(:body).new(body)
    swap_value(CrawlSupport, :fetch, response) { gate.send(:check_no_js_parity, [surface]) }
    result
  end

  def test_cross_app_without_chrome_is_inconclusive_and_never_passes
    result = swap_value(Deploy::GeometryProbe, :available?, false) { C.run }

    assert_equal :inconclusive, result.outcome
    assert_equal 0, result.checks_ran
    assert_empty result.failures
    assert_match(/no Chrome/i, result.unchecked.join(" "))
  end

  # One app is not a comparison. The gate must say so rather than compare a
  # thing to itself and report agreement.
  def test_cross_app_with_fewer_than_two_apps_running_is_inconclusive
    result = swap_value(Deploy::GeometryProbe, :available?, true) do
      swap_value(Deploy::GeometryProbe, :surfaces, [surface]) do
        swap_value(Deploy::GeometryProbe, :reachable, [surface]) do
          swap_value(Deploy::GeometryProbe, :unreachable_apps, []) { C.run }
        end
      end
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/at least two apps/, result.unchecked.join(" "))
  end

  # One chrome payload per app. Every field here comes from shared/frontend.
  def chrome(main_id: "main-content", skip: "#main-content", footer: true, controllers: %w[nav theme])
    { "skip_href" => skip, "skip_text" => "Hopp til innhold", "main_id" => main_id,
      "main_tag" => "main", "nav_aria" => "Hoved", "has_footer" => footer,
      "lang" => "nb", "viewport_meta" => "width=device-width", "controllers" => controllers }
  end

  def compare(payloads)
    result = Deploy::GateResult.new
    gate = C.new
    gate.instance_variable_set(:@result, result)
    gate.send(:compare_chrome, payloads)
    result
  end

  def test_three_apps_rendering_the_same_shared_chrome_pass
    assert_empty compare("brgen" => chrome, "amber" => chrome, "bsdports" => chrome).failures
  end

  # The divergence this gate exists for: per-app copies of shared markup drifted
  # once already, and nothing prevented it returning.
  def test_an_app_whose_main_landmark_id_drifts_fails_and_names_both_values
    result = compare("brgen" => chrome, "amber" => chrome(main_id: "content"))

    assert_names result, /the shared main landmark id differs between apps/
    assert_names result, /amber="content"/
  end

  def test_an_app_whose_skip_link_target_drifts_fails
    result = compare("brgen" => chrome, "amber" => chrome(skip: "#content"))

    assert_names result, /the shared skip link target differs between apps/
  end

  def test_an_app_rendering_no_skip_link_at_all_fails
    result = compare("brgen" => chrome, "amber" => chrome(skip: nil))

    assert_names result, /amber render no skip link at all/
    assert_names result, /accessibility/
  end

  # A footer missing everywhere is a design decision; missing in one app is the
  # shared partial failing to reach it.
  def test_a_footer_reaching_two_apps_of_three_is_a_soft_finding
    result = compare("brgen" => chrome, "amber" => chrome, "bsdports" => chrome(footer: false))

    assert result.soft_failures.any? { |f| f.match?(/shared footer partial is not reaching every app/) },
           "expected a soft finding; got #{result.soft_failures.inspect}"
  end

  def test_no_app_rendering_a_footer_is_not_a_finding
    result = compare("brgen" => chrome(footer: false), "amber" => chrome(footer: false))

    assert_empty result.failures
    assert_empty result.soft_failures
  end

  def controllers_verdict(payloads, layout_mounts)
    result = Deploy::GateResult.new
    gate = C.new
    gate.instance_variable_set(:@result, result)
    swap(gate, :layout_controller_names, -> { layout_mounts }) do
      swap(gate, :shared_controller_names, -> { layout_mounts }) do
        gate.send(:compare_controllers, payloads)
      end
    end
    result
  end

  # A controller the shared layout mounts renders in every app, necessarily. One
  # app missing it is drift in code all three render.
  def test_a_layout_mounted_controller_missing_from_one_app_is_a_soft_finding
    result = controllers_verdict({ "brgen" => chrome, "amber" => chrome(controllers: %w[nav]) }, %w[nav theme])

    assert result.soft_failures.any? { |f| f.match?(/"theme" is mounted by the shared layout but renders only in brgen/) },
           "expected a soft finding; got #{result.soft_failures.inspect}"
  end

  # bsdports has no feed, so a shared controller it never mounts is not drift.
  # Asserting otherwise is the false-positive factory the gate's comment names.
  def test_a_shared_controller_no_app_mounts_is_an_inventory_warning_not_a_finding
    result = controllers_verdict({ "brgen" => chrome, "amber" => chrome }, %w[nav theme feed-compose])

    assert_empty result.failures
    assert_empty result.soft_failures
    assert result.warnings.any? { |w| w.include?("feed-compose") }, result.warnings.inspect
  end
end
