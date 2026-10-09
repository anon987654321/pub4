# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class PostTest < ActiveSupport::TestCase
  test "departing accounts are not attributed on their posts" do
    user = User.strict_loading(false).create!(
      email_address: "departing-post-#{SecureRandom.hex(4)}@brgen.no",
      password: "password12345",
      username: "departing_post_#{SecureRandom.hex(3)}"
    )
    user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    post = Post.new(user: user, title: "Still public", content: "body")

    assert_not post.attributed?
    assert_equal "anon", post.author_name
    assert_nil post.author_avatar_url
  end

  test "reading_time_minutes ignores markup and rounds up" do
    words = Array.new(201, "bergen").join(" ")
    post = Post.new(content: "<p>#{words}</p><script>alert('x')</script>")

    assert_equal 2, post.reading_time_minutes
  end

  test "reading_time_minutes is zero without body text" do
    assert_equal 0, Post.new(content: "<p> </p>").reading_time_minutes
  end

  test "search returns no posts when the FTS table is absent" do
    Post.connection.stub(:data_source_exists?, false) do
      assert_empty Post.search("bergen")
    end
  end
end
