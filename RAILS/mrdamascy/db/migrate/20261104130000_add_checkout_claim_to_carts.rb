# frozen_string_literal: true

# A double-tapped pay button posted the confirm form twice: the second
# request either built a second order or, after the first emptied the cart,
# landed on "cart empty" while the first order waited for payment. The cart
# now claims its checkout, and the order remembers the cart it came from so
# a repeat post is sent on to that order's payment.
class AddCheckoutClaimToCarts < ActiveRecord::Migration[8.0]
  def change
    add_column :carts, :checkout_started_at, :datetime
    add_reference :orders, :cart, foreign_key: false, index: true
  end
end
