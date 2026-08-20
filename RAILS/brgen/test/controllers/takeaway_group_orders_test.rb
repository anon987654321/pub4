# frozen_string_literal: true

require "test_helper"

# Ordering for an office meant one person collecting everybody's choices in a
# chat and typing them in, which is where the wrong lunch comes from.
class TakeawayGroupOrdersTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @host = create_user("tg_host")
    @colleague = create_user("tg_colleague")
    ActsAsTenant.current_tenant = @city
    @restaurant = Takeaway::Restaurant.create!(
      user: @host, name: "Kafeen #{SecureRandom.hex(2)}", address: "Torget 1",
      cuisine_type: "Norwegian", city: @city, active: true,
      min_order_cents: 10_000, delivery_fee_cents: 4_900
    )
    @pizza = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Pizza", price_cents: 18_000, available: true)
    @salad = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Salat", price_cents: 12_000, available: true)
    @order = place_takeaway_order!(restaurant: @restaurant, user: @host, item: @pizza)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  test "the host opens the ticket and gets a token, not an id" do
    sign_in_as(@host)

    post takeaway.order_group_path(@order)
    @order.reload
    assert_predicate @order, :group?
    assert @order.group_open?
    assert_not_equal @order.id.to_s, @order.group_token
  end

  test "somebody with the link adds their own line, and the total follows" do
    @order.open_group!
    sign_in_as(@colleague)

    get takeaway.group_order_path(@order.group_token)
    assert_response :success

    assert_difference -> { @order.order_items.count }, 1 do
      patch takeaway.group_order_path(@order.group_token), params: { menu_item_id: @salad.id, quantity: 2 }
    end
    line = @order.order_items.order(:created_at).last
    assert_equal @colleague.id, line.user_id
    assert_equal 24_000, line.subtotal_cents
    assert_equal 18_000 + 24_000 + 4_900, @order.reload.total_cents
  end

  # A ticket where anyone can delete anyone's lunch is a ticket people stop
  # sharing.
  test "a line can be taken back only by whoever added it" do
    @order.open_group!
    sign_in_as(@colleague)
    patch takeaway.group_order_path(@order.group_token), params: { menu_item_id: @salad.id, quantity: 1 }
    line = @order.order_items.order(:created_at).last

    sign_in_as(@host)
    delete takeaway.group_order_path(@order.group_token, line_id: line.id)
    assert_response :not_found
    assert Takeaway::OrderItem.exists?(line.id)

    sign_in_as(@colleague)
    delete takeaway.group_order_path(@order.group_token, line_id: line.id)
    assert_not Takeaway::OrderItem.exists?(line.id)
  end

  # Once the kitchen has it, a late line is a different order rather than a
  # surprise on this one.
  test "a confirmed ticket takes no more lines" do
    @order.open_group!
    @order.transition_to!("confirmed")
    sign_in_as(@colleague)

    assert_no_difference -> { @order.order_items.count } do
      patch takeaway.group_order_path(@order.group_token), params: { menu_item_id: @salad.id, quantity: 1 }
    end
    assert_redirected_to takeaway.root_path
  end

  test "only the host opens the ticket" do
    sign_in_as(@colleague)

    post takeaway.order_group_path(@order)
    assert_response :not_found
    assert_not @order.reload.group?
  end

  # Splitting the fee four ways to the øre is a worse argument than paying it.
  test "shares name what each person owes, without the delivery fee" do
    @order.open_group!
    sign_in_as(@colleague)
    patch takeaway.group_order_path(@order.group_token), params: { menu_item_id: @salad.id, quantity: 1 }

    shares = Takeaway::Order.includes(order_items: :user).find(@order.id).shares
    assert_equal 18_000, shares[@host.id] || shares[nil]
    assert_equal 12_000, shares[@colleague.id]
  end
end
