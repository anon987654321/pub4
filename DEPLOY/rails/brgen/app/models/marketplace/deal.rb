# frozen_string_literal: true

module Marketplace
  class Deal < ApplicationRecord
    self.table_name = "marketplace_deals"

    # Engine-ize Shared
    include Shared.concern(:Reactable) rescue nil
    include Shared.concern(:Notifiable) rescue nil
    belongs_to :listing, class_name: "Marketplace::Listing"

    validates :headline, presence: true, length: { maximum: 160 }
    validates :badge, length: { maximum: 64 }, allow_blank: true
    validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

    scope :active, -> {
      now = Time.current
      where("starts_at IS NULL OR starts_at <= ?", now)
        .where("ends_at IS NULL OR ends_at >= ?", now)
        .order(priority: :desc, created_at: :desc)
    }

    scope :featured, -> { where(featured: true) }

    def active?
      (starts_at.blank? || starts_at <= Time.current) && (ends_at.blank? || ends_at >= Time.current)
    end
  end
end
