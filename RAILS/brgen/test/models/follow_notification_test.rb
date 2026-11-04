# frozen_string_literal: true

require "test_helper"

# Follow, unfollow and follow again sent a follow notification each time.
class FollowNotificationTest < ActiveSupport::TestCase
  setup do
    @follower = person("fn-follower")
    @followed = person("fn-followed")
  end

  def person(prefix)
    email_address = "#{prefix}-#{SecureRandom.hex(3)}@brgen.no"
    User.strict_loading(false).create!(email_address:, password: "password123")
  end

  def follow_notices = Notification.where(user: @followed, actor_id: @follower.id, kind: "follow")

  test "following again within a day does not notify again" do
    Follow.create!(follower: @follower, followed: @followed).destroy!
    Follow.create!(follower: @follower, followed: @followed)

    assert_equal 1, follow_notices.count
  end

  test "a follow after the quiet day notifies again" do
    Follow.create!(follower: @follower, followed: @followed).destroy!
    follow_notices.update_all(created_at: 2.days.ago)
    Follow.create!(follower: @follower, followed: @followed)

    assert_equal 2, follow_notices.count
  end
end
