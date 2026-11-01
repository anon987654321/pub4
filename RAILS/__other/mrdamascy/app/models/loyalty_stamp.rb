# frozen_string_literal: true

class LoyaltyStamp < ApplicationRecord
  belongs_to :user
  belongs_to :order, optional: true

  scope :unredeemed, -> { where(redeemed: false) }
  scope :redeemed, -> { where(redeemed: true) }
end
