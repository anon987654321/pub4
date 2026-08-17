# frozen_string_literal: true

require "test_helper"

# The table exists to say which of seven city domains anyone reaches. Every test
# here is about it staying a counter — one row per host per day — because the
# moment it becomes a row per request it is both a write-volume problem on
# SQLite and a record of what each visitor looked at.
class VisitCountTest < ActiveSupport::TestCase
  setup { Shared::VisitCount.delete_all }

  def record(host: "oshlo.no", route: "home#index", day: Date.current)
    Shared::VisitCount.record(app: "app", host: host, route: route, day: day)
  end

  test "a second view of the same page on the same day increments rather than inserts" do
    record
    record
    record

    assert_equal 1, Shared::VisitCount.count
    assert_equal 3, Shared::VisitCount.sole.count
  end

  test "each host counts separately" do
    record(host: "oshlo.no")
    record(host: "brgen.no")
    record(host: "brgen.no")

    assert_equal({ "brgen.no" => 2, "oshlo.no" => 1 }, Shared::VisitCount.by_host)
  end

  test "a new day starts a new row so the series is readable" do
    record(day: Date.current - 1)
    record(day: Date.current)

    assert_equal 2, Shared::VisitCount.count
    assert_equal 2, Shared::VisitCount.total
  end

  # www.oshlo.no and oshlo.no are the same city, and splitting them would split
  # the number the whole table exists to report.
  test "host is normalised so a www prefix does not split the count" do
    record(host: "WWW.Oshlo.no")
    record(host: "oshlo.no")

    assert_equal({ "oshlo.no" => 2 }, Shared::VisitCount.by_host)
  end

  test "routes are counted per host and ranked" do
    record(route: "home#index")
    record(route: "home#index")
    record(route: "posts#show")

    assert_equal({ "home#index" => 2, "posts#show" => 1 }, Shared::VisitCount.by_route(host: "oshlo.no"))
    assert_empty Shared::VisitCount.by_route(host: "brgen.no")
  end

  test "an incomplete record is refused rather than counted against a blank host" do
    assert_nil Shared::VisitCount.record(app: "app", host: "", route: "home#index")
    assert_nil Shared::VisitCount.record(app: "app", host: "oshlo.no", route: "")
    assert_nil Shared::VisitCount.record(app: "", host: "oshlo.no", route: "home#index")

    assert_equal 0, Shared::VisitCount.count
  end

  # "Which city has traffic" must not answer "the one the crawlers like".
  test "obvious crawlers are recognised, and a real browser is not" do
    %w[
      Googlebot/2.1
      Mozilla/5.0\ (compatible;\ bingbot/2.0)
      curl/8.4.0
      HeadlessChrome/120
    ].each { |ua| assert Shared::VisitCount.bot?(ua), "#{ua} should be a bot" }

    assert Shared::VisitCount.bot?(nil), "a missing user agent is not a person"
    assert Shared::VisitCount.bot?("")
    refute Shared::VisitCount.bot?(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
    )
  end

  test "the report window excludes days before it" do
    record(day: Date.current - 40)
    record(day: Date.current)

    assert_equal 1, Shared::VisitCount.total(since: 30.days.ago.to_date)
    assert_equal 2, Shared::VisitCount.total(since: 60.days.ago.to_date)
  end
end
