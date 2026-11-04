# frozen_string_literal: true

require "test_helper"

# The English mirror: the menu's own copy, and a choice that lasts.
class LocaleTest < ActionDispatch::IntegrationTest
  setup do
    kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(kitchen), description: "Kylling i gjæret brød.")
    @item.update!(description_en: "Chicken in leavened bread.")
    ItemOption.create!(menu_item: @item, name: "Hvitløkssaus", name_en: "Garlic sauce", kind: "sauce",
                       price_ore: 0, position: 1)
  end

  test "the menu prints the English names under ?locale=en" do
    get root_url(locale: "en")
    page = Nokogiri::HTML(response.body)

    assert_includes page.at_css(".menu-section .section-title").text, "Wraps & Rolls"
    assert_equal "Damascus Chicken Shawarma", page.at_css(".item-name").text

    get root_url(locale: "nb")
    assert_equal "Damaskus Kylling Shawarma", Nokogiri::HTML(response.body).at_css(".item-name").text
  end

  test "the item sheet prints the English name, description and options" do
    get menu_item_url(@item, locale: "en")
    sheet = Nokogiri::HTML(response.body)

    assert_equal "Damascus Chicken Shawarma", sheet.at_css(".sheet-name").text
    assert_equal "Chicken in leavened bread.", sheet.at_css(".sheet-description").text
    assert_equal "Garlic sauce", sheet.at_css(".option-name").text
  end

  test "the chosen language lasts to the next link and can be switched back" do
    get root_url(locale: "en")
    get cart_url

    page = Nokogiri::HTML(response.body)
    assert_equal "en", page.at_css("html")["lang"]
    assert_includes page.at_css(".tab-bar a.tab")["href"], "locale=en"

    get about_url
    switch = Nokogiri::HTML(response.body).at_css("nav.language-switch")
    assert_equal "true", switch.at_css("a[lang=en]")["aria-current"]

    get about_url(locale: "nb")
    get cart_url
    assert_equal "nb", Nokogiri::HTML(response.body).at_css("html")["lang"]
  end
end
