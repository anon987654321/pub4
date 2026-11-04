# frozen_string_literal: true

require "test_helper"

# UsersController#show loaded @outfits under the wardrobe visibility policy
# and users/show never drew them, so a profile showed pieces but no looks.
class UsersProfileTest < ActionDispatch::IntegrationTest
  setup do
    email = "owner-#{SecureRandom.hex(4)}@example.test"
    @owner = User.strict_loading(false).create!(email_address: email, password: "password")
    @outfit = Outfit.strict_loading(false).create!(user: @owner, name: "Fredagsantrekk")
  end

  test "the owner sees their outfits on their profile" do
    post session_path, params: { email_address: @owner.email_address, password: "password" }

    get user_path(@owner)
    assert_response :success
    assert_select "h2", text: I18n.t("users.outfits")
    assert_select ".item-grid article##{ActionView::RecordIdentifier.dom_id(@outfit)}"
  end

  # Posts rendered as bare siblings, and the empty state invited whoever was
  # looking at the profile to write their first post.
  test "profile posts are list items" do
    Post.create!(user: @owner, body: "Ny jakke")

    get user_path(@owner)
    assert_select "ul.post-card-list > li", 1
  end

  test "only the owner is invited to write a first post" do
    get user_path(@owner)
    assert_select "a[href=?]", new_post_path, 0

    post session_path, params: { email_address: @owner.email_address, password: "password" }
    get user_path(@owner)
    assert_select "a[href=?]", new_post_path, text: I18n.t("empty.first_post")
  end

  test "a guest who may not see the wardrobe sees no outfits" do
    get user_path(@owner)
    assert_response :success
    assert_select "article##{ActionView::RecordIdentifier.dom_id(@outfit)}", 0
  end
end
