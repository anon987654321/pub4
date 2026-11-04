# frozen_string_literal: true

# The kitchen and courier had a phone number but no name to address the
# customer by, and no way to hear the door code, the floor or "ring the
# bell". The order now carries both from the confirm screen.
class AddCustomerNameAndDeliveryNoteToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :customer_name, :string
    add_column :orders, :delivery_note, :string
  end
end
