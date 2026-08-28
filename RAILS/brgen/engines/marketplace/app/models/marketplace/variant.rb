# frozen_string_literal: true

# One buyable version of a listing: this shirt in medium, in blue.
#
# The listing keeps the description, the photos and the seller; the variant
# carries what differs — price when it differs, stock always, because stock is
# the thing a shared column gets wrong. A shop with four sizes on one
# `listings.stock` either lists the shirt four times or oversells the medium.
class Marketplace::Variant < ApplicationRecord
  include Shared::StrictSafeAssociations

  belongs_to :listing, class_name: "Marketplace::Listing"
  has_many :options, -> { order(:name) }, class_name: "Marketplace::VariantOption",
           foreign_key: :variant_id, dependent: :destroy, inverse_of: :variant
  # :restrict_with_error for the same reason a listing refuses it: an order is a
  # buyer's receipt, and the seller who retires a size does not own the buyer's
  # half of it.
  has_many :orders, class_name: "Marketplace::Order", foreign_key: :variant_id,
           dependent: :restrict_with_error, inverse_of: :variant

  accepts_nested_attributes_for :options, allow_destroy: true

  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :sku, length: { maximum: 60 }, allow_blank: true

  scope :in_stock, -> { where(stock: nil).or(where(stock: 1..)) }
  scope :ordered, -> { order(:position, :id) }

  # nil price means "the listing's", so a shop varying only the size states the
  # price once. Restating it per variant is how the two drift apart.
  def price_cents_or_listing = price_cents.presence || strict_safe_attribute(:listing, :price_cents).to_i
  def price_display = Shared::MoneyDisplay.format(price_cents_or_listing, strict_safe_attribute(:listing, :currency) || "NOK")

  # nil stock is the listing's own one-of-a-kind meaning: there is one, until it
  # is sold.
  def unlimited_stock? = stock.nil?
  def in_stock? = unlimited_stock? || stock.to_i.positive?

  def consume_stock!(quantity = 1)
    raise "variant is not in stock" unless in_stock?
    return if unlimited_stock?

    update_columns(stock: [ stock.to_i - quantity.to_i, 0 ].max, updated_at: Time.current)
  end

  # "M · Blå" — what the buyer picks from, built from the option rows rather
  # than stored, so renaming an option cannot leave a stale label behind.
  def label
    parts = options.map(&:value)
    parts.any? ? parts.join(" · ") : sku.presence || "—"
  end
end
