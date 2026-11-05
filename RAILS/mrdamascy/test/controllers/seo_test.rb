# frozen_string_literal: true

require "test_helper"

# What search engines, answer surfaces and link previews read.
class SeoTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(@kitchen), description: "Kylling, toum og sylteagurk i gjæret brød.")
    seed_zone!(postcode: "5004", fee_ore: 2900, eta_minutes: 20)
    seed_zone!(postcode: "5005", fee_ore: 3900, eta_minutes: 35)
  end

  def head_of(url)
    get url
    Nokogiri::HTML(response.body)
  end

  test "a dish page describes itself and every page carries a share card" do
    page = head_of(menu_item_url(@item))
    assert_equal @item.description, page.at_css("meta[name=description]")["content"]
    assert_equal "http://www.example.com/og-card.png", page.at_css("meta[property='og:image']")["content"]
    assert_equal @item.name, page.at_css("meta[property='og:title']")["content"]
    assert_equal "summary_large_image", page.at_css("meta[name='twitter:card']")["content"]

    assert_equal I18n.t("app.description"), head_of(root_url).at_css("meta[name=description]")["content"]
  end

  test "the menu page carries Restaurant and Menu structured data" do
    script = head_of(root_url).at_css("script[type='application/ld+json']")
    data = JSON.parse(script.text)

    assert_equal "Restaurant", data["@type"]
    assert_equal %w[5054 Bergen], data["address"].values_at("postalCode", "addressLocality")
    assert_equal [ "Mo-Fr 11:00-21:00", "Sa-Su 14:00-21:00" ], data["openingHours"]
    assert_equal "129 kr–129 kr", data["priceRange"]
    dish = data["hasMenu"]["hasMenuSection"].first["hasMenuItem"].first
    assert_equal [ @item.name, "129.00", "NOK" ], [ dish["name"], *dish["offers"].values_at("price", "priceCurrency") ]
  end

  test "the hero states the zones' cheapest fee and slowest promise" do
    hero = head_of(root_url).at_css(".hero").text

    assert_includes hero, I18n.t("menu.delivery_facts", fee: "29 kr", eta: 35)
  end
end
