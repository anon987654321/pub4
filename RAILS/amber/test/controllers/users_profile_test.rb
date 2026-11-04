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
    assert_select "title", text: "#{@owner.display_name} — Amber"
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
    assert_select "a[href=?]", demo_wardrobe_path, text: I18n.t("home.browse_demo")

    post session_path, params: { email_address: @owner.email_address, password: "password" }
    get user_path(@owner)
    assert_select "a[href=?]", new_post_path, text: I18n.t("empty.first_post")
    assert_select "a[href=?]", new_item_path, text: I18n.t("home.first_item")
  end

  test "a guest who may not see the wardrobe sees no outfits" do
    get user_path(@owner)
    assert_response :success
    assert_select "article##{ActionView::RecordIdentifier.dom_id(@outfit)}", 0
  end

  # robots.txt disallowed /users/ while the profile answered every guest, so a
  # linked profile could be listed by URL with no way for a crawler to read a
  # noindex. The profile now says noindex and robots.txt lets it be read.
  test "a member profile is crawlable and says noindex" do
    get user_path(@owner)
    assert_select "head meta[name=robots][content=?]", "noindex, follow"
    robots = Rails.public_path.join("robots.txt").read
    assert_no_match %r{^Disallow: /users}, robots
  end

  # Recent pieces were a bare link around an image and a <p>, unlike any card
  # in the wardrobe or the demo.
  test "recent pieces render as wardrobe cards without owner actions" do
    item = @owner.items.create!(title: "Wool coat", category: "Outerwear", color: "navy")
    post session_path, params: { email_address: @owner.email_address, password: "password" }

    get user_path(@owner)
    assert_select ".item-grid article.item-card##{ActionView::RecordIdentifier.dom_id(item)}" do
      assert_select ".item-photo--placeholder", text: "O"
      assert_select "a.item-title[href=?]", item_path(item), text: "Wool coat"
      assert_select ".item-meta span", text: "navy"
      assert_select "form", 0
    end
  end
end
