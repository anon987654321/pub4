# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper
  include SchemaHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && City.none?
    @city = City.find_by!(domain: "brgen.no")
    Current.domain = "brgen.no"
    Current.city = "Bergen"
    Rails.application.routes.default_url_options[:host] = "brgen.no"
  end

  teardown do
    Current.reset if Current.respond_to?(:reset)
  end

  test "activity_event_href links to post path" do
    user = User.strict_loading(false).create!(
      email_address: "activity-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "act#{SecureRandom.hex(3)}",
      city: @city
    )
    post = Post.create!(user: user, title: "Hello Bergen", content: "body text here", city: @city)
    event = ActivityEvent.new(
      source_vertical: "social",
      event_name: "PostCreated",
      subject_type: "Post",
      subject_id: post.id
    )

    href = activity_event_href(event)
    assert_equal post_path(post), href
  end

  test "activity_event_href returns nil for missing record" do
    event = ActivityEvent.new(
      source_vertical: "social",
      event_name: "PostCreated",
      subject_type: "Post",
      subject_id: 9_999_999
    )
    assert_nil activity_event_href(event)
  end

  test "activity_event_title uses the subject's name, not humanize of CamelCase" do
    user = User.strict_loading(false).create!(
      email_address: "title-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "ttl#{SecureRandom.hex(3)}",
      city: @city
    )
    category = Marketplace::Category.create!(
      name: "Ski",
      slug: "ski-#{SecureRandom.hex(4)}"
    )
    listing = Marketplace::Listing.create!(
      user: user,
      title: "Telemarkski",
      description: "Pent brukt",
      price_cents: 1000,
      status: "active",
      category: category,
      city: @city
    )
    event = ActivityEvent.new(
      source_vertical: "marketplace",
      event_name: "ListingCreated",
      subject_type: "Marketplace::Listing",
      subject_id: listing.id
    )

    I18n.with_locale(:nb) do
      assert_equal "Telemarkski", activity_event_title(event)
      assert_equal "markedsplass", activity_event_vertical(event)
    end
  end

  test "activity_event_title translates the event when the subject has no name" do
    event = ActivityEvent.new(
      source_vertical: "takeaway",
      event_name: "TakeawayRestaurantCreated",
      subject_type: "Takeaway::Restaurant",
      subject_id: 9_999_999
    )
    I18n.with_locale(:nb) do
      refute_equal "Takeawayrestaurantcreated", activity_event_title(event)
      assert_equal "Ny restaurant", activity_event_title(event)
    end
  end

  test "activity_event_href marketplace listing uses subdomain host" do
    user = User.strict_loading(false).create!(
      email_address: "list-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "lst#{SecureRandom.hex(3)}",
      city: @city
    )
    category = Marketplace::Category.create!(
      name: "Bikes",
      slug: "bikes-#{SecureRandom.hex(4)}"
    )
    listing = Marketplace::Listing.create!(
      user: user,
      title: "Bike",
      description: "Nice bike",
      price_cents: 1000,
      status: "active",
      category: category,
      city: @city
    )
    event = ActivityEvent.new(
      source_vertical: "marketplace",
      event_name: "ListingCreated",
      subject_type: "Marketplace::Listing",
      subject_id: listing.id
    )

    href = activity_event_href(event)
    assert href.present?
    assert_match %r{\Ahttps?://}, href
    # City marketplace subdomain is locale-specific (markedsplass for brgen.no).
    assert_match %r{markedsplass\.brgen\.no}, href
    # Listings are slug-routed now (Shared::Sluggable): to_param returns the slug.
    assert_includes href, "/listings/#{listing.slug}"
  end

  test "city_name reads the domain when Current.city is blank" do
    Current.city = nil
    Current.domain = "oshlo.no"
    assert_equal "Oslo", city_name
  end

  test "city_name does not invent Bergen as a last resort" do
    Current.city = nil
    Current.domain = nil
    assert_equal "Brgen", city_name
  end

  test "schema_url_for makes listing URLs absolute on the marketplace host" do
    user = User.strict_loading(false).create!(
      email_address: "seo-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "seo#{SecureRandom.hex(3)}",
      city: @city
    )
    category = Marketplace::Category.create!(
      name: "Furniture",
      slug: "furniture-#{SecureRandom.hex(4)}"
    )
    listing = Marketplace::Listing.create!(
      user: user, title: "Seo chair", description: "a chair",
      price_cents: 1000, status: "active", category: category, city: @city
    )
    url = schema_url_for(listing)
    assert url.start_with?("http"), url
    assert_match %r{markedsplass\.brgen\.no}, url
  end

  test "inferred vertical for channels is messenger" do
    helper = Object.new.extend(ApplicationHelper)
    def helper.controller_path = "channels"
    assert_equal :messenger, helper.inferred_vertical_from_controller
  end

  # The bar is eight entries in one order — operator, 2026-08-29. Named here
  # rather than counted, because the failure this catches is a vertical quietly
  # falling off the only chrome that reaches it, which a count cannot see.
  #
  # Slugs, not labels: the labels are localised now, so a test written against
  # them would pass in en and fail in nb, and this app defaults to nb.
  test "the nav bar is the eight verticals, in order" do
    Current.domain = "brgen.no"
    # authenticated? is mixed in from Authentication in controllers; stub for helper unit tests.
    def authenticated? = true

    assert_equal %w[front ai playlist marketplace takeaway messenger maps tv],
                 brgen_nav_items.map(&:first)
  end

  # dating, channels and sign up came off the bar on 2026-08-29. Pinned so that
  # putting one back is a decision someone makes on purpose.
  test "the nav bar carries no dating, channels or sign up" do
    Current.domain = "brgen.no"
    def authenticated? = false

    slugs = brgen_nav_items.map(&:first)
    %w[dating channels sign_up].each { |gone| refute_includes slugs, gone }
  end

  # Radio is the playlist vertical wearing the name the operator gave the bar.
  # The slug has to stay `playlist` because that is what Current.subapp reports,
  # and it is what decides which entry wears the active rule.
  test "Radio is the playlist vertical, and still points at it" do
    Current.domain = "brgen.no"
    def authenticated? = true

    slug, label, href = brgen_nav_items.find { |s, _, _| s == "playlist" }
    assert_equal "playlist", slug
    assert_equal "Radio", label
    assert_equal "//playlist.brgen.no/", href
  end

  # The active entry is decided by slug against Current.subapp, never by the
  # display string. Comparing labels worked only while they were English.
  test "the active entry follows the subapp, not the label" do
    Current.subapp = nil
    assert nav_item_active?("front"), "the apex is the front feed"
    refute nav_item_active?("playlist")

    Current.subapp = :playlist
    assert nav_item_active?("playlist"), "Radio wears the rule on playlist.brgen.no"
    refute nav_item_active?("front")
  end

  # Exactly one entry wears the rule, whichever surface is being read.
  test "one entry is active at a time" do
    Current.domain = "brgen.no"
    def authenticated? = true

    [ nil, :playlist, :marketplace, :maps, :tv ].each do |subapp|
      Current.subapp = subapp
      active = brgen_nav_items.map(&:first).count { |slug| nav_item_active?(slug) }
      assert_equal 1, active, "expected one active entry on #{subapp.inspect}, got #{active}"
    end
  end

  test "notification_href opens match and follow targets" do
    user = User.strict_loading(false).create!(
      email_address: "n-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "n#{SecureRandom.hex(3)}",
      city: @city
    )
    actor = User.strict_loading(false).create!(
      email_address: "a-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "a#{SecureRandom.hex(3)}",
      city: @city
    )

    match_n = Notification.new(user: user, actor: actor, kind: "match")
    href = notification_href(match_n)
    assert href.present?
    assert_match %r{dating\.brgen\.no}, href

    follow_n = Notification.new(user: user, actor: actor, kind: "follow", notifiable: nil)
    assert_equal user_path(actor), notification_href(follow_n)
  end

  test "notification_href uses notifiable post" do
    user = User.strict_loading(false).create!(
      email_address: "p-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "p#{SecureRandom.hex(3)}",
      city: @city
    )
    post = Post.create!(user: user, title: "Ping", content: "pong", city: @city)
    n = Notification.new(user: user, actor: user, kind: "like", notifiable: post)
    assert_equal post_path(post), notification_href(n)
  end

  # The wordmark is the city domain, on every host. It was the literal "brgen"
  # everywhere once, so Oslo and Frankfurt wore Bergen's name; it then went the
  # other way and rendered whole hostnames on verticals; then it dropped to the
  # bare city label. It is the domain now — brgen.no, oshlo.no, lsangeles.com —
  # which is one shape per city and the string that is on the stickers.
  test "brand mark on a city apex is that city, not brgen" do
    Current.domain = "oshlo.no"
    Current.subapp = nil

    assert_equal({ label: "oshlo.no" }, brand_mark_fragments)
  end

  test "brand mark on the bergen apex is unchanged" do
    Current.domain = "brgen.no"
    Current.subapp = nil

    assert_equal({ label: "brgen.no" }, brand_mark_fragments)
  end

  test "brand mark on a vertical is still just the city" do
    Current.domain = "brgen.no"
    Current.subapp = :marketplace
    request.host = "markedsplass.brgen.no"

    # It used to render the whole host -- quiet "markedsplass.", bold "brgen",
    # quiet ".no". That prints a URL where a logo goes, and the nav swiper
    # already marks which vertical is active. Operator decision 2026-08-27.
    assert_equal({ label: "brgen.no" }, brand_mark_fragments)
  end

  # Every city is a peer — the mark leaves for whichever city the request
  # resolved to, never a hardcoded brgen.no. dating renders no primary nav, so
  # on that vertical this link is the only way off the page.
  test "brand mark on a vertical leaves for its own city apex" do
    { "brgen.no" => "brgen.no", "lsangeles.com" => "lsangeles.com",
      "stvanger.no" => "stvanger.no", "trndheim.no" => "trndheim.no" }.each do |domain, expected|
      Current.domain = domain
      Current.subapp = :dating
      request.host = "dating.#{domain}"

      assert_equal "http://#{expected}/", brand_mark_href,
                   "the mark on dating.#{domain} should leave for #{expected}"
    end
  end

  test "brand mark on an apex still links to root" do
    Current.domain = "oshlo.no"
    Current.subapp = nil

    assert_equal "/", brand_mark_href
  end

  test "brand mark on a non-no city is that city" do
    Current.domain = "lsangeles.com"
    Current.subapp = :marketplace
    request.host = "marketplace.lsangeles.com"

    assert_equal({ label: "lsangeles.com" }, brand_mark_fragments)
  end
end
