# frozen_string_literal: true

module Marketplace
  class Store < ApplicationRecord
    # Engine-ized Shared
    include Shared.concern(:Notifiable) rescue nil
    include Shared.concern(:ActivityTrackable) rescue nil
    include Shared.concern(:GeoLocatable) rescue nil
    include Shared.concern(:Reactable) rescue nil

    self.table_name = "marketplace_stores"

    VERTICALS = %w[
      groceries homewares furniture electronics fashion beauty sports toys
      garden automotive pets books health local_services other
    ].freeze

    belongs_to :owner, class_name: "User"
    has_many :listings, class_name: "Marketplace::Listing", dependent: :nullify

    validates :name, presence: true, length: { maximum: 160 }
    validates :slug, presence: true, uniqueness: true, length: { maximum: 180 }
    validates :vertical, inclusion: { in: VERTICALS }, allow_blank: true
    validates :description, length: { maximum: 4_000 }, allow_blank: true

    before_validation :default_slug

    scope :active, -> { where(active: true) }
    scope :verified, -> { where(verified: true) }
    scope :by_vertical, ->(vertical) { where(vertical: vertical) if vertical.present? }
    scope :recent, -> { order(created_at: :desc) }

    def grocery?
      vertical == "groceries"
    end

    private

    def default_slug
      self.slug = name.to_s.parameterize if slug.blank? && name.present?
    end
  end
end
