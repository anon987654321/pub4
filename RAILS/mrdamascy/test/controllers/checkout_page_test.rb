# frozen_string_literal: true

require "test_helper"

# What the confirm screen renders before the customer taps a pay button.
class CheckoutPageTest < ActionDispatch::IntegrationTest
  setup do
    kitchen = seed_kitchen!
    seed_zone!(postcode: "5004", fee_ore: 2900, min_basket_ore: 10_000, eta_minutes: 20)
    @item = seed_item!(seed_category!(kitchen), price_ore: 12_900)
    customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }
  end

  def page
    get checkout_url
    assert_response :success
    Nokogiri::HTML(response.body)
  end

  test "both pay buttons lock while the order is being created" do
    buttons = page.css("button[name=payment_method]")

    assert_equal %w[stripe vipps], buttons.map { |b| b["value"] }.sort
    buttons.each { |b| assert_equal I18n.t("checkout.paying"), b["data-turbo-submits-with"] }
  end
end
