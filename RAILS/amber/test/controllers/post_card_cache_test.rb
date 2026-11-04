# frozen_string_literal: true

require "test_helper"

# The post card was cached under the viewer's id, so every reader wrote a
# private copy of every card; the viewer's own like, vote and delete are now
# drawn fresh, and only the body every reader shares is cached.
class PostCardCacheTest < ActionDispatch::IntegrationTest
  setup do
    @store = ActiveSupport::Cache::MemoryStore.new
    @caching, @cache_store = ActionController::Base.perform_caching, ActionController::Base.cache_store
    ActionController::Base.perform_caching = true
    ActionController::Base.cache_store = @store
    @author = member("author")
    @post = Post.create!(user: @author, body: "Ny kåpe til høsten")
  end

  teardown do
    ActionController::Base.perform_caching = @caching
    ActionController::Base.cache_store = @cache_store
  end

  def member(name)
    email = "#{name}-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def fragment_writes
    keys = []
    count = ->(*, payload) { keys << payload[:key].to_s if payload[:key].to_s.include?("posts/") }
    ActiveSupport::Notifications.subscribed(count, "cache_write.active_support") { yield }
    keys
  end

  test "a second reader reuses the first reader's card body" do
    sign_in(member("first"))
    assert_not_empty fragment_writes { get posts_path }, "the card body was not cached at all"

    delete session_path
    sign_in(member("second"))
    assert_empty fragment_writes { get posts_path }, "a second reader wrote a private copy of the card"
  end

  test "the author's delete button is drawn for the author only, cache or no cache" do
    sign_in(member("reader"))
    get posts_path
    assert_select "form[action=?]", post_path(@post), 0

    delete session_path
    sign_in(@author)
    get posts_path
    assert_select "form[action=?] button", post_path(@post), text: I18n.t("actions.delete")
  end
end
