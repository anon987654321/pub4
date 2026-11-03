# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# The city stream reaches every open front page in the city, signed in or not,
# so a post only goes there if every one of those readers may see it.
class PostCityFeedBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "feed-author@brgen.no", password: "password123",
                                                 city: @city)
    @stream = Post.city_feed_stream(@city.id)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a public post reaches the city's front pages" do
    ActsAsTenant.with_tenant(@city) do
      assert_turbo_stream_broadcasts(@stream) do
        Post.create!(user: @author, city: @city, title: "Åpent", content: "Alle kan se dette")
      end
    end
  end

  test "a post in a private community never reaches the city stream" do
    ActsAsTenant.with_tenant(@city) do
      club = Community.create!(slug: "lukket-klubb", name: "Lukket klubb", user: @author, city: @city,
                               privacy: "private")
      assert_no_turbo_stream_broadcasts(@stream) do
        Post.create!(user: @author, city: @city, community: club, title: "Hemmelig", content: "Bare for medlemmer")
      end
    end
  end
end
