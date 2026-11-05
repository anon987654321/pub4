# frozen_string_literal: true

require "test_helper"

# The 14 EU allergens before purchase: the item sheet names them, says a dish
# holds none, or, until the kitchen records them, says so and to call.
class ItemAllergensTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(@kitchen))
  end

  def allergen_line
    get menu_item_url(@item)
    assert_response :success
    Nokogiri::HTML(response.body).at_css(".sheet-allergens p").text
  end

  test "a dish the kitchen has not recorded says so and gives the kitchen's number" do
    assert_equal I18n.t("menu.allergens.unknown_call", phone: @kitchen.phone), allergen_line
  end

  test "a recorded dish names its allergens" do
    @item.update!(allergens: "gluten,milk,sesame")

    assert_equal "Inneholder gluten, melk, sesamfrø.", allergen_line
  end

  test "a dish recorded as free of all fourteen says that" do
    @item.update!(allergens: "none")

    assert_equal I18n.t("menu.allergens.none"), allergen_line
  end
end
