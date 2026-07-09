# frozen_string_literal: true

class AffiliateLink < ApplicationRecord
  belongs_to :item

  validates :url, :merchant, presence: true
  validates :url, length: { maximum: 2_000 }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
