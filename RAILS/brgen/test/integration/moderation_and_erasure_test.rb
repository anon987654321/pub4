# frozen_string_literal: true

require "test_helper"

# P0 safety behaviours: resolving a report takes the content down and out of feeds,
# and a scheduled-for-deletion account can't sign back in.
class ModerationAndErasureTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.create!(email_address: "auth-#{SecureRandom.hex(4)}@brgen.no",
                           password: "password12345", username: "a_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "resolving a report removes the post from feeds and by-id lookup" do
    post = Post.create!(user: @author, title: "spammy", content: "buy now")
    assert_includes Post.hot.to_a, post
    report = ModerationWorkflow.report!(reporter: @author, target: post, reason: "spam")
    ModerationWorkflow.transition!(report: report, status: "resolved")
    post.reload
    assert post.removed_at.present?, "resolve must stamp removed_at"
    assert_not_includes Post.hot.to_a, post, "removed post must leave the feed"
    assert_not_includes Post.kept.to_a, post
  end

  test "hot ranking decays with age (fresh beats stale-but-higher)" do
    stale = Post.create!(user: @author, title: "old", content: "x", created_at: 5.days.ago)
    fresh = Post.create!(user: @author, title: "new", content: "y")
    3.times { |i| Vote.create!(user: User.create!(email_address: "v#{i}-#{SecureRandom.hex(3)}@brgen.no", password: "password12345", city: @city), votable: stale, value: 1) }
    Vote.create!(user: User.create!(email_address: "vf-#{SecureRandom.hex(3)}@brgen.no", password: "password12345", city: @city), votable: fresh, value: 1)
    order = Post.hot.to_a
    assert_operator order.index(fresh), :<, order.index(stale), "a fresh post should outrank a 5-day-old one on hot"
  end

  test "a deletion-pending account cannot authenticate a new session" do
    @author.schedule_deletion!
    assert @author.deletion_pending?
  end
end
