# frozen_string_literal: true

# A cancelled order whose payment was already taken needs its money back, and
# neither payment client can refund. The order now says so ("manual_due")
# until staff mark the refund made by hand ("refunded").
class AddRefundStateToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :refund_state, :string
  end
end
