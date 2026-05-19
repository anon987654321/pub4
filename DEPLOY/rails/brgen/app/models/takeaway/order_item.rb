# frozen_string_literal: true

class Takeaway::OrderItem < ApplicationRecord
  belongs_to :order,     class_name: "Takeaway::Order"
  belongs_to :menu_item, class_name: "Takeaway::MenuItem"

  validates :quantity, numericality: { greater_than: 0 }

  def subtotal_cents = unit_price_cents * quantity
  def subtotal_display = "#{subtotal_cents / 100.0} NOK"
end
