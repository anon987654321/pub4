# frozen_string_literal: true

require "test_helper"

class Tv::SubscriptionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_sub_owner@brgen.no", password: "password123", city: @city
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "tv_sub_viewer@brgen.no", password: "password123", city: @city
    )
    @channel = ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Abonnement #{SecureRandom.hex(2)}")
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a viewer subscribes to a channel once" do
    Tv::Subscription.create!(user: @viewer, channel: @channel)
    again = Tv::Subscription.new(user: @viewer, channel: @channel)

    assert_not again.valid?
    assert again.errors.added?(:user_id, :taken, value: @viewer.id)
    assert Tv::Subscription.new(user: @owner, channel: @channel).valid?
  end
end
