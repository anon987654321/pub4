# frozen_string_literal: true

require "test_helper"

class LikeCountStreamTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze

  setup do
    @user = User.strict_loading(false).create!(
      email_address: "liker-#{SecureRandom.hex(4)}@amber.test", password: "password123"
    )
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  test "liking an outfit replaces its button and count in place" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    post like_outfit_path(outfit), headers: TURBO

    assert_response :success
    assert_equal 1, outfit.reload.likes_count
    assert_select "turbo-stream[action=replace][target=?]", "like_outfit_#{outfit.id}" do
      assert_select "template form#like_outfit_#{outfit.id} button", I18n.t("actions.like_count", count: 1)
    end
    assert_select "turbo-stream[action=replace][target=?]", "likes_outfit_#{outfit.id}"
  end

  test "liking an outfit without Turbo still redirects" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    post like_outfit_path(outfit)

    assert_redirected_to outfit_path(outfit)
  end

  test "the outfit page carries the ids the stream targets" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    get outfit_path(outfit)

    assert_select "form#like_outfit_#{outfit.id}"
    assert_select "span#likes_outfit_#{outfit.id}"
  end

  test "liking a post replaces its button in place" do
    record = @user.posts.create!(body: "Ny kåpe")

    post like_post_path(record), headers: TURBO

    assert_response :success
    assert_equal 1, record.reload.likes_count
    assert_select "turbo-stream[action=replace][target=?]", "like_post_#{record.id}" do
      assert_select "template form#like_post_#{record.id} button", I18n.t("post.like_count", count: 1)
    end
  end

  test "liking a post without Turbo still redirects and busts the cached card" do
    record = @user.posts.create!(body: "Ny kåpe")
    before = record.updated_at

    travel 1.second do
      post like_post_path(record)
    end

    assert_redirected_to posts_path
    assert_operator record.reload.updated_at, :>, before
  end
end
