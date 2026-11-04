# frozen_string_literal: true

class OrderItem < ApplicationRecord
  belongs_to :order
  # The dish this line was taken from, while it is still on the menu.
  belongs_to :menu_item, optional: true

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_ore, :line_total_ore,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
