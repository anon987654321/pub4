# frozen_string_literal: true

require "test_helper"

class Tv::ChannelTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_channel_owner@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a channel without a slug takes one from its name and routes by it" do
    ActsAsTenant.with_tenant(@city) do
      channel = Tv::Channel.create!(user: @owner, name: "Bergen Byliv #{SecureRandom.hex(2)}")

      assert_equal channel.name.parameterize, channel.slug
      assert_equal channel.slug, channel.to_param
    end
  end

  test "a slug is lowercase letters, digits, dashes and underscores, and unique" do
    ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Første", slug: "felles-kanal")
      taken = Tv::Channel.new(user: @owner, name: "Andre", slug: "felles-kanal")
      shouting = Tv::Channel.new(user: @owner, name: "Tredje", slug: "Store Bokstaver")

      assert_not taken.valid?
      assert taken.errors.added?(:slug, :taken, value: "felles-kanal")
      assert_not shouting.valid?
      assert shouting.errors.added?(:slug, :invalid, value: "Store Bokstaver")
    end
  end

  test "a channel needs a name" do
    channel = Tv::Channel.new(user: @owner, name: "")

    assert_not channel.valid?
    assert channel.errors.added?(:name, :blank)
  end

  test "a channel is live only while one of its broadcasts is" do
    ActsAsTenant.with_tenant(@city) do
      channel = Tv::Channel.create!(user: @owner, name: "Direkte #{SecureRandom.hex(2)}")
      broadcast = channel.broadcasts.create!(user: @owner, title: "Kveldssending", status: "scheduled")

      assert_not Tv::Channel.find(channel.id).live?
      broadcast.update!(status: "live")
      assert Tv::Channel.find(channel.id).live?
    end
  end

  test "popular lists the most subscribed channel first" do
    ActsAsTenant.with_tenant(@city) do
      quiet = Tv::Channel.create!(user: @owner, name: "Stille #{SecureRandom.hex(2)}", subscribers_count: 1)
      loud = Tv::Channel.create!(user: @owner, name: "Populær #{SecureRandom.hex(2)}", subscribers_count: 50)

      assert_equal [ loud.id, quiet.id ], Tv::Channel.where(id: [ quiet.id, loud.id ]).popular.ids
    end
  end
end
