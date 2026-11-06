# frozen_string_literal: true

require "test_helper"

class CartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @category = seed_category!(@kitchen)
    @item = seed_item!(@category, name: "Damaskus Kylling Shawarma", price_ore: 12900)
  end

  test "add_item snapshots the price including paid options" do
    user = customer_sign_in
    extra_meat = seed_option!(@item, name: "Ekstra kjøtt", kind: "extra", price_ore: 2500)

    post add_item_cart_url, params: {
      menu_item_id: @item.id, quantity: 2, option_ids: [ extra_meat.id ], note: "Ekstra toum"
    }
    assert_includes [ 200, 302, 303 ], response.status

    cart = open_cart_for(user)
    assert_not_nil cart, "add_item must create the open cart for the signed-in user"

    line = cart.cart_items.sole
    assert_equal 2, line.quantity
    assert_equal 15400, line.unit_price_ore   # 12900 + 2500 option snapshot
    assert_equal 30800, line.line_total_ore
    assert_equal "Ekstra toum", line.note
  end

  test "add_item without options snapshots the plain price" do
    user = customer_sign_in

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }

    line = open_cart_for(user).cart_items.sole
    assert_equal 12900, line.unit_price_ore
  end

  test "add_item refuses an option that belongs to another dish" do
    user = customer_sign_in
    other = seed_item!(@category, name: "Adana Sterk Dürüm", position: 2)
    foreign = seed_option!(other, name: "Ekstra kjøtt", kind: "extra", price_ore: 2500)

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [ foreign.id ] }

    assert_redirected_to menu_item_path(@item)
    assert_empty open_cart_for(user)&.cart_items.to_a
  end

  test "add_item refuses a third sauce" do
    user = customer_sign_in
    sauces = 3.times.map { |n| seed_option!(@item, name: "Saus #{n}", kind: "sauce", position: n) }

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: sauces.map(&:id) }

    assert_redirected_to menu_item_path(@item)
    assert_empty open_cart_for(user)&.cart_items.to_a
  end

  test "add_item refuses a dish the kitchen has taken off the menu" do
    user = customer_sign_in
    @item.update!(available: false)

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }

    assert_redirected_to root_path
    assert_equal I18n.t("menu.sold_out"), flash[:alert]
    assert_empty open_cart_for(user)&.cart_items.to_a
  end

  test "update_item changes the quantity" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    line = open_cart_for(user).cart_items.sole

    patch update_item_cart_url(line.id), params: { quantity: 3 }

    assert_equal 3, line.reload.quantity
    assert_equal 38700, line.reload.line_total_ore
  end

  test "remove_item clears the line" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    line = open_cart_for(user).cart_items.sole

    delete remove_item_cart_url(line.id)

    assert_empty open_cart_for(user).reload.cart_items
  end

  test "cart page renders lines, totals and the Vipps CTA" do
    user = customer_sign_in
    cart = Cart.create!(user: user, delivery_mode: "delivery")
    CartItem.create!(cart: cart, menu_item: @item, quantity: 2,
                     unit_price_ore: 12900, option_ids: "")

    get cart_url
    assert_response :success

    assert_match "Damaskus Kylling Shawarma", response.body
    assert_match "258 kr", response.body       # subtotal 2 × 129 kr
    assert_match "Betal med Vipps", response.body
    assert_match "ingen kortfelter", response.body  # cart.steps_note
  end

  test "every id the cart streams target exists on the cart page" do
    customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }
    get cart_url
    page = Nokogiri::HTML(response.body)
    line = CartItem.sole

    delete remove_item_cart_url(line.id), as: :turbo_stream
    targets = response.body.scan(/target="([^"]+)"/).flatten.uniq

    assert_includes targets, "cart_item_#{line.id}"
    targets.each { |id| assert page.at_css("##{id}"), "the cart page has no ##{id} for its stream" }
  end

  test "the promo badge names the code checkout will apply, and only that" do
    customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }

    get cart_url
    assert_nil Nokogiri::HTML(response.body).at_css(".badge-promo"), "no active code, no badge"

    seed_promo!(code: "YALLA15", kind: "percent", value: 15)
    get cart_url
    assert_equal "YALLA15", Nokogiri::HTML(response.body).at_css(".badge-promo")&.text
  end

  test "quick-add, the stepper and the item sheet share one quantity ceiling" do
    user = customer_sign_in
    2.times { post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 15 } }
    line = open_cart_for(user).cart_items.sole
    assert_equal 20, line.quantity

    patch update_item_cart_url(line.id), params: { quantity: 99 }
    assert_equal 20, line.reload.quantity

    get menu_item_url(@item)
    sheet = Nokogiri::HTML(response.body)
    assert_equal "20", sheet.at_css("input#quantity")["max"]
    assert_equal "20", sheet.at_css("form.sheet-form")["data-item-sheet-max-value"]
  end

  test "a quick-add replaces the toast instead of stacking another" do
    customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id }, as: :turbo_stream

    assert_match(/<turbo-stream action="update" target="toasts">/, response.body)
    assert_no_match(/action="append"[^>]*targets="main"/, response.body)
  end

  test "an empty cart invites you back to the menu" do
    customer_sign_in

    get cart_url
    assert_response :success
    assert_match(/tom|Meny|menyen/, response.body)
  end

  test "the stepper streams the changed line and the subtotal back" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }
    line = open_cart_for(user).cart_items.sole

    patch update_item_cart_url(line.id), params: { quantity: 3 }, as: :turbo_stream

    stream = Nokogiri::HTML(response.body).at_css(%(turbo-stream[action="replace"][target="cart_contents"]))
    assert stream, "update_item must replace the cart contents"
    contents = Nokogiri::HTML(stream.at_css("template").inner_html)
    assert_equal "3", contents.at_css("#cart_item_#{line.id} .quantity-value").text
    assert_equal "387 kr", contents.at_css("#cart_item_#{line.id} .line-sum").text
    assert_equal "387 kr", contents.at_css(".cart-subtotal strong").text
    get cart_url
    assert Nokogiri::HTML(response.body).at_css("#cart_contents"), "the page carries the stream target"
  end

  test "the minus stays at one and removes the line" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }
    line = open_cart_for(user).cart_items.sole

    get cart_url
    minus = Nokogiri::HTML(response.body).at_css(%(#cart_item_#{line.id} form:first-child button.quantity-button))
    assert_equal "−", minus&.text, "a line at one still carries its minus"
    assert_equal I18n.t("cart.remove"), minus["aria-label"]
    assert_equal "0", minus.ancestors("form").first.at_css(%(input[name="quantity"]))["value"]

    patch update_item_cart_url(line.id), params: { quantity: 0 }, as: :turbo_stream
    assert_empty open_cart_for(user).reload.cart_items
    assert_match I18n.t("cart.empty_title"), response.body
  end

  test "cart and order lines show the menu card's food photo" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }

    get cart_url
    assert Nokogiri::HTML(response.body).at_css("img.line-photo"), "the cart line shows the dish photo"

    order = seed_order!(user:)
    OrderItem.create!(order:, menu_item_id: @item.id, name: @item.name, emoji: @item.emoji,
                      quantity: 1, unit_price_ore: 12_900, line_total_ore: 12_900)
    get order_url(order)
    assert Nokogiri::HTML(response.body).at_css(".order-line img.line-photo"), "the order line shows it too"
  end

  test "the pay-bar knows the cart path it pulses for" do
    customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }

    get root_url
    assert_equal cart_path, Nokogiri::HTML(response.body).at_css("#cart_bar")["data-cart-bar-cart-path-value"]
  end
end
