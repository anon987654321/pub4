# frozen_string_literal: true

require "test_helper"

class MenuControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @wraps = seed_category!(@kitchen, name: "Wraps & Ruller", slug: "wraps", emoji: "🌯")
    @item = seed_item!(@wraps, name: "Damaskus Kylling Shawarma", price_ore: 12900)
  end

  test "root renders the catalog with the seeded items" do
    get root_url
    assert_response :success

    assert_match "Damaskus Kylling Shawarma", response.body
    assert_match "129 kr", response.body                       # money(12900)
    assert_match(/4[.,]9/, response.body)                      # kitchen rating ⭐
    assert_match "11–21", response.body                        # opening hours
    assert_match "Wraps &amp; Ruller", response.body  # HTML-escaped in the section title               # category section
  end

  test "a menu card is named by everything it shows, not the dish name alone" do
    get root_url
    card = Nokogiri::HTML(response.body).at_css("a.item-card-hit")

    assert_nil card["aria-label"]
    assert_includes card.text, @item.name
    assert_includes card.text, "450 g"
  end

  test "the item page shows the origin story and the options" do
    seed_option!(@item, name: "Toum", kind: "sauce", default_on: true)
    seed_option!(@item, name: "Salat", kind: "topping")

    get menu_item_url(@item)
    assert_response :success

    assert_match "Souq al-Hamidiyah", response.body  # origins.damaskus story
    assert_match "Toum", response.body
    assert_match "Salatbar", response.body           # free toppings presented as salatbar
    assert_match "Legg i kurv", response.body        # sticky add button
  end

  test "the reorder card greets returning customers with Yalla igjen" do
    user = customer_sign_in
    order = seed_order!(user: user, kitchen: @kitchen, state: "delivered")
    # The card renders only when the last order carries lines.
    order.order_items.create!(name: "Damaskus Kylling Shawarma", quantity: 1,
                              unit_price_ore: 12900, line_total_ore: 25800)

    get root_url
    assert_response :success
    assert_match "Yalla igjen", response.body
  end

  test "guests do not see the reorder card" do
    get root_url
    assert_response :success
    assert_no_match(/Yalla igjen/, response.body)
  end

  test "sold-out items stay off the menu" do
    seed_item!(@wraps, name: "Hemmelig test-wrap", name_en: "Secret test wrap",
               available: false)

    get root_url
    assert_response :success
    assert_no_match(/Hemmelig test-wrap/, response.body)
  end

  test "the sauce legend states the cap and the sheet carries its polite notice" do
    seed_option!(@item, name: "Toum", kind: "sauce")

    get menu_item_url(@item)
    page = Nokogiri::HTML(response.body)
    legend = page.css("fieldset.option-group legend").find { |node| node.text.include?(I18n.t("menu.sauces")) }

    assert_includes legend.text, I18n.t("menu.sauce_limit", count: Cart::MAX_SAUCES)
    notice = page.at_css("[data-item-sheet-target=sauceNotice]")
    assert_equal "polite", notice["aria-live"]
    assert_equal I18n.t("menu.sauce_limit_reached"), page.at_css("form.sheet-form")["data-item-sheet-sauce-limit-value"]
  end

  test "food photos are sized WebP pictures with a reserved box" do
    get menu_item_url(@item)
    picture = Nokogiri::HTML(response.body).at_css(".sheet-head picture")
    img = picture.at_css("img.sheet-photo")

    assert_equal %w[320 320 async], [img["width"], img["height"], img["decoding"]]
    srcset = picture.at_css("source[type='image/webp']")["srcset"]
    assert_match(%r{food/damaskus-kylling-shawarma-320-\h+\.webp 320w, .*-640-\h+\.webp 640w}, srcset)
    ApplicationHelper::FOOD_PHOTOS.each_value do |photo|
      ApplicationHelper::FOOD_PHOTO_WIDTHS.each do |width|
        assert Rails.root.join("app/assets/images", photo.sub(".jpg", "-#{width}.webp")).file?, "#{photo} at #{width}"
      end
    end

    get root_url
    card = Nokogiri::HTML(response.body).at_css(".item-card picture img.item-photo")
    assert_equal %w[56 lazy], [card["width"], card["loading"]]
  end

  test "the category chips are watched for the section in view" do
    get root_url
    nav = Nokogiri::HTML(response.body).at_css("nav.category-chips")

    assert_equal "category-spy", nav["data-controller"]
    assert_equal "chip", nav.at_css("a.chip")["data-category-spy-target"]
  end
end
