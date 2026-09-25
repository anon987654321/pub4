# frozen_string_literal: true

module Marketplace
  module Payments
    class DinteroCheckout
      class SellerNotReady < ProviderError; end

      COMMISSION_ENV = "DINTERO_PLATFORM_COMMISSION_BPS"

      class << self
        def configured?
          DinteroClient.checkout_configured? &&
            ENV["DINTERO_CHECKOUT_ENABLED"].to_s == "1"
        end

        def start!(order:, return_url:, callback_url:)
          raise NotConfigured, "Dintero" unless configured?
          raise ArgumentError, "order is not payable" unless order.respond_to?(:startable?) && order.startable?

          reference = merchant_reference(order)
          dintero_order_id = order.dintero_order_id.presence ||
            create_shopping_order!(order, reference)

          persist_dintero_order!(order, dintero_order_id, reference) if dintero_order_id.present?

          response = DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/orders/#{ERB::Util.url_encode(dintero_order_id)}/sessions",
            session_payload(order, return_url:, callback_url:),
            idempotency_key: "brgen-session-#{reference}"
          )
          session_id = response.fetch("id")
          checkout_url = response.fetch("url")

          persist_session!(order, dintero_order_id, session_id, reference)
          order.define_singleton_method(:dintero_checkout_url) { checkout_url }
          checkout_url
        rescue DinteroClient::Error => error
          raise ProviderError, error.message
        end

        def ensure_sellers_ready!(orders)
          Array(orders).each do |order|
            listing = order.listing
            store = store_for_listing(listing)
            unless store&.dintero_ready?
              raise SellerNotReady,
                    "Dintero seller payout destination is not ACTIVE for listing #{order.listing_id}"
            end
          end
          true
        end

        def supported_listing?(listing)
          store_for_listing(listing)&.dintero_ready? == true
        end

        def capture!(order:)
          raise NotConfigured, "Dintero" unless configured?
          raise ArgumentError, "order is not a Dintero authorization" unless order.payment_provider == "dintero"
          raise ArgumentError, "order is not authorized" unless order.payment_status == "authorized"

          transaction_id = order.dintero_transaction_id.to_s
          dintero_order_id = order.dintero_order_id.to_s
          raise ArgumentError, "order has no Dintero transaction" if transaction_id.empty?
          raise ArgumentError, "order has no Dintero order id" if dintero_order_id.empty?

          DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/orders/#{ERB::Util.url_encode(dintero_order_id)}/captures",
            {
              items: [ capture_item(order) ],
              fee_split: fee_split
            }.compact,
            idempotency_key: "brgen-capture-order-#{order.id}"
          )
        rescue DinteroClient::Error => error
          raise ProviderError, error.message
        end
        def refund!(order:)
          raise NotConfigured, "Dintero" unless configured?
          raise ArgumentError, "order is not a Dintero payment" unless order.payment_provider == "dintero"
          raise ArgumentError, "order is not paid" unless order.payment_status == "paid"

          dintero_order_id = order.dintero_order_id.to_s
          raise ArgumentError, "order has no Dintero order id" if dintero_order_id.empty?

          DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/orders/#{ERB::Util.url_encode(dintero_order_id)}/refunds",
            {
              items: [ capture_item(order) ],
              fee_split: fee_split
            }.compact,
            idempotency_key: "brgen-refund-order-#{order.id}"
          )
        rescue DinteroClient::Error => error
          raise ProviderError, error.message
        end

        def refunded!(payable, transaction_id:, items: [])
          payable.update_columns(
            dintero_transaction_id: transaction_id,
            updated_at: Time.current
          )

          if payable.is_a?(Marketplace::Checkout)
            line_ids = Array(items).filter_map do |item|
              item["line_id"].presence || item["external_id"].presence
            end.map(&:to_s)
            return payable if line_ids.empty?

            payable.transaction do
              payable.order_lines.where(id: line_ids).where(payment_status: "paid").find_each do |order|
                order.update_columns(
                  payment_status: "refunded",
                  dintero_transaction_id: transaction_id,
                  updated_at: Time.current
                )
                mark_return_refunded!(order, transaction_id)
              end
            end
          else
            payable.update!(
              payment_status: "refunded",
              dintero_transaction_id: transaction_id
            )
            mark_return_refunded!(payable, transaction_id)
          end
          payable
        end

        def captured!(payable, transaction_id:, items: [])
          payable.update_columns(
            dintero_transaction_id: transaction_id,
            updated_at: Time.current
          )

          if payable.is_a?(Marketplace::Checkout)
            line_ids = Array(items).filter_map do |item|
              item["line_id"].presence || item["external_id"].presence
            end.map(&:to_s)
            return payable if line_ids.empty?

            payable.transaction do
              payable.order_lines.where(id: line_ids).find_each do |order|
                order.update_columns(
                  dintero_transaction_id: transaction_id,
                  updated_at: Time.current
                )
                order.mark_paid!(reference: payable.payment_reference)
                Webhooks::PaymentPaid.enqueue_google_conversion(order)
              end
              payable.sync_payment_status!
            end
          else
            payable.mark_paid!(reference: payable.payment_reference)
            Webhooks::PaymentPaid.enqueue_google_conversion(payable)
          end
          payable
        end

        def payable_for_reference(reference)
          return if reference.blank?

          Marketplace::Checkout.find_by(payment_reference: reference) ||
            Marketplace::Order.find_by(payment_reference: reference)
        end

        def merchant_reference(payable)
          prefix = payable.is_a?(Marketplace::Checkout) ? "checkout" : "order"
          "brgen-dintero-#{prefix}-#{payable.id}"
        end

        private

        def store_for_listing(listing)
          return if listing.blank?

          if listing.respond_to?(:association) && listing.association(:store).loaded?
            return listing.store
          end

          store_id = listing.respond_to?(:store_id) ? listing.store_id : nil
          return listing.store if store_id.blank? && listing.respond_to?(:store)

          Marketplace::Store.strict_loading(false).find_by(id: store_id)
        end

        def mark_return_refunded!(order, reference)
          return unless order.respond_to?(:id)

          return_record = Marketplace::Return.where(
            order_id: order.id,
            status: "received"
          ).where(refunded_at: nil).order(resolved_at: :desc).first
          return_record&.update!(
            refunded_at: Time.current,
            refund_reference: reference
          )
        end

        def persist_dintero_order!(payable, dintero_order_id, reference)
          payable.update_columns(
            payment_provider: "dintero",
            payment_reference: reference,
            dintero_order_id: dintero_order_id,
            updated_at: Time.current
          )
          return unless payable.is_a?(Marketplace::Checkout)

          payable.order_lines.find_each do |order|
            order.update_columns(
              payment_provider: "dintero",
              payment_reference: reference,
              dintero_order_id: dintero_order_id,
              updated_at: Time.current
            )
          end
        end

        def persist_session!(payable, dintero_order_id, session_id, reference)
          payable.update!(
            payment_provider: "dintero",
            payment_status: "pending",
            payment_reference: reference,
            dintero_order_id: dintero_order_id,
            dintero_session_id: session_id
          )
          return unless payable.is_a?(Marketplace::Checkout)

          payable.order_lines.find_each do |order|
            order.update_columns(
              payment_provider: "dintero",
              payment_status: "pending",
              payment_reference: reference,
              dintero_order_id: dintero_order_id,
              dintero_session_id: session_id,
              updated_at: Time.current
            )
          end
        end

        def create_shopping_order!(payable, reference)
          orders = payable.is_a?(Marketplace::Checkout) ?
            payable.order_lines.includes(listing: :store).to_a : [ payable ]

          draft = DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/draft_orders",
            {
              order: {
                merchant_reference: reference,
                currency: payable.payment_currency,
                items: orders.map { |order| draft_item(order) }
              },
              options: {
                split_draft: false
              }
            },
            idempotency_key: "brgen-draft-#{reference}"
          )
          draft_id = draft.fetch("id")

          completed = DinteroClient.put(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/draft_orders/#{ERB::Util.url_encode(draft_id)}/complete"
          )
          order_ids = Array(completed["orders"]).filter_map do |item|
            item["order_id"].presence || item["id"].presence
          end
          order_ids.first || completed["order_id"] || completed.dig("order", "order_id") ||
            completed.fetch("id")
        rescue DinteroClient::Error => error
          raise ProviderError, error.message
        end

        def draft_item(order)
          {
            id: order.id.to_s,
            external_id: order.id.to_s,
            description: order.listing.title.to_s.truncate(120),
            quantity: (order.quantity.presence || 1).to_i,
            amount: order.total_cents
          }
        end

        def session_payload(payable, return_url:, callback_url:)
          orders = payable.is_a?(Marketplace::Checkout) ?
            payable.order_lines.includes(listing: :store).to_a : [ payable ]
          {
            items: orders.map { |order| session_item(order) },
            url: {
              return_url: return_url,
              callback_url: callback_url
            },
            profile_id: DinteroClient.profile_id,
            fee_split: fee_split
          }.compact
        end

        def session_item(order)
          {
            line_id: order.id.to_i,
            amount: order.total_cents,
            splits: split_for(order)
          }
        end

        def capture_item(order)
          session_item(order)
        end

        def split_for(order)
          store = store_for_listing(order.listing)
          seller_destination = store&.dintero_payout_destination_id.to_s
          seller_status = store&.dintero_payout_destination_status.to_s
          unless seller_destination.present? && seller_status == "ACTIVE"
            raise SellerNotReady,
                  "Dintero seller payout destination is not ACTIVE for listing #{order.listing_id}"
          end

          fee = platform_fee_cents(order)
          seller_amount = order.total_cents - fee
          raise SellerNotReady, "Dintero platform fee exceeds order total" if seller_amount.negative?

          splits = [
            { payout_destination_id: seller_destination, amount: seller_amount }
          ]
          if fee.positive?
            platform_destination = ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"].to_s
            raise SellerNotReady, "Dintero platform payout destination is not configured" if platform_destination.empty?

            splits << { payout_destination_id: platform_destination, amount: fee }
          end
          splits
        end

        def fee_split
          return if platform_fee_bps.zero?

          platform_destination = ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"].to_s
          raise SellerNotReady, "Dintero platform payout destination is not configured" if platform_destination.empty?

          { type: "proportional", destinations: [ platform_destination ] }
        end

        def platform_fee_bps
          bps = Integer(ENV.fetch(COMMISSION_ENV, "0"), 10)
          raise SellerNotReady, "#{COMMISSION_ENV} must be between 0 and 10000" unless bps.between?(0, 10_000)

          bps
        rescue ArgumentError
          raise SellerNotReady, "#{COMMISSION_ENV} must be an integer"
        end

        def platform_fee_cents(order)
          ((order.total_cents.to_i * platform_fee_bps) + 5_000) / 10_000
        end

      end
    end
  end
end
