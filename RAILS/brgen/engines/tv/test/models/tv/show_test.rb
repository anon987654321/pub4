# frozen_string_literal: true

require "test_helper"

class Tv::ShowTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_show_owner@brgen.no", password: "password123", city: @city
    )
    @channel = ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Serier #{SecureRandom.hex(2)}")
    end
    @other_channel = ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Andre serier #{SecureRandom.hex(2)}")
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a show needs a title, a description and a slug" do
    show = Tv::Show.new(channel: @channel, title: "", description: "", slug: nil)

    assert_not show.valid?
    assert show.errors.added?(:title, :blank)
    assert show.errors.added?(:description, :blank)
    assert show.errors.added?(:slug, :blank)
  end

  # The seed paths create a show from a title alone, against a NOT NULL slug.
  test "a show without a slug takes one from its title" do
    show = Tv::Show.create!(channel: @channel, title: "Livet på Nordnes", description: "Seks episoder")

    assert_equal "livet-pa-nordnes", show.slug
  end

  test "a slug is unique within a channel and free across channels" do
    Tv::Show.create!(channel: @channel, title: "Bybanen", description: "Om trikken", slug: "bybanen")
    same_channel = Tv::Show.new(channel: @channel, title: "Bybanen igjen", description: "Om trikken", slug: "bybanen")

    assert_not same_channel.valid?
    assert same_channel.errors.added?(:slug, :taken, value: "bybanen")
    assert Tv::Show.new(channel: @other_channel, title: "Bybanen", description: "Om trikken", slug: "bybanen").valid?
  end

  test "published holds only published shows and a show routes by its slug" do
    live = Tv::Show.create!(channel: @channel, title: "Ute", description: "Sendt", slug: "ute", published: true)
    draft = Tv::Show.create!(channel: @channel, title: "Kladd", description: "Ikke sendt", slug: "kladd")

    assert_includes Tv::Show.published, live
    assert_not_includes Tv::Show.published, draft
    assert_equal "ute", live.to_param
  end

  test "a show found by id names its channel's owner" do
    id = Tv::Show.create!(channel: @channel, title: "Eier", description: "Hvem", slug: "eier").id

    assert_equal @owner.id, Tv::Show.find(id).channel_owner&.id
  end
end
