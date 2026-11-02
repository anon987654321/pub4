# frozen_string_literal: true

class DeliveryZone < ApplicationRecord
  validates :postcode, presence: true, uniqueness: true
  validates :name, :fee_ore, :min_basket_ore, :eta_minutes, presence: true
  validates :fee_ore, :min_basket_ore, :eta_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # The checkout asks by postcode; "0170 " and "0170" are the same zone.
  # Returns the zone record or nil.
  def self.for_postcode(postcode)
    return nil if postcode.blank?

    find_by(postcode: postcode.to_s.gsub(/\s+/, ""))
  end

  # Zone rule (APP_SPEC §4): the basket must clear the zone minimum before the
  # order may go out for delivery.
  def covers?(subtotal_ore)
    subtotal_ore.to_i >= min_basket_ore.to_i
  end
end
