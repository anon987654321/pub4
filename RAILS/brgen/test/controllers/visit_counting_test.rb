# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A counter that is never called is worse than no counter: it reports zero, and
# zero reads as "nobody visits" rather than "nothing is counting". These pin
# that Shared::VisitCounting is actually reached from ApplicationController, and
# that it counts page views rather than traffic.
class VisitCountingTest < ActionDispatch::IntegrationTest
  # A real browser always sends one; the integration harness does not, and
  # VisitCount.bot? treats a missing user agent as a non-person. That is the
  # right call in production — a request with no user agent is a script — so the
  # test supplies one rather than the filter being loosened to accommodate it.
  # Current Chrome, because ApplicationController also runs `allow_browser
  # versions: :modern` — Safari 17.0 is under that floor and gets a 406 before
  # the counter is ever reached, which looks like the counter failing.
  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

  setup { Shared::VisitCount.delete_all }

  def browse(url, headers: {})
    get url, headers: { "HTTP_USER_AGENT" => BROWSER }.merge(headers)
  end

  def test_a_page_view_is_counted_against_the_host_it_was_served_for
    browse "http://oshlo.no/"

    assert_response :success
    assert_equal({ "oshlo.no" => 1 }, Shared::VisitCount.by_host)
    assert_equal "home#index", Shared::VisitCount.sole.route
  end

  # The whole point: brgen serves seven city domains from one app, and the
  # counter has to tell them apart.
  # Absolute URLs throughout, never host! plus root_url. host! sets the default
  # for url helpers only, so root_url could resolve against a host an earlier
  # test had set: in isolation these passed, and in the full suite a request
  # meant for oshlo.no arrived at brgen.no. A test about telling seven domains
  # apart must not itself be ambiguous about which one it asked for.
  def test_each_city_domain_accumulates_separately
    browse "http://oshlo.no/"
    browse "http://brgen.no/"
    browse "http://brgen.no/"

    assert_equal({ "brgen.no" => 2, "oshlo.no" => 1 }, Shared::VisitCount.by_host)
  end

  # Route, not path — otherwise the table grows one row per listing per day and
  # becomes a record of what each visitor looked at.
  def test_repeat_views_share_one_row
    3.times { browse "http://brgen.no/" }

    assert_equal 1, Shared::VisitCount.count
    assert_equal 3, Shared::VisitCount.sole.count
  end

  def test_a_crawler_is_not_counted_as_a_visit
    browse "http://brgen.no/", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (compatible; Googlebot/2.1)" }

    assert_response :success
    assert_equal 0, Shared::VisitCount.count
  end

  def test_a_non_html_response_is_traffic_but_not_a_page_view
    browse "http://brgen.no/", headers: { "Accept" => "application/json" }

    assert_equal 0, Shared::VisitCount.count, "only successful HTML GETs are page views"
  end

  # A counter must never be able to take the page down with it.
  #
  # Scoped, not a singleton_class.prepend — that version is permanent, so with a
  # randomised seed every test that ran after it got the raising `record` and
  # counted nothing. The failure looked exactly like the concern not firing.
  def test_a_failing_counter_does_not_fail_the_request
    Shared::VisitCount.stub(:record, ->(*, **) { raise "counter exploded" }) do
      browse "http://brgen.no/"

      assert_response :success
    end

    assert_equal 0, Shared::VisitCount.count
  end
end
