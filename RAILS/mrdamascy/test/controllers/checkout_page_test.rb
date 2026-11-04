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
  test "the delivery or pickup choice is kept on the cart" do
    get checkout_url(mode: "pickup")
    get cart_url

    pickup = Nokogiri::HTML(response.body).at_css(".mode-toggle a[href*=\"mode=pickup\"]")
    assert_equal "true", pickup["aria-current"]
  end

  test "the confirm screen shows the whole bill before the tap" do
    User.last.update!(default_postcode: "5004")
    seed_promo!(code: "YALLA10", kind: "fixed", value: 1000)
    section = page.at_css("section.totals")
    totals = section.text.squish

    assert_includes totals, "#{I18n.t('checkout.discount')} −10 kr"
    assert_includes totals, "#{I18n.t('checkout.delivery_fee')} 29 kr"
    assert_includes totals, "#{I18n.t('checkout.total')} 148 kr"
    assert_includes totals, I18n.t("checkout.eta_delivery", eta: 20)
  end

  test "the pay buttons name the amount once it is settled" do
    User.last.update!(default_postcode: "5004")
    labels = page.css("button[name=payment_method]").map(&:text).map(&:squish)

    assert_equal ["Betal 158 kr med Vipps", "Betal 158 kr med kort"], labels
  end

  test "the pay buttons leave the amount out while the delivery fee is unknown" do
    labels = page.css("button[name=payment_method]").map(&:text).map(&:squish)

    assert_equal [I18n.t("checkout.vipps_cta"), I18n.t("checkout.stripe_cta")], labels
  end

  test "the zone answer carries this cart's fee, total, ETA and pay labels" do
    get checkout_zone_path(postcode: "5004"), as: :json
    answer = response.parsed_body

    assert_equal 10_000, answer["min_basket_ore"]
    assert_equal "29 kr", answer["fee_text"]
    assert_equal "158 kr", answer["total_text"]
    assert_equal I18n.t("checkout.eta_delivery", eta: 20), answer["eta_text"]
    assert_nil answer["minimum_text"]
    assert_equal "Betal 158 kr med Vipps", answer["vipps_label"]
  end

  test "a basket under the zone minimum is named before the tap" do
    seed_zone!(postcode: "5005", name: "Nordnes", fee_ore: 2900, min_basket_ore: 20_000, eta_minutes: 25)
    get checkout_zone_path(postcode: "5005"), as: :json
    assert_equal I18n.t("checkout.min_basket_fail", amount: "71 kr", name: "Nordnes"),
                 response.parsed_body["minimum_text"]

    User.last.update!(default_postcode: "5005")
    warning = page.at_css("[data-zone-check-target=minimum]")
    assert_equal I18n.t("checkout.min_basket_fail", amount: "71 kr", name: "Nordnes"), warning.text
    assert_nil warning["hidden"]
  end

  test "the zone lookup url comes from the route" do
    get checkout_url, env: { "SCRIPT_NAME" => "/mat" }
    form = Nokogiri::HTML(response.body).at_css("form.checkout-form")

    assert_equal "/mat/checkout/zone", form["data-zone-check-url-value"]
  end
end
