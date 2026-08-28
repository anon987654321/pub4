# frozen_string_literal: true

module Marketplace
  class Store < ApplicationRecord
    include CityTenantable

    # Engine-ized Shared
    include Shared::Notifiable
    tracks_activity created: "MarketplaceStoreCreated", updated: "MarketplaceStoreUpdated", source_vertical: "marketplace", actor: :owner
    include Shared::GeoLocatable
    include Shared::Reactable

    self.table_name = "marketplace_stores"

    VERTICALS = %w[
      groceries homewares furniture electronics fashion beauty sports toys
      garden automotive pets books health local_services other
    ].freeze

    belongs_to :owner, class_name: "User"
    belongs_to :place, optional: true
    has_many :listings, class_name: "Marketplace::Listing", dependent: :nullify
    has_many :payouts, class_name: "Marketplace::Payout", dependent: :restrict_with_error

    validates :name, presence: true, length: { maximum: 160 }
    validates :slug, presence: true, uniqueness: true, length: { maximum: 180 }
    validates :vertical, inclusion: { in: VERTICALS }, allow_blank: true
    validates :description, length: { maximum: 4_000 }, allow_blank: true
    validates :stripe_connect_id, format: { with: Marketplace::Payments::StripeTransfer::ACCOUNT }, allow_blank: true

    before_validation :default_slug

    scope :active, -> { where(active: true) }
    scope :verified, -> { where(verified: true) }
    scope :by_vertical, ->(vertical) { where(vertical: vertical) if vertical.present? }
    scope :recent, -> { order(created_at: :desc) }

    def grocery?
      vertical == "groceries"
    end

    # StoresController looks up by slug (find_by!(slug: params[:id])), so path
    # helpers must emit the slug, not the numeric id — otherwise /shops/<id> 404s.
    def to_param = slug.presence || id.to_s

    private

    def default_slug
      self.slug = name.to_s.parameterize if slug.blank? && name.present?
    end
  end
end
