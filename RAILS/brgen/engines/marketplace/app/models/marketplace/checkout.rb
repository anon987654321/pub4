# frozen_string_literal: true

# One basket, one payment, one delivery address, many orders.
#
# The per-listing Marketplace::Order stays exactly what it was — an offer,
# which is the right shape for a bike from a stranger. This sits above them so
# that buying four things from a shop is one card charge and one address rather
# than four of each.
class Marketplace::Checkout < ApplicationRecord
  include Shared::Notifiable

  STATUSES = %w[open pending_payment paid cancelled].freeze

  belongs_to :user
  belongs_to :marketplace_address, class_name: "Marketplace::Address", optional: true
  has_many :orders, class_name: "Marketplace::Order",
           foreign_key: :marketplace_checkout_id, dependent: :nullify, inverse_of: :checkout

  validates :status, inclusion: { in: STATUSES }

  scope :open_baskets, -> { where(status: "open") }

  # ApplicationRecord is strict_loading by default and a checkout is usually
  # found by id — from a controller, a PSP webhook, a job — with nothing
  # preloaded, so every read of `orders` here raised. Same shape as
  # Shared::StrictSafeAssociations, which only covers belongs_to.
  def order_lines
    return orders if association(:orders).loaded?

    Marketplace::Order.strict_loading(false).where(marketplace_checkout_id: id)
  end

  # Recomputed rather than accumulated. A price can change between adding to the
  # basket and paying, and a total that was summed once is a total that is
  # eventually wrong.
  def recalculate!
    update!(total_cents: order_lines.sum(&:total_cents))
  end

  def payable? = status.in?(%w[open pending_payment]) && order_lines.any?

  # A basket already sent to the PSP is payable (webhook) but not startable.
  def startable? = status == "open" && order_lines.any?

  def total_display = Shared::MoneyDisplay.format(total_cents, currency)

  # The payable interface the payment services read. A basket has no single
  # listing, which is exactly why they stopped reading one.
  def payment_currency = currency.presence || "NOK"

  def payment_description
    titles = order_lines.includes(:listing).map { |order| order.listing.title }
    return titles.first.to_s if titles.one?

    "#{titles.first} + #{titles.size - 1} more"
  end

  def mark_payment_pending!(provider:, reference:)
    raise "checkout is not payable" unless payable?

    transaction do
      update!(status: "pending_payment", payment_provider: provider, payment_reference: reference)
      order_lines.each { |order| order.mark_payment_pending!(provider: provider, reference: reference) }
    end
  end

  # One payment clears every order in the basket. Done in a transaction because
  # a half-paid basket — some orders paid, some not, one card charged — is the
  # state nobody has a way to resolve.
  def mark_paid!(reference: payment_reference)
    transaction do
      update!(status: "paid", paid_at: Time.current, payment_reference: reference.presence || payment_reference)
      order_lines.each { |order| order.mark_paid!(reference: reference) }
    end
  end

  # A basket spanning three sellers is three deliveries, and each seller only
  # ever sees their own line. Grouping here rather than in the view because the
  # notification and the seller dashboard need the same split.
  def orders_by_seller
    order_lines.includes(listing: :user).group_by { |order| order.listing.user_id }
  end
end
