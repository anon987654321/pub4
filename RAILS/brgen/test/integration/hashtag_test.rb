# frozen_string_literal: true

require "test_helper"

class HashtagTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = ActsAsTenant.with_tenant(@city) do
      User.create!(email_address: "h-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "h_#{SecureRandom.hex(3)}", city: @city)
    end
    host! "brgen.no"
  end

  test "usage_count moves by the delta, not on every save" do
    ActsAsTenant.with_tenant(@city) do
      post = Post.create!(user: @user, title: "hi", content: "loving #bergentest today")
      tag = Hashtag.find_by(name: "bergentest")
      assert_equal 1, tag.usage_count
      post.update!(content: "still #bergentest")   # edit, same tag → no re-increment
      assert_equal 1, tag.reload.usage_count
      post.update!(content: "no tags now")          # untag → decrement
      assert_equal 0, tag.reload.usage_count
    end
  end

  test "the hashtag page lists posts using the tag" do
    ActsAsTenant.with_tenant(@city) { Post.create!(user: @user, title: "trip", content: "#oslotest was fun") }
    get "/tags/oslotest"
    assert_response :success
    assert_select "h1", text: "#oslotest"
  end

  test "trending ranks by recent taggings, not all-time usage" do
    ActsAsTenant.with_tenant(@city) do
      # `stale` has the higher all-time usage_count, but its taggings are old;
      # `fresh` was used less overall but all within the trending window. Real
      # trending must surface `fresh` first and drop the purely-stale tag.
      stale = Hashtag.create!(name: "staletag", usage_count: 99)
      fresh = Hashtag.create!(name: "freshtag", usage_count: 2)
      cold = Hashtag.create!(name: "coldtag", usage_count: 50)

      post = Post.create!(user: @user, title: "t", content: "body")
      Tagging.create!(hashtag: fresh, taggable: post) # within window (created now)
      Tagging.create!(hashtag: fresh, taggable: post)
      old = Tagging.create!(hashtag: stale, taggable: post)
      old.update_column(:created_at, 30.days.ago)
      Tagging.create!(hashtag: cold, taggable: post).update_column(:created_at, 30.days.ago)

      names = Hashtag.trending.limit(8).map(&:name)
      assert_equal "freshtag", names.first, "recently-used tag must lead trending"
      assert_not_includes names, "coldtag", "a tag with only stale taggings is not trending"
    end
  end
end
