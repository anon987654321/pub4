# frozen_string_literal: true

class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :menu_item

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_ore, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # option_ids is the comma list of selected ItemOption ids ("" = none).
  def selected_option_ids
    option_ids.to_s.split(",").map { |id| Integer(id) }
  end

  # Human list of the chosen options — the cart line and the order snapshot
  # both render this.
  def options_list
    ItemOption.where(id: selected_option_ids).order(:position, :id).map(&:name)
  end

  # Moves this line into another cart, adding to a matching line there.
  def move_to!(other)
    same = other.cart_items.find_by(menu_item_id:, option_ids:, note:)
    return update!(cart: other) unless same

    same.update!(quantity: same.quantity + quantity)
    destroy!
  end

# The frozen copy an order keeps of this line (Order#snapshot_from_cart!):
# name, price, options and the customer's note as they were at checkout.
def order_line_attributes
  { menu_item_id:, name: menu_item.name, emoji: menu_item.emoji, quantity:, unit_price_ore:,
    options_text: options_list.join(", ").presence, note: note.presence, line_total_ore: }
end

  def line_total_ore
    unit_price_ore.to_i * quantity
  end
end
