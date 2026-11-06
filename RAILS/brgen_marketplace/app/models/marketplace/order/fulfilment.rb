# frozen_string_literal: true

class Marketplace::Order
  # Where the parcel is after payment. The seller says it has gone and that it
  # arrived; the buyer confirms it did. Only that confirmation, or
  # RECEIPT_WINDOW of silence, creates a shop's payout: a seller's word alone
  # never moves money to a store.
  module Fulfilment
    extend ActiveSupport::Concern

    # How long a buyer has to confirm a parcel the seller has marked delivered.
    # Silence for this long, with no return open, counts as receipt: it is the
    # same fourteen days as the return window, so a buyer who says nothing has
    # had the whole of it.
    RECEIPT_WINDOW = 14.days

    included do
      # Delivered on the seller's word, unconfirmed for RECEIPT_WINDOW, and no
      # return open. Marketplace::ConfirmReceiptJob confirms these.
      scope :receipt_overdue, lambda {
        where(fulfilment_status: "delivered", receipt_confirmed_at: nil, payment_status: "paid")
          .where(delivered_at: ..RECEIPT_WINDOW.ago)
          .where.not(id: Marketplace::Return.open_returns.select(:order_id))
      }
    end

    # A paid parcel the seller can say has gone, correct the tracking of while
    # it is on its way, or say has arrived.
    def shippable? = payment_status == "paid" && fulfilment_status.in?(%w[unfulfilled shipped])

    # Delivered on the seller's word and not yet confirmed.
    def awaiting_receipt? = fulfilment_status == "delivered" && receipt_confirmed_at.nil?

    def receipt_confirmable_by?(user) = user.present? && user.id == buyer_id && awaiting_receipt?

    # Shipping is the seller telling the buyer where the parcel is. Notified on
    # the transition rather than left as a status for the buyer to poll, because
    # nobody polls an order page.
    def ship!(tracking_code: nil, carrier: nil)
      transitioned = false
      with_lock do
        already_shipped = fulfilment_status == "shipped"
        update!(fulfilment_status: "shipped", tracking_code: tracking_code, carrier: carrier, shipped_at: Time.current)
        transitioned = !already_shipped
      end
      return self unless transitioned

      metadata = { order_id: id, carrier: carrier }
      record_listing_commerce_event("MarketplaceOrderShipped", actor: seller, metadata: metadata)
      record_listing_event("shipped", user: seller, metadata: metadata)
      notify_buyer(I18n.t("marketplace.order_notification.on_its_way"), shipment_detail(carrier, tracking_code))
    end

    # The seller's word that the parcel arrived. It starts the return window
    # (delivered_at) and asks the buyer to confirm. It does not create the
    # shop's payout.
    def report_delivered!
      transitioned = false
      with_lock do
        next if fulfilment_status == "delivered"

        update!(fulfilment_status: "delivered", delivered_at: Time.current)
        transitioned = true
      end
      return self unless transitioned

      record_delivery_events!
      notify_buyer(I18n.t("marketplace.order_notification.delivered"),
                   I18n.t("marketplace.order_notification.confirm_receipt_body", title: listing_title))
    end

    # Receipt confirmed, by the buyer or by the window closing. This is what
    # enqueues the store payout, once.
    def mark_delivered!
      reported = false
      confirmed = false
      with_lock do
        next if receipt_confirmed_at.present?

        reported = fulfilment_status != "delivered"
        update!(fulfilment_status: "delivered", delivered_at: delivered_at || Time.current,
                receipt_confirmed_at: Time.current)
        confirmed = true
      end
      return self unless confirmed

      enqueue_store_payout!
      announce_receipt(reported:)
    end

    private

    def announce_receipt(reported:)
      if reported
        record_delivery_events!
        notify_buyer(I18n.t("marketplace.order_notification.delivered"), listing_title)
      end
      body = I18n.t("marketplace.order_notification.receipt_confirmed_body", title: listing_title)
      deliver_notification(seller, title: I18n.t("marketplace.order_notification.receipt_confirmed"), body: body,
                                   source: self, kind: "order")
    end

    def notify_buyer(title, body)
      deliver_notification(buyer_record, title: title, body: body, source: self, kind: "order")
    end

    def shipment_detail(carrier, tracking_code)
      return listing_title if tracking_code.blank?

      "#{listing_title} — #{carrier.presence || I18n.t('marketplace.order_notification.tracking')}: #{tracking_code}"
    end

    def record_delivery_events!
      metadata = { order_id: id }
      record_listing_commerce_event("MarketplaceOrderDelivered", actor: buyer_record, metadata: metadata)
      record_listing_event("delivered", user: buyer_record, metadata: metadata)
    end
  end
end
