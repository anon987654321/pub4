# frozen_string_literal: true

require "test_helper"

# What the confirm screen asks and shows beyond the address: the cart
# itself, the customer's name and a note for the courier.
class CheckoutDetailsTest < ActionDispatch::IntegrationTest
  setup do
    kitchen = seed_kitchen!
    seed_zone!(postcode: "5004", min_basket_ore: 10_000)
    @item = seed_item!(seed_category!(kitchen), price_ore: 12_900)
    @user = customer_sign_in(name: "Layla Haddad")
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 2, note: "Ekstra toum" }
  end

  test "the confirm screen lists the cart lines under one summary" do
    get checkout_url
    details = Nokogiri::HTML(response.body).at_css("details.checkout-lines")

    assert_includes details.at_css("summary").text, "258 kr"
    line = details.at_css("li.order-line")
    assert_includes line.text, "2× Damaskus Kylling Shawarma"
    assert_includes line.text, "Ekstra toum"
  end

  test "the name is prefilled and the note rides onto the order, board and run" do
    get checkout_url
    form = Nokogiri::HTML(response.body)
    assert_equal "Layla Haddad", form.at_css("input#name[autocomplete=name]")["value"]

    post checkout_url, params: { mode: "delivery", address: "Nygårdsgaten 12", postcode: "5004",
                                 phone: "90000004", name: "Layla H.", delivery_note: "Kode 1234, 3. etg" }
    order = Order.sole
    assert_equal "Layla H.", order.customer_name
    assert_equal "Kode 1234, 3. etg", order.delivery_note

    order.update!(state: "ready")
    sign_out
    staff_sign_in
    get staff_board_url
    card = Nokogiri::HTML(response.body).at_css("#order_card_#{order.id}")
    assert_includes card.text, "Layla H."
    assert_includes card.text, "Kode 1234, 3. etg"

    sign_out
    courier_sign_in
    get courier_runs_url
    assert_includes Nokogiri::HTML(response.body).at_css(".run-stop").text, "Kode 1234, 3. etg"
  end

  test "a pickup order carries no delivery note" do
    post checkout_url, params: { mode: "pickup", phone: "90000004", delivery_note: "Kode 1234" }

    assert_nil Order.sole.delivery_note
  end
end
