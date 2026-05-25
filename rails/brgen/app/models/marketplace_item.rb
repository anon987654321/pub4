# frozen_string_literal: true

class MarketplaceItem < ApplicationRecord
  self.table_name = "brgen_marketplace_items"
  enum :deal_type, { standard: 0, flash_deal: 1, voucher: 2 }, default: :standard
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  scope :active_offers, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  include Brgen::Localizable
end
