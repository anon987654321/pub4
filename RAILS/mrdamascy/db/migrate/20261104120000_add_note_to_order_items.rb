# frozen_string_literal: true

# The cart line's note ("ekstra toum", "uten løk") was dropped at checkout,
# so the kitchen never saw it. The order snapshot keeps it beside the options.
class AddNoteToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :note, :string
  end
end
