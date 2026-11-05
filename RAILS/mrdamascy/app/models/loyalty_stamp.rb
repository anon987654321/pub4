# frozen_string_literal: true

class LoyaltyStamp < ApplicationRecord
  belongs_to :user
  belongs_to :order, optional: true
  # The order whose free wrap this stamp paid for.
  belongs_to :redeemed_order, class_name: "Order", optional: true, inverse_of: :redeemed_stamps

  scope :unredeemed, -> { where(redeemed: false) }
  scope :redeemed, -> { where(redeemed: true) }
end
