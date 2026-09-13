# frozen_string_literal: true

require "test_helper"

class Tv::EpisodeTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_episode_owner@brgen.no", password: "password123", city: @city
    )
    channel = ActsAsTenant.with_tenant(@city) do
      Tv::Channel.create!(user: @owner, name: "Episoder #{SecureRandom.hex(2)}")
    end
    @show = Tv::Show.create!(channel: channel, title: "Fjellet", description: "Seks turer", slug: "fjellet")
    @other_show = Tv::Show.create!(channel: channel, title: "Sjøen", description: "Seks båter", slug: "sjoen")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "an episode needs a title and a number" do
    episode = Tv::Episode.new(show: @show, title: "", number: nil)

    assert_not episode.valid?
    assert episode.errors.added?(:title, :blank)
    assert episode.errors.added?(:number, :blank)
  end

  test "a number is used once per show and routes the episode" do
    Tv::Episode.create!(show: @show, title: "Ulriken", number: 1)
    again = Tv::Episode.new(show: @show, title: "Fløyen", number: 1)

    assert_not again.valid?
    assert again.errors.added?(:number, :taken, value: 1)
    assert Tv::Episode.new(show: @other_show, title: "Nordnes", number: 1).valid?
    assert_equal "1", Tv::Episode.find_by!(show_id: @show.id, number: 1).to_param
  end

  # Two hops from an episode loaded by id: show, then channel, then its user.
  test "an episode found by id names its channel's owner" do
    id = Tv::Episode.create!(show: @show, title: "Løvstakken", number: 2).id

    assert_equal @owner.id, Tv::Episode.find(id).channel_owner&.id
  end
end
