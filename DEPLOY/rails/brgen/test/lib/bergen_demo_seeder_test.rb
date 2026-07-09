# frozen_string_literal: true

require "test_helper"

class BergenDemoSeederTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "seeds norwegian bergen posts and users without remote media" do
    ActsAsTenant.with_tenant(@city) do
      Brgen::BergenDemoSeeder.new(@city, attach_media: false).seed!
    end

    post = Post.where(city: @city).find_by!(title: "Regnværsdag på Bryggen")
    assert_equal "bergen", post.community.slug
    assert_match(/Kaffebrenneriet/, post.content)
    refute post.image.attached?

    user = User.find_by!(username: "henrik_vestland")
    assert_equal "henrik_vestland@brgen.no", user.email_address

    assert Comment.where(commentable: post).count >= 2
    assert Marketplace::Listing.exists?(title: "Brukt sykkel — Bergen sentrum")
    assert Dating::Profile.joins(:user).exists?(users: { username: "emilie_floyen" })
  end
end