# frozen_string_literal: true

require "test_helper"

# Crossed paths over HTTP: a location ping is taken only from a visible,
# verified profile that opted in, only with real coordinates, and the list
# never shows someone either side has blocked.
class DatingPathCrossingsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @previous_slugs = Rails.application.config.x.oauth_provider_slugs
    Rails.application.config.x.oauth_provider_slugs = %w[vipps]
    @me = user_with_profile("pc_me")
    @other = user_with_profile("pc_other")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Rails.application.config.x.oauth_provider_slugs = @previous_slugs
  end

  def user_with_profile(handle)
    handle = "#{handle}_#{SecureRandom.hex(3)}"
    user = User.strict_loading(false).create!(email_address: "#{handle}@brgen.no", password: "password123",
                                              username: handle, guest: false, city: @city)
    vipps = IdentityProvider.find_by(slug: "vipps") || IdentityProvider.create!(slug: "vipps", name: "Vipps")
    ExternalIdentity.create!(user:, identity_provider: vipps, subject: "sub-#{handle}", assurance_level: "verified")
    profile = Dating::Profile.new(user:, age: 30, bio: "hei", visible: true, gender: "woman", looking_for: "man",
                                  location_discovery_enabled: true, verified_at: Time.current)
    attach_pixel!(profile.photos, filename: "#{handle}.png")
    profile.save!
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  def profile_for(user) = Dating::Profile.find_by!(user_id: user.id)

  def ping(latitude: 60.3921, longitude: 5.3225)
    post dating.locate_path_crossings_path, params: { location: { latitude:, longitude: } }, as: :json
  end

  test "an unverified profile, or one that has not opted in, is refused a ping" do
    profile_for(@me).update_columns(verified_at: nil)
    sign_in_as(@me)
    assert_no_difference -> { Dating::LocationPing.count } do
      ping
    end
    assert_response :forbidden

    profile_for(@me).update_columns(verified_at: Time.current, location_discovery_enabled: false)
    assert_no_difference -> { Dating::LocationPing.count } do
      ping
    end
    assert_response :forbidden
  end

  test "coordinates out of range, unparseable or missing are refused" do
    sign_in_as(@me)

    out_of_range = [ { latitude: 91, longitude: 5 }, { latitude: 60, longitude: 181 },
                     { latitude: "nord", longitude: 5 } ]
    out_of_range.each do |bad|
      ping(**bad)
      assert_response :unprocessable_entity, bad.inspect
    end
    post dating.locate_path_crossings_path, params: {}, as: :json
    assert_response :unprocessable_entity

    ping
    assert_response :no_content
  end

  test "the list shows a crossing until either person blocks the other" do
    [ @other, @me ].each do |user|
      Dating::PathCrossingRecorder.new(user:, profile: profile_for(user), latitude: 60.3921, longitude: 5.3225).call
    end
    sign_in_as(@me)
    card = "article.dating-crossing form input[name=user_id][value=?]"

    get dating.path_crossings_path
    assert_select card, @other.id.to_s, 1

    @other.block!(@me)
    get dating.path_crossings_path
    assert_select card, @other.id.to_s, 0
  end
end
