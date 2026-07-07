# frozen_string_literal: true

require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "reading_time_minutes ignores markup and rounds up" do
    words = Array.new(201, "bergen").join(" ")
    post = Post.new(content: "<p>#{words}</p><script>alert('x')</script>")

    assert_equal 2, post.reading_time_minutes
  end

  test "reading_time_minutes is zero without body text" do
    assert_equal 0, Post.new(content: "<p> </p>").reading_time_minutes
  end
end
