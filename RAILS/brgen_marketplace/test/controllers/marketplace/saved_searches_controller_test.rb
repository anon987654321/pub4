# frozen_string_literal: true

require "test_helper"

# Saved searches: an invalid search is refused with a message rather than a
# 500 from create!, alerts switch on and off from the list, and the run link
# carries the saved place, which the listings grid now narrows to.
class Marketplace::SavedSearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    @buyer = User.create!(email_address: "ss_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
  end

  def sign_in
    post session_path, params: { email_address: @buyer.email_address, password: "secret1234" }
  end

  test "an invalid search is refused with a message" do
    sign_in

    assert_no_difference -> { Marketplace::SavedSearch.count } do
      post marketplace.saved_searches_path, params: { saved_search: { name: "x" * 200, query: "sykkel" } }
    end
    assert_response :redirect
    assert flash[:alert].present?
  end

  test "alerts switch on and off from the saved list" do
    sign_in
    search = @buyer.marketplace_saved_searches.create!(query: "sykkel", notify: false)

    patch marketplace.saved_search_path(search), params: { notify: true }
    assert search.reload.notify?
    assert_equal I18n.t("flash.marketplace.alerts_on"), flash[:notice]

    patch marketplace.saved_search_path(search), params: { notify: false }
    refute search.reload.notify?
  end

  test "the list offers the toggle and runs the search in its place" do
    sign_in
    search = @buyer.marketplace_saved_searches.create!(query: "sykkel", location: "Sandviken", notify: true)

    get marketplace.saved_searches_path

    page = Nokogiri::HTML(response.body)
    toggle = page.at_css("form[action='#{marketplace.saved_search_path(search)}'] button[aria-pressed]")
    assert_equal "true", toggle["aria-pressed"]
    assert_equal I18n.t("marketplace.alerts_turn_off"), toggle.text.strip
    run = page.css("a").find { _1.text.strip == I18n.t("marketplace.run_search") }
    assert_includes run["href"], "location=Sandviken"
  end

  test "the listings grid narrows to the saved place" do
    seller = User.create!(email_address: "ss_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    category = Marketplace::Category.create!(name: "Probe", slug: "ss-#{SecureRandom.hex(4)}")
    here = Marketplace::Listing.create!(user: seller, category:, title: "Sykkel her", price_cents: 100, stock: 1,
                                        location: "Sandviken")
    there = Marketplace::Listing.create!(user: seller, category:, title: "Sykkel der", price_cents: 100, stock: 1,
                                         location: "Fana")

    get marketplace.listings_path(location: "Sandviken")

    grid = Nokogiri::HTML(response.body).at_css("div.deal-grid#marketplace-listings").text
    assert_includes grid, here.title
    refute_includes grid, there.title
  end
end
