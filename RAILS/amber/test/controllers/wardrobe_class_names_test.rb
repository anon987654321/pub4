# frozen_string_literal: true

require "test_helper"

# The wardrobe's cards and the item page are named for what they are, not for
# how they look: no "luxury" class, and the card's actions take their size
# from where they sit rather than from a button-small class on each.
class WardrobeClassNamesTest < ActionDispatch::IntegrationTest
  setup do
    email = "classes-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = @user.items.create!(title: "Wool coat", category: "Outerwear", color: "navy")
  end

  test "the item card's actions sit in item-card-actions and carry no size class" do
    get items_path
    assert_response :success
    card = "article.item-card.item-card--wardrobe##{ActionView::RecordIdentifier.dom_id(@item)}"
    assert_select "#{card} nav.item-card-actions form[action=?] button", wear_item_path(@item)
    assert_select "#{card} nav.item-card-actions a[href=?]", edit_item_path(@item)
    assert_select "#{card} .button-small", 0
    assert_select ".item-grid--wardrobe"
  end

  test "the stylesheet sizes the card's actions by where they sit" do
    scss = Rails.root.join("app/assets/stylesheets/application.scss").read
    compact = scss[/^\.button-small,\n\.button\.button-small,\n(?:.*,\n)*.*\{[^}]*\}/]
    assert compact, "the compact button rule is gone"
    assert_includes compact, ".item-card-actions :is(a, button)"
    assert_includes compact, "min-height: var(--tap-min)"
  end

  test "the item page names its photos, facts and actions" do
    @item.photos.attach(io: StringIO.new("photo"), filename: "coat.jpg", content_type: "image/jpeg")
    get item_path(@item)
    assert_response :success
    assert_select "article.item-detail.item-detail--wardrobe > .item-detail-layout" do
      assert_select ".item-detail-photos"
      assert_select ".item-detail-facts h1.item-detail-title", text: "Wool coat"
    end
    assert_select "dl.item-detail-fact-list"
    assert_select "nav.item-detail-actions"
  end

  test "no wardrobe page names a class after a look" do
    outfit = Outfit.create!(user: @user, name: "Autumn")
    [ items_path, item_path(@item), outfits_path, outfit_path(outfit), user_path(@user) ].each do |path|
      get path
      assert_response :success, path
      assert_select "[class*=luxury]", 0, "#{path} still names a class luxury"
    end
  end
end
