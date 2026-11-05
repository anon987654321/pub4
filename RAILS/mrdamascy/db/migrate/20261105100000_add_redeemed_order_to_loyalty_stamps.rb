# frozen_string_literal: true

# A free wrap never spent the stamps that earned it, so a customer with nine
# stamps had every later order's wrap on the house. A redeemed stamp now names
# the order it paid for, so cancelling that order can give the stamps back.
class AddRedeemedOrderToLoyaltyStamps < ActiveRecord::Migration[8.0]
  def change
    add_reference :loyalty_stamps, :redeemed_order, foreign_key: { to_table: :orders }
  end
end
