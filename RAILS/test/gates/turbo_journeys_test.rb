# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../MASTER/gates/support/turbo_journeys"

# The journeys journey_invariant walks in Chrome, judged on planted answers: the
# scripts run only on the deploy host, and the verdicts are where a defect is
# either named or let through.
class TurboJourneysTest < Minitest::Test
  J = Deploy::TurboJourneys

  def verdict(method, answer)
    result = Deploy::GateResult.new
    measured = J.public_send(method, "brgen/core", answer, result)
    [measured, result]
  end

  def said(result) = (result.failures + result.soft_failures).join(" | ")

  FRAME = { "found" => true, "href" => "/channels/bergen", "frame" => "messenger-pane", "outcome" => "load",
            "same_document" => true, "connected" => true, "missing" => false, "advance" => false,
            "url_changed" => false, "lazy" => [] }.freeze

  def test_a_frame_link_that_swaps_its_frame_passes_and_counts
    measured, result = verdict(:judge_frame, FRAME)

    assert measured
    assert_equal "", said(result)
  end

  def test_a_frame_answer_without_the_frame_is_a_hard_failure
    _, result = verdict(:judge_frame, FRAME.merge("outcome" => "missing"))

    assert_match(/showed "Content missing".*no #messenger-pane/, result.failures.join)
  end

  def test_a_lazy_frame_that_loaded_content_missing_is_named_without_a_click
    _, result = verdict(:judge_frame, { "found" => false, "lazy" => [{ "id" => "feed", "missing" => true }] })

    assert_match(/lazy frame #feed loaded "Content missing"/, result.failures.join)
  end

  def test_a_frame_link_that_reloads_the_page_is_named
    _, result = verdict(:judge_frame, { "error" => "Execution context was destroyed." })

    assert_match(/frame link replaced the page/, result.soft_failures.join)
  end

  def test_an_advancing_frame_that_leaves_the_url_behind_is_named
    _, result = verdict(:judge_frame, FRAME.merge("advance" => true))

    assert_match(/data-turbo-action=advance/, result.soft_failures.join)
  end

  FOCUS = { "found" => true, "href" => "/nearby", "outcome" => "load", "same_document" => true,
            "body" => false, "connected" => true, "painted" => true, "sel" => "a.nav_link" }.freeze

  def test_focus_on_a_painted_permanent_link_or_the_body_passes
    assert_equal "", said(verdict(:judge_focus, FOCUS).last)
    assert_equal "", said(verdict(:judge_focus, FOCUS.merge("body" => true, "painted" => false)).last)
  end

  def test_focus_left_on_a_detached_element_after_a_visit_is_named
    _, result = verdict(:judge_focus, FOCUS.merge("connected" => false, "painted" => false))

    assert_match(/focus sits on a\.nav_link, which is detached/, result.soft_failures.join)
  end

  def test_a_nav_link_that_does_a_full_load_is_not_judged
    measured, result = verdict(:judge_focus, { "error" => "Execution context was destroyed." })

    refute measured
    assert_equal "", said(result)
  end

  RECONNECT = { "found" => true, "scrollable" => true, "before" => 400, "reconnected" => 400,
                "arrived" => 401, "pill" => true, "tail_gap" => 0, "pill_left" => false }.freeze

  def test_a_log_that_holds_the_reader_and_offers_jump_to_newest_passes
    measured, result = verdict(:judge_reconnect, RECONNECT)

    assert measured
    assert_equal "", said(result)
  end

  def test_a_reconnect_that_yanks_the_reader_to_the_tail_is_named
    _, result = verdict(:judge_reconnect, RECONNECT.merge("reconnected" => 900, "arrived" => 900))

    assert_match(/reconnect moved a scrolled-back reader 500px/, result.soft_failures.join)
  end

  def test_a_line_arriving_with_no_jump_to_newest_is_named
    _, result = verdict(:judge_reconnect, RECONNECT.merge("pill" => false))

    assert_match(/no jump-to-newest appeared/, result.soft_failures.join)
  end

  def test_a_jump_to_newest_that_stops_short_is_named
    _, result = verdict(:judge_reconnect, RECONNECT.merge("tail_gap" => 300))

    assert_match(/left the reader 300px above the newest line/, result.soft_failures.join)
  end

  def test_a_log_that_does_not_scroll_is_not_measured
    measured, result = verdict(:judge_reconnect, { "found" => true, "scrollable" => false })

    refute measured
    assert_match(/not measured/, result.warnings.join)
  end

  def pager(html, status: 200)
    result = Deploy::GateResult.new
    followed = []
    measured = J.judge_pager("brgen/events", html, result, follow: ->(href) { followed << href; status })
    [measured, result, followed]
  end

  SENTINEL = %(<div class="infinite-scroll-sentinel" data-next-page="2"></div>)
  NEXT = %(<a class="pager-link" rel="next" href="/events?page=2&amp;sort=new">)

  def test_infinite_scroll_without_a_rel_next_link_is_named
    _, result, = pager("<main>#{SENTINEL}</main>")

    assert_match(/without JavaScript the list ends at page one/, result.soft_failures.join)
  end

  def test_the_next_page_link_is_followed_unescaped_and_must_answer
    measured, result, followed = pager("<main>#{SENTINEL}#{NEXT}</main>", status: 500)

    assert measured
    assert_equal ["/events?page=2&sort=new"], followed
    assert_match(/rel=next .* answers 500/, result.failures.join)
  end

  def test_a_page_with_a_working_pager_or_no_list_passes
    assert_equal "", said(pager("<main>#{SENTINEL}#{NEXT}</main>")[1])
    assert_equal "", said(pager("<main></main>")[1])
  end
end
