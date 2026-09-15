# frozen_string_literal: true

require "test_helper"

# What a crawler reads about a record has to be what the record knows. These
# render the public pages and parse what they emit, rather than reading the
# helper's source, because a projection is only honest where it is rendered.
class StructuredDataTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "sd_seller@brgen.no", password: "password123", username: "sd_seller", guest: false, city: @city
    )
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, title: "Sofa #{SecureRandom.hex(3)}", category: @category,
      price_cents: 200_000, status: "active", currency: "NOK"
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def schemas
    css_select("script[type='application/ld+json']").map { |node| JSON.parse(node.text) }
  end

  def schema_of(type)
    schemas.find { |data| data["@type"] == type }
  end

  def show_listing
    host! "markedsplass.brgen.no"
    get marketplace.listing_path(@listing)
    assert_response :success
    schema_of("Product")
  end

  test "a listing names no brand and no sku it does not have" do
    product = show_listing

    assert_nil product["brand"], "a seller is not a brand"
    assert_nil product["sku"], "a database id is not a stock-keeping unit"
    refute_includes response.body, "Local Seller"
  end

  test "a buyable listing is in stock" do
    assert @listing.buyable?

    assert_equal "https://schema.org/InStock", show_listing.dig("offers", "availability")
  end

  test "a sold listing is sold out" do
    @listing.mark_sold!

    assert_equal "https://schema.org/SoldOut", show_listing.dig("offers", "availability")
  end

  test "a reserved listing claims no availability at all" do
    @listing.update!(status: "reserved")
    refute @listing.buyable?

    offer = show_listing["offers"]
    assert offer, "the price is still true, so the offer stays"
    assert_nil offer["availability"]
  end

  test "an anonymous post names no author" do
    post_record = Post.create!(user: @seller, title: "Hemmelig #{SecureRandom.hex(3)}", content: "Tekst", city: @city,
                               anonymous: true)
    host! "brgen.no"

    get post_path(post_record)

    assert_response :success
    assert_nil schema_of("Article")["author"]
    refute_includes css_select("script[type='application/ld+json']").map(&:text).join, @seller.username
  end

  test "an attributed post names its author as the page does" do
    post_record = Post.create!(user: @seller, title: "Åpen #{SecureRandom.hex(3)}", content: "Tekst", city: @city)
    host! "brgen.no"

    get post_path(post_record)

    assert_response :success
    assert_equal @seller.username, schema_of("Article").dig("author", "name")
  end

  def meta_content(property)
    css_select("meta[property='#{property}']").first&.attr("content")
  end

  def canonical_href
    css_select("link[rel=canonical]").first&.attr("href")
  end

  test "canonical, og:url, the Product url and the last breadcrumb name one URL" do
    host! "markedsplass.brgen.no"

    get marketplace.listing_path(@listing, ref: "delt-lenke")

    assert_response :success
    canonical = canonical_href
    refute_includes canonical, "?"
    assert_equal canonical, meta_content("og:url")
    assert_equal canonical, schema_of("Product")["url"]
    assert_equal canonical, schema_of("BreadcrumbList")["itemListElement"].last["item"]
  end

  test "a post is an article to both its card and its structured data" do
    post_record = Post.create!(user: @seller, title: "Helg #{SecureRandom.hex(3)}", content: "Tekst", city: @city)
    host! "brgen.no"

    get post_path(post_record)

    assert_response :success
    assert_equal "article", meta_content("og:type")
    assert schema_of("Article")
  end

  test "the home page title names the city once and its search target has one slash" do
    host! "brgen.no"

    get root_path

    assert_response :success
    title = css_select("title").first.text
    assert_equal I18n.t("pages.home_title", city: @city.name), title
    refute_match(/\A(.+) — \1\z/, title)
    target = schema_of("WebSite").dig("potentialAction", "target")
    assert_equal "#{root_url}search?q={search_term_string}", target
  end

  test "a listing reached by its id moves permanently to its slug" do
    host! "markedsplass.brgen.no"

    get marketplace.listing_path(@listing.id, ref: "gammel-lenke")

    assert_response :moved_permanently
    assert_redirected_to marketplace.listing_url(@listing, ref: "gammel-lenke")
    refute_equal @listing.id.to_s, @listing.to_param
  end

  test "a restaurant reached by its id moves permanently to its slug" do
    restaurant = Takeaway::Restaurant.create!(user: @seller, name: "Kjøkken #{SecureRandom.hex(3)}", address: "Marken 4",
                                              cuisine_type: "Norwegian", city: @city, active: true)
    host! "takeaway.brgen.no"

    get takeaway.restaurant_path(restaurant.id)

    assert_response :moved_permanently
    assert_redirected_to takeaway.restaurant_url(restaurant)
  end

  test "a post reached by its id moves permanently to its slug" do
    post_record = Post.create!(user: @seller, title: "Lenke #{SecureRandom.hex(3)}", content: "Tekst", city: @city)
    host! "brgen.no"

    get post_path(post_record.id)

    assert_response :moved_permanently
    assert_redirected_to post_url(post_record)
  end

  # The redirect names the slug, and the slug is the title. A withdrawn listing
  # is hidden from a stranger, so reaching it by id must not hand them its title.
  test "a withdrawn listing reached by its id does not reveal its slug" do
    @listing.update!(status: "removed")
    host! "markedsplass.brgen.no"

    get marketplace.listing_path(@listing.id)

    refute_equal 301, response.status
    refute_includes response.headers["Location"].to_s, @listing.slug
  end

  def create_restaurant(**attributes)
    Takeaway::Restaurant.create!(user: @seller, name: "Kjøkken #{SecureRandom.hex(3)}", address: "Marken 4",
                                 cuisine_type: "Norwegian", city: @city, active: true, **attributes)
  end

  def local_business_for(restaurant)
    host! "takeaway.brgen.no"
    get takeaway.restaurant_path(restaurant)
    assert_response :success
    schema_of("LocalBusiness")
  end

  test "a restaurant saved without coordinates has none, and its markup places it nowhere" do
    restaurant = create_restaurant

    assert_nil restaurant.reload.latitude
    business = local_business_for(restaurant)
    assert business, "an ordinary restaurant still describes itself"
    assert_nil business["geo"]
  end

  test "a restaurant keeps the coordinates its owner gave, in its markup too" do
    restaurant = create_restaurant(latitude: 60.3913, longitude: 5.3221)

    assert_in_delta 60.3913, local_business_for(restaurant).dig("geo", "latitude").to_f, 0.000_001
  end

  test "the migration clears a pin the old arithmetic placed and keeps a typed one" do
    require Rails.root.join("db/migrate/20260915090000_clear_synthesized_takeaway_coordinates")
    pin = ClearSynthesizedTakeawayCoordinates.synthesized_pin(
      anchor_lat: @city.latitude, anchor_lng: @city.longitude, address: "Marken 4", city: nil, name: "Pinnet"
    )
    pinned = create_restaurant(name: "Pinnet", latitude: pin[0], longitude: pin[1])
    typed = create_restaurant(latitude: 60.3913, longitude: 5.3221)

    ActiveRecord::Migration.suppress_messages { ClearSynthesizedTakeawayCoordinates.new.up }

    assert_nil pinned.reload.latitude
    assert_nil pinned.longitude
    assert_in_delta 60.3913, typed.reload.latitude.to_f, 0.000_001
  end

  test "a track with no artist carries no invented artist" do
    set = Playlist::Set.create!(name: "Sett #{SecureRandom.hex(3)}", user: @seller, privacy: "public")
    track = Playlist::Track.create!(title: "Regnvær", artist: "", user: @seller, source_type: "direct",
                                    source_url: "https://example.com/regn.mp3", privacy: "public")
    set.add_track!(track, user: @seller)
    host! "radio.brgen.no"

    get playlist.set_path(set)

    assert_response :success
    recording = schema_of("MusicPlaylist")["track"].find { |row| row["name"] == track.title }
    assert recording, "the set's track is missing from its structured data"
    assert_nil recording["byArtist"]
  end
end
