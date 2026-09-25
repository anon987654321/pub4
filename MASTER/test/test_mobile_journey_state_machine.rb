# frozen_string_literal: true

require "minitest/autorun"

class TestMobileJourneyStateMachine < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_cdp_exposes_real_history_navigation
    source = read("../RAILS/gates/support/cdp_session.rb")
    assert_includes source, 'send_cmd("Page.goBack")'
    assert_includes source, 'send_cmd("Page.goForward")'
  end

  def test_discovers_search_and_filter_states
    source = read("../RAILS/gates/support/mobile_journey_probe.rb")
    assert_includes source, "input[type='search']"
    assert_includes source, 'kind: "search"'
    assert_includes source, 'kind: "filter"'
  end

  def test_exercises_back_and_forward_without_submitting
    source = read("../RAILS/gates/support/mobile_journey_probe.rb")
    assert_includes source, "cdp.back"
    assert_includes source, "cdp.forward"
    refute_includes source, "el.form.submit()"
  end
end
