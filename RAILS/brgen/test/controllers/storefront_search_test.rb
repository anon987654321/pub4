# frozen_string_literal: true

require "test_helper"

# markedsplass and takeaway carried two search fields with one placeholder: the
# header's did a full page load, and the page's streamed results below the fold.
# One field now, the header's, streaming into the page.
class StorefrontSearchTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "ss_seller@brgen.no", password: "password123", username: "ss_seller", guest: false, city: @city
    )
    @bikes = Marketplace::Category.create!(name: "Sykler", slug: "sykler-#{SecureRandom.hex(4)}")
    @bike = Marketplace::Listing.create!(user: @seller, category: @bikes, title: "Racersykkel #{SecureRandom.hex(2)}",
                                         price_cents: 90_000)
    @restaurant = Takeaway::Restaurant.create!(
      user: @seller, name: "Suppekjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  # The search palette keeps a field of its own over every page, so the count
  # is taken inside <main>.
  def page_search_fields = css_select("main input[type=search]")

  def header_form = css_select("#navBar form##{StorefrontSearch::FORM}").first

  test "the listings page has one search field, the header's, and it streams" do
    host! "markedsplass.brgen.no"
    get marketplace.listings_path(kind: "goods")

    assert_response :success
    assert_equal 1, page_search_fields.size
    assert_equal I18n.t("search.marketplace"), page_search_fields.first["placeholder"]
    assert header_form, "the field sits in the storefront header"
    assert_equal "live-search", header_form["data-controller"]
    assert_equal "true", header_form["data-turbo-stream"]
    assert_equal 1, css_select("##{StorefrontSearch::RESULTS}").size
  end

  test "the filter drawer joins the header form and the header carries the kind" do
    host! "markedsplass.brgen.no"
    get marketplace.listings_path(kind: "job")

    assert_equal StorefrontSearch::FORM, css_select("select[name=category_id]").first["form"]
    assert_equal StorefrontSearch::FORM, css_select("select[name=sort]").first["form"]
    assert_equal StorefrontSearch::FORM, css_select("input[name=min_price]").first["form"]
    assert_equal "job", css_select("##{StorefrontSearch::FORM} input[type=hidden][name=kind]").first["value"]
    # geolocation#pin fills these through the button's form, so they are
    # rendered with no value rather than left out.
    assert_equal 1, css_select("##{StorefrontSearch::FORM} input[type=hidden][name=lat]").size
  end

  # update keeps the region's id for the next keystroke, and the named target
  # stays clear of the search palette's #live_search_results, which comes first
  # in the document.
  test "a search streams into the storefront region, not the palette's" do
    host! "markedsplass.brgen.no"
    get marketplace.listings_path(q: "Racersykkel", kind: "goods"), headers: STREAM

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(<turbo-stream action="update" target="#{StorefrontSearch::RESULTS}">)
    assert_includes response.body, %(<turbo-stream action="update" target="#{StorefrontSearch::SUGGESTIONS}">)
    assert_includes response.body, @bike.title
  end

  test "takeaway has one search field and streams the same way" do
    host! "takeaway.brgen.no"
    get takeaway.restaurants_path

    assert_equal 1, page_search_fields.size
    assert_equal I18n.t("search.restaurants"), page_search_fields.first["placeholder"]
    assert_equal "live-search", header_form["data-controller"]

    get takeaway.restaurants_path(q: "Suppekjøkkenet"), headers: STREAM
    assert_includes response.body, %(<turbo-stream action="update" target="#{StorefrontSearch::RESULTS}">)
    assert_includes response.body, @restaurant.name
  end

  test "deals and stores search from the header too" do
    host! "markedsplass.brgen.no"

    [ marketplace.deals_path, marketplace.shops_path(vertical: "groceries") ].each do |path|
      get path
      assert_equal 1, page_search_fields.size, path
      assert_equal "live-search", header_form["data-controller"], path
    end
    assert_equal "groceries", css_select("##{StorefrontSearch::FORM} input[name=vertical]").first["value"]
  end

  # A page that lists nothing to stream into keeps the plain GET, or typing on
  # a category page would stream at a region that is not there.
  test "a category page's header field is a plain search" do
    host! "markedsplass.brgen.no"
    get marketplace.category_path(@bikes)

    assert_response :success
    assert_equal 1, page_search_fields.size
    assert_nil header_form["data-controller"]
  end
end
