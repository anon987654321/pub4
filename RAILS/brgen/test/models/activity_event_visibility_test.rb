# frozen_string_literal: true

require "test_helper"
class ActivityEventVisibilityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no"); ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "ae-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "ae_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "public_only keeps private activity off the profile" do
    pub  = ActivityEvent.create!(actor: @user, source_vertical: "social", event_name: "PostCreated",  subject_type: "Post", subject_id: 1, visibility: "public",  moderation_state: "clean")
    priv = ActivityEvent.create!(actor: @user, source_vertical: "dating", event_name: "DatingLike",    subject_type: "User", subject_id: 2, visibility: "private", moderation_state: "clean")
    ids = ActivityEvent.visible.public_only.where(actor_id: @user.id).pluck(:id)
    assert_includes ids, pub.id
    assert_not_includes ids, priv.id, "a private dating like must never surface on a profile"
  end

  test "for_city_home keeps another city's listing off this city's strip" do
    foreign = ActivityEvent.create!(
      actor: @user, source_vertical: "marketplace", event_name: "ListingCreated",
      subject_type: "Marketplace::Listing", subject_id: 9_999_999,
      locality: "Oslo", visibility: "public", moderation_state: "clean"
    )
    category = Marketplace::Category.create!(name: "Chairs", slug: "chairs-#{SecureRandom.hex(4)}")
    listing = Marketplace::Listing.create!(
      user: @user, title: "Bergen chair", description: "chair",
      price_cents: 1000, status: "active", category: category, city: @city
    )
    local = ActivityEvent.create!(
      actor: @user, source_vertical: "marketplace", event_name: "ListingCreated",
      subject_type: "Marketplace::Listing", subject_id: listing.id,
      visibility: "public", moderation_state: "clean"
    )

    ids = ActivityEvent.for_city_home(@city).map(&:id)
    assert_includes ids, local.id
    refute_includes ids, foreign.id
  end
end
