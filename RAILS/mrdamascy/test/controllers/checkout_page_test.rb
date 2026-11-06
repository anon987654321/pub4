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

    assert_equal [ "Betal 158 kr med Vipps", "Betal 158 kr med kort" ], labels
  end

  test "the pay buttons leave the amount out while the delivery fee is unknown" do
    labels = page.css("button[name=payment_method]").map(&:text).map(&:squish)

    assert_equal [ I18n.t("checkout.vipps_cta"), I18n.t("checkout.stripe_cta") ], labels
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

  test "the fields say what they need and the card lane reads as a method" do
    form = page.at_css("form.checkout-form")

    assert form.at_css("input#address[required]")
    assert_equal "[0-9]{4}", form.at_css("input#postcode[required]")["pattern"]
    assert_equal I18n.t("checkout.phone_placeholder"), form.at_css("input#phone[required]")["placeholder"]
    assert_equal I18n.t("checkout.card_mark"), form.at_css(".stripe-wordmark").text
  end

  test "refused fields are named beside themselves and keep what was typed" do
    post checkout_url, params: { mode: "delivery", address: "", postcode: "50", phone: "90000009" }

    assert_response :unprocessable_entity
    assert_equal 0, Order.count
    form = Nokogiri::HTML(response.body)

    { address: "address_blank", postcode: "postcode_invalid" }.each do |field, key|
      input = form.at_css("input##{field}")
      assert_equal "#{field}_error", input["aria-describedby"]
      assert_equal "true", input["aria-invalid"]
      assert_equal I18n.t("checkout.errors.#{key}"), form.at_css("##{field}_error").text
    end
    assert_equal "90000009", form.at_css("input#phone")["value"]
    assert_nil form.at_css("#phone_error")
  end

  test "an unserved postcode is named beside the postcode field" do
    post checkout_url, params: { mode: "delivery", address: "Nygårdsgaten 12", postcode: "9999", phone: "90000009" }

    error = Nokogiri::HTML(response.body).at_css("#postcode_error")
    assert_equal I18n.t("flash.zone_error", postcode: "9999"), error&.text
  end

  test "an empty cart returns to the cart instead of offering zero-value payment" do
    Cart.last.empty!

    get checkout_url

    assert_redirected_to cart_url
    assert_nil flash[:alert], "the cart page says it is empty; no alert repeats it"
    follow_redirect!
    assert_response :success
    assert_includes response.body, I18n.t("cart.empty_title")
    assert_select "button[name=payment_method]", count: 0
  end

  test "a pickup order needs no address" do
    post checkout_url, params: { mode: "pickup", address: "", postcode: "", phone: "90000009" }

    assert_equal 1, Order.count
    assert_equal "pickup", Order.sole.delivery_mode
  end
end
