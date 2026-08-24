# frozen_string_literal: true

require "test_helper"
class BookmarkTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no"); ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "bm-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "bm_#{SecureRandom.hex(3)}", city: @city)
    @post = Post.create!(user: @user, title: "keep me", content: "x")
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "bookmarking adds and removing drops a post from the saved list" do
    assert_not @user.bookmarked?(@post)
    @user.bookmark!(@post)
    assert @user.bookmarked?(@post)
    assert_includes @user.bookmarked_posts, @post
    @user.unbookmark!(@post)
    assert_not @user.bookmarked?(@post)
  end

  test "bookmarking is idempotent" do
    @user.bookmark!(@post)
    assert_nothing_raised { @user.bookmark!(@post) }
    assert_equal 1, @user.bookmarks.count
  end
end
