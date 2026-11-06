# frozen_string_literal: true

require "test_helper"

# Blocking someone hid their posts and profile, but their comments still sat
# in every thread the reader opened.
class PostCommentsBlockingTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = member("reader")
    @blocked = member("blocked")
    @other = member("other")

    @post = Post.create!(user: @other, title: "Tråd", content: "…", city: @city)
    root = Comment.create!(user: @other, commentable: @post, content: "en vanlig kommentar")
    Comment.create!(user: @blocked, commentable: @post, content: "blokkert rotkommentar")
    Comment.create!(user: @blocked, commentable: @post, parent: root, content: "blokkert svar")
    @reader.block!(@blocked)
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no", username: "#{prefix}_#{SecureRandom.hex(3)}",
      password: "password123", guest: false, city: @city
    )
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "the reader does not see comments or replies by someone they blocked" do
    sign_in_as(@reader)

    get post_path(@post)

    assert_response :success
    assert_match "en vanlig kommentar", response.body
    assert_no_match "blokkert rotkommentar", response.body
    assert_no_match "blokkert svar", response.body
  end

  test "everyone else still sees them" do
    sign_in_as(@other)

    get post_path(@post)

    assert_match "blokkert rotkommentar", response.body
    assert_match "blokkert svar", response.body
  end
end
