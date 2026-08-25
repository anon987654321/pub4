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
      object_type: "Post",
      object_id: post.id
    )

    href = activity_event_href(event)
    assert_equal post_path(post), href
  end

  test "activity_event_href returns nil for missing record" do
    event = ActivityEvent.new(
      source_vertical: "social",
      event_name: "PostCreated",
      object_type: "Post",
      object_id: 9_999_999
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
      object_type: "Marketplace::Listing",
      object_id: listing.id
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
      object_type: "Takeaway::Restaurant",
      object_id: 9_999_999
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
      object_type: "Marketplace::Listing",
      object_id: listing.id
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

  test "brgen_nav_items includes channels" do
    Current.domain = "brgen.no"
    # authenticated? is mixed in from Authentication in controllers; stub for helper unit tests.
    def authenticated? = true
    items = brgen_nav_items
    labels = items.map(&:first)
    assert_includes labels, "channels"
    channels = items.find { |label, _| label == "channels" }
    assert_equal channels_path, channels.last
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

  # The wordmark used to be the literal "brgen" on every host, so Oslo and
  # Frankfurt wore Bergen's name and a vertical was indistinguishable from the
  # apex it hangs off. These pin the three shapes it can take.
  test "brand mark on a city apex is that city, not brgen" do
    Current.domain = "oshlo.no"
    Current.subapp = nil

    assert_equal({ label: "oshlo" }, brand_mark_fragments)
  end

  test "brand mark on the bergen apex is unchanged" do
    Current.domain = "brgen.no"
    Current.subapp = nil

    assert_equal({ label: "brgen" }, brand_mark_fragments)
  end

  test "brand mark on a vertical names the whole host" do
    Current.domain = "brgen.no"
    Current.subapp = :marketplace
    request.host = "markedsplass.brgen.no"

    fragments = brand_mark_fragments
    assert_equal "markedsplass.", fragments[:prefix]
    assert_equal "brgen", fragments[:label]
    assert_equal ".no", fragments[:suffix]
    # The parts have to reassemble into the host the reader typed — that is the
    # whole claim the mark is making.
    assert_equal "markedsplass.brgen.no", fragments.values_at(:prefix, :label, :suffix).join
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

  test "brand mark carries a non-no tld intact" do
    Current.domain = "lsangeles.com"
    Current.subapp = :marketplace
    request.host = "marketplace.lsangeles.com"

    assert_equal "marketplace.lsangeles.com",
                 brand_mark_fragments.values_at(:prefix, :label, :suffix).join
  end
end
