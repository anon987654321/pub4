# frozen_string_literal: true

require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  test "site rss feed returns published posts" do
    user = User.create!(email_address: "writer@example.com", password: "password123!")
    blog = Blog.create!(name: "Test Blog", slug: "test-blog", user:)
    Post.create!(blog:, user:, title: "Published", slug: "published", body: "Hello world", published: true, published_at: 1.hour.ago)
    Post.create!(blog:, user:, title: "Draft", slug: "draft", body: "Hidden", published: false)

    get feed_path(format: :rss)

    assert_response :success
    assert_includes response.content_type, "application/rss+xml"
    assert_includes response.body, "Published"
    refute_includes response.body, "Draft"
  end

  test "site atom feed returns published posts" do
    user = User.create!(email_address: "atom@example.com", password: "password123!")
    blog = Blog.create!(name: "Atom Blog", slug: "atom-blog", user:)
    Post.create!(blog:, user:, title: "Atom Post", slug: "atom-post", body: "Atom body", published: true, published_at: 1.hour.ago)

    get feed_path(format: :atom)

    assert_response :success
    assert_includes response.content_type, "application/atom+xml"
    assert_includes response.body, "Atom Post"
  end
end