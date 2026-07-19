# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

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
    assert_includes href, "/listings/#{listing.id}"
  end

  test "inferred vertical for channels is messenger" do
    helper = Object.new.extend(ApplicationHelper)
    def helper.controller_path = "channels"
    assert_equal :messenger, helper.inferred_vertical_from_controller
  end
end
