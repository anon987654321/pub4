# frozen_string_literal: true

class Takeaway::OrderItem < ApplicationRecord
  belongs_to :order,     class_name: "Takeaway::Order"
  belongs_to :menu_item, class_name: "Takeaway::MenuItem"
  # Whose line this is on a shared ticket. Optional: every order that predates
  # group ordering is the host's own, and backfilling a guess would be worse
  # than saying nothing.
  belongs_to :user, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validate :menu_item_must_be_available

  def subtotal_cents = unit_price_cents * quantity
  def subtotal_display = Shared::MoneyDisplay.format(subtotal_cents)

  private

  def menu_item_must_be_available
    errors.add(:menu_item, :unavailable) unless menu_item&.available_for_order?
  end
end
