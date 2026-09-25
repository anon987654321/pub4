# frozen_string_literal: true

module Marketplace
  module Payments
    class DinteroCheckout
      class SellerNotReady < ProviderError; end


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
            store = listing&.store
            unless store&.dintero_ready?
              raise SellerNotReady,
                    "Dintero seller payout destination is not ACTIVE for listing #{order.listing_id}"
            end
          end
          true
        end

        def supported_listing?(listing)
          listing&.store&.dintero_ready? == true
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
            { items: [ capture_item(order) ] },
            idempotency_key: "brgen-capture-order-#{order.id}"
          )
        rescue DinteroClient::Error => error
          raise ProviderError, error.message
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

            payable.order_lines.where(id: line_ids).find_each do |order|
              order.update_columns(
                dintero_transaction_id: transaction_id,
                updated_at: Time.current
              )
              order.mark_paid!(reference: payable.payment_reference)
            end
            payable.sync_payment_status!
          else
            payable.mark_paid!(reference: payable.payment_reference)
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

          stores = orders.map { |order| order.listing.store }.uniq
          stores.each { |store| DinteroPayoutRules.ensure_for!(store) }

          draft = DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/draft_orders",
            {
              order: {
                merchant_reference: reference,
                currency: payable.payment_currency,
                items: orders.map { |order| draft_item(order) }
              },
              options: {
                split_draft: false,
                payout: true
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
            store: DinteroPayoutRules.item_store(order.listing.store),
            description: order.listing.title.to_s.truncate(120),
            quantity: (order.quantity.presence || 1).to_i,
            unit_price: order.unit_price_cents,
            gross_amount: order.total_cents
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
            profile_id: DinteroClient.profile_id
          }
        end

        def session_item(order)
          {
            line_id: order.id.to_i,
            amount: order.total_cents
          }
        end

        def capture_item(order)
          {
            line_id: order.id.to_i,
            amount: order.total_cents
          }
        end

      end
    end
  end
end
