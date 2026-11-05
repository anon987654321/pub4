# frozen_string_literal: true

require "test_helper"

# Every photo of a garment carried the same alt and its lightbox link no name
# of its own; the colour swatch and the palette chips set their colour in a
# style attribute, which a CSP without 'unsafe-inline' refuses; and a palette
# chip had no colour name for a screen reader, only a hover title naming the item.
class ItemDetailPhotosTest < ActionDispatch::IntegrationTest
  setup do
    email = "photos-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @item = @user.items.create!(title: "Wool coat", category: "Outerwear", color: "navy")
  end

  def attach_photos(count)
    count.times do |index|
      @item.photos.attach(io: StringIO.new("photo-#{index}"), filename: "coat-#{index}.jpg", content_type: "image/jpeg")
    end
  end

  test "several photos are numbered in their alt text and their lightbox links" do
    attach_photos(2)

    get item_path(@item)
    assert_response :success
    [ 1, 2 ].each do |position|
      numbered = { title: "Wool coat", position:, count: 2 }
      assert_select "[data-controller=lightbox] a[aria-label=?] img[alt=?]",
                    I18n.t("items.open_photo", **numbered), I18n.t("items.photo_numbered", **numbered)
    end
  end

  test "a single photo is simply the garment" do
    attach_photos(1)

    get item_path(@item)
    assert_select "[data-controller=lightbox] a:not([aria-label]) img[alt=?]", "Wool coat"
  end

  test "the colour swatch is drawn without a style attribute" do
    get item_path(@item)
    assert_select "svg.color-swatch[role=img][aria-label=?] circle[fill]", I18n.t("items.color_named", color: "navy")
    assert_select ".color-swatch[style]", 0
  end

  test "a palette chip names its colour and its garment, with no inline style" do
    get ai_palette_path
    assert_response :success
    assert_select ".color-swatch-row .chip", text: /navy\s*, Wool coat/
    assert_select ".color-swatch-row .chip[title]", 0
    assert_select ".color-swatch-row svg.color-swatch[aria-hidden=true]"
    assert_select ".color-swatch-row [style]", 0
  end

  # Eight actions sat in one row. Worn today, joy and Edit stay in reach; AI
  # analysis, tagging, the declutter review and archiving sit under More tools.
  test "the item page leads with its everyday actions and folds the rest away" do
    get item_path(@item)
    nav = "nav.item-detail-actions"
    assert_select "#{nav} > form[action=?]", wear_item_path(@item)
    assert_select "#{nav} > a[href=?]", edit_item_path(@item)
    assert_select "#{nav} > details.wardrobe-more-tools > summary", text: I18n.t("wardrobe.more_tools")
    [ ai_analyze_item_path(@item), ai_tag_item_path(@item), archive_item_path(@item) ].each do |path|
      assert_select "#{nav} > details form[action=?]", path
    end
    assert_select "#{nav} > details a[href=?]", review_declutter_path(@item)
  end
end
