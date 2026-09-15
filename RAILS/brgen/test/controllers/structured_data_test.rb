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
