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

  def line_total_ore
    unit_price_ore.to_i * quantity
  end
end
