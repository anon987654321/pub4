# frozen_string_literal: true

require "test_helper"
class CommunityJoinTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user  = User.create!(email_address: "cj-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "cj_#{SecureRandom.hex(3)}", city: @city)
    @other = User.create!(email_address: "co-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "co_#{SecureRandom.hex(3)}", city: @city)
    @community = Community.create!(name: "Test #{SecureRandom.hex(3)}", user: @other)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "the community feed shows posts only from joined communities" do
    theirs = Post.create!(user: @other, community: @community, title: "in community", content: "x")
    feed = -> { Brgen::HomeFeed.scope(feed: "communities", authenticated: true, user: @user.reload).to_a }
    assert_not_includes feed.call, theirs
    @user.join_community!(@community)
    assert @user.member_of?(@community)
    assert_includes feed.call, theirs
    @user.leave_community!(@community)
    assert_not_includes feed.call, theirs
  end
end
