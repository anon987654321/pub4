# frozen_string_literal: true

require "test_helper"

# SearchRecent: one row per (user, query), a repeat search moves the row to
# the top instead of accumulating, and guests/blank queries record nothing.
class SearchRecentTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @reader = User.strict_loading(false).create!(email_address: "searcher@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "recording the same query twice keeps one row and moves it to the top" do
    SearchRecent.record!(@reader, "bike repair")
    SearchRecent.record!(@reader, "sofa")
    later = SearchRecent.record!(@reader, "bike repair")

    assert_equal 2, SearchRecent.where(user: @reader).count
    assert_equal "bike repair", later.query
    assert_equal [ "bike repair", "sofa" ], SearchRecent.recent_for(@reader).pluck(:query)
  end

  test "queries are trimmed and stored verbatim enough to find again" do
    row = SearchRecent.record!(@reader, "  Vintage  Glerárskóli lamp  ")

    assert_equal "Vintage  Glerárskóli lamp", row.query
  end

  test "guests, signed-out readers and blank queries record nothing" do
    guest = User.strict_loading(false).create!(email_address: "guest-search@brgen.no", password: "password123", city: @city, guest: true)

    assert_nil SearchRecent.record!(guest, "bike repair")
    assert_nil SearchRecent.record!(nil, "bike repair")
    assert_nil SearchRecent.record!(@reader, "   ")
    assert_equal 0, SearchRecent.count
  end

  test "recent_for is capped and ordered newest first" do
    7.times { |n| SearchRecent.record!(@reader, "query #{n}") }
    newest = SearchRecent.record!(@reader, "the newest one")

    shown = SearchRecent.recent_for(@reader).to_a
    assert_equal SearchRecent::SHOWN_LIMIT, shown.length
    assert_equal newest.id, shown.first.id
  end
end
