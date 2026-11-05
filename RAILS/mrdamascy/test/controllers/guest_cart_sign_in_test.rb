# frozen_string_literal: true

require "test_helper"

# A guest who fills the basket and then signs in at checkout keeps it.
class GuestCartSignInTest < ActionDispatch::IntegrationTest
  setup do
    @item = seed_item!(seed_category!(seed_kitchen!), price_ore: 12_900)
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 2 }
  end

  def lines_of(phone) = Cart.find_by!(user: User.find_by!(phone:)).cart_items

  test "a guest basket is still there on the next page" do
    get cart_url
    assert_match @item.name, response.body
  end

  test "signing in with a phone code carries the guest basket over" do
    post session_request_code_url, params: { phone: "90000021" }
    post session_url, params: { phone: "90000021", code: "1234" }

    assert_equal [ [ @item.id, 2 ] ], lines_of("90000021").pluck(:menu_item_id, :quantity)
    assert_equal 0, Cart.where(user_id: nil).joins(:cart_items).count
  end

  test "signing in with Vipps adds the guest basket to the saved one" do
    user = User.create!(phone: "90000022", name: "Lina", role: ROLES.fetch(:customer))
    saved = Cart.create!(user:, session_key: "other-device")
    saved.add_item!(@item, 1)

    get session_vipps_path(to: "checkout")
    get session_vipps_callback_path, params: { state: session[:vipps_login_state], phone: user.phone }

    assert_equal [ [ @item.id, 3 ] ], lines_of("90000022").pluck(:menu_item_id, :quantity)
  end

  test "after signing out the browser does not get the customer's cart back" do
    post session_request_code_url, params: { phone: "90000023" }
    post session_url, params: { phone: "90000023", code: "1234" }
    delete session_url

    get cart_url
    assert_no_match @item.name, response.body
  end
end
