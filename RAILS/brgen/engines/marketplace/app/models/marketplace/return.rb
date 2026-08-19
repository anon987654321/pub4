# frozen_string_literal: true

# Sending it back.
#
# Deliberately not offered on every order: the right to return a purchase
# (angrerett) is a right against a business, and a private sale between two
# people in the same city is not one. A listing with a store behind it is a
# shop's; a listing without one is somebody selling their own bike, and the
# seller is not obliged to take it back.
class Marketplace::Return < ApplicationRecord
  include Shared::Notifiable
  include Shared::StrictSafeAssociations

  # requested -> approved|refused, approved -> received. Money is a fourth thing
  # (refunded_at), and nothing in the tree moves it yet.
  STATUSES = %w[requested approved refused received].freeze
  # Fourteen days from delivery, which is the statutory floor for a distance
  # purchase from a business in Norway.
  WINDOW = 14.days

  belongs_to :order, class_name: "Marketplace::Order"
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: true, length: { maximum: 1_000 }
  validate :one_open_return_per_order, on: :create

  scope :open_returns, -> { where(status: %w[requested approved]) }

  def open? = status.in?(%w[requested approved])
  def refunded? = refunded_at.present?

  def approve!(by:, note: nil)
    resolve!("approved", by: by, note: note)
    deliver_notification(order_buyer, title: I18n.t("marketplace.return_approved_title"),
                                      body: note.presence || I18n.t("marketplace.return_approved_body"),
                                      source: self, kind: "order")
  end

  def refuse!(by:, note: nil)
    resolve!("refused", by: by, note: note)
    deliver_notification(order_buyer, title: I18n.t("marketplace.return_refused_title"),
                                      body: note.presence || I18n.t("marketplace.return_refused_body"),
                                      source: self, kind: "order")
  end

  # The seller has the item back. Stock returns here and not on approval: an
  # approved return that never arrives would otherwise put a thing back on the
  # shelf that is still in the post.
  def receive!(by:)
    transaction do
      update!(status: "received", resolved_by: by, resolved_at: Time.current)
      order_record&.restock_returned!
    end
    deliver_notification(order_buyer, title: I18n.t("marketplace.return_received_title"),
                                      body: I18n.t("marketplace.return_received_body"),
                                      source: self, kind: "order")
  end

  private

  def resolve!(status, by:, note:)
    update!(status: status, resolved_by: by, resolved_at: Time.current, resolution_note: note.presence)
  end

  def order_record = strict_safe(:order)
  def order_buyer = User.find_by(id: strict_safe_attribute(:order, :buyer_id))

  def one_open_return_per_order
    return if order_id.blank?

    errors.add(:base, :already_open) if self.class.open_returns.where(order_id: order_id).exists?
  end
end
