# frozen_string_literal: true

require "test_helper"

# Subscribing to a TV channel looked its subscription up by `tv_channel:`, an
# association that does not exist (the belongs_to is `channel`, the column
# `tv_channel_id`), so both subscribe and unsubscribe answered 500. Found by the
# flow gate (MASTER/gates/data/flows.yml, brgen_tv_subscribe_and_leave).
class Tv::ChannelSubscriptionTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_chan_owner@brgen.no", password: "password123", username: "tv_chan_owner", city: @city, guest: false
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "tv_chan_viewer@brgen.no", password: "password123", username: "tv_chan_viewer", city: @city, guest: false
    )
    @channel = ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Abonnement #{SecureRandom.hex(2)}")
    end
    host! "tv.brgen.no"
    post session_path, params: { email_address: @viewer.email_address, password: "password123" }
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "subscribing records one subscription and a second request keeps it at one" do
    assert_difference -> { Tv::Subscription.where(user_id: @viewer.id, tv_channel_id: @channel.id).count }, 1 do
      post tv.subscribe_channel_path(@channel.slug)
    end
    assert_response :redirect

    post tv.subscribe_channel_path(@channel.slug)
    assert_equal 1, Tv::Subscription.where(user_id: @viewer.id, tv_channel_id: @channel.id).count
  end

  test "unsubscribing removes it" do
    Tv::Subscription.create!(user: @viewer, channel: @channel)

    assert_difference -> { Tv::Subscription.count }, -1 do
      delete tv.unsubscribe_channel_path(@channel.slug)
    end
  end
end
