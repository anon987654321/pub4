# frozen_string_literal: true

require "test_helper"

class DemoFeedTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
  end

  test "demo feed prefers bergen demo usernames" do
    demo_user = User.create!(
      email_address: "emilie@brgen.no",
      username: "emilie_floyen",
      password: "password123",
      password_confirmation: "password123",
      city: @city
    )
    noise_user = User.create!(
      email_address: "noise@brgen.no",
      username: "seed99_noise",
      password: "password123",
      password_confirmation: "password123",
      city: @city
    )
    community = Community.create!(name: "bergen", slug: "bergen", user: demo_user)
    demo_post = Post.create!(user: demo_user, community: community, title: "Demo post", content: "Hei Bergen")
    Post.create!(user: noise_user, community: community, title: "Noise", content: "Lorem")

    assert Brgen::DemoFeed.available?
    assert_includes Brgen::DemoFeed.hot.pluck(:id), demo_post.id
    assert_not_includes Brgen::DemoFeed.hot.pluck(:id), Post.find_by(title: "Noise").id
  end
end