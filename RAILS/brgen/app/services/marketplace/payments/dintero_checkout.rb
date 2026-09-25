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
          order.update_columns(payment_provider: "dintero", payment_reference: reference, dintero_session_id: nil) if order.payment_reference != reference

          response = DinteroClient.post(
            "/v1/sessions-profile",
            session_payload(order, return_url:, callback_url:),
            checkout: true,
            idempotency_key: "brgen-session-#{reference}"
          )
          session_id = response.fetch("id")
          checkout_url = response.fetch("url")

          persist_session!(order, session_id, reference)
          order.define_singleton_method(:dintero_checkout_url) { checkout_url }
          checkout_url
        rescue DinteroClient::Error => e
          raise ProviderError, e.message
        end

        def ensure_sellers_ready!(orders)
          Array(orders).each do |order|
            listing = order.listing
            store = listing&.store
            raise SellerNotReady, "Dintero seller is not configured for listing #{order.listing_id}" unless store&.dintero_ready?
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
          raise ArgumentError, "order has no Dintero transaction" if transaction_id.empty?

          dintero_order_id = order.dintero_order_id.to_s
          raise ArgumentError, "order has no Dintero order id" if dintero_order_id.empty?

          DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/orders/#{ERB::Util.url_encode(dintero_order_id)}/captures",
            { items: [ capture_item(order) ] },
            idempotency_key: "brgen-capture-order-#{order.id}"
          )
        rescue DinteroClient::Error => e
          raise ProviderError, e.message
        end

        def authorize!(payable, transaction_id:)
          payable.transaction do
            payable.update!(
              payment_status: "authorized",
              dintero_transaction_id: transaction_id,
              status: payable.is_a?(Marketplace::Checkout) ? "pending_payment" : payable.status
            )
            if payable.is_a?(Marketplace::Checkout)
              payable.order_lines.each { |order| order.authorize_payment!(transaction_id: transaction_id) }
            end
          end
          payable
        end

        def captured!(payable, transaction_id:)
          payable.update_columns(
            dintero_transaction_id: transaction_id,
            updated_at: Time.current
          )
          payable.mark_paid!(reference: payable.payment_reference)
          payable
        end

        def payable_for_reference(reference)
          Marketplace::Checkout.find_by(payment_reference: reference) ||
            Marketplace::Order.find_by(payment_reference: reference)
        end

        def session_transaction(order:, session_id:)
          dintero_order_id = order.dintero_order_id.to_s
          raise ArgumentError, "order has no Dintero order id" if dintero_order_id.empty?

          DinteroClient.get(
            "/v1/accounts/#{DinteroClient.account_id}/shopping/orders/#{ERB::Util.url_encode(dintero_order_id)}/sessions/#{ERB::Util.url_encode(session_id)}"
          )
        rescue DinteroClient::Error => e
          raise ProviderError, e.message
        end

        def merchant_reference(payable)
          prefix = payable.is_a?(Marketplace::Checkout) ? "checkout" : "order"
          "brgen-dintero-#{prefix}-#{payable.id}"
        end

        private

        def persist_session!(payable, session_id, reference)
          payable.update!(
            payment_provider: "dintero",
            payment_status: "pending",
            payment_reference: reference,
            dintero_session_id: session_id
          )
          if payable.is_a?(Marketplace::Checkout)
            payable.order_lines.each do |order|
              order.update_columns(
                payment_provider: "dintero",
                payment_status: "pending",
                payment_reference: reference,
                dintero_session_id: session_id,
                updated_at: Time.current
              )
            end
          end
        end

        def session_payload(payable, return_url:, callback_url:)
          orders = payable.is_a?(Marketplace::Checkout) ? payable.order_lines.to_a : [ payable ]
          {
            merchant_reference: merchant_reference(payable),
            items: orders.map { |order| session_item(order) },
            url: {
              return_url: return_url,
              callback_url: callback_url
            },
            profile_id: DinteroClient.profile_id
          }
        end

        def session_item(order)
          listing = order.listing
          split = split_for(order)
          item = {
            id: listing.id.to_s,
            line_id: order.id.to_s,
            description: listing.title.to_s.truncate(120),
            quantity: (order.quantity.presence || 1).to_i,
            amount: order.total_cents
          }
          item[:splits] = split
          if (fee = fee_split)
            item[:fee_split] = fee
          end
          item
        end

        def capture_item(order)
          session_item(order)
        end

        def split_for(order)
          destination = order.listing.store
          payout_destination_id = destination&.dintero_payout_destination_id.to_s
          status = destination&.dintero_payout_destination_status.to_s
          unless destination && payout_destination_id.present? && status == "ACTIVE"
            raise SellerNotReady,
                  "Dintero seller payout destination is not ACTIVE for listing #{order.listing_id}"
          end

          fee = platform_fee_cents(order)
          seller_amount = order.total_cents - fee
          raise SellerNotReady, "Dintero platform fee exceeds order total" if seller_amount.negative?

          splits = [
            { payout_destination_id: payout_destination_id, amount: seller_amount }
          ]
          splits << {
            payout_destination_id: ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"].to_s,
            amount: fee
          } if fee.positive?

          unless fee.zero? || ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"].to_s.present?
            raise SellerNotReady, "Dintero platform payout destination is not configured"
          end

          splits
        end

        def fee_split
          return if platform_fee_bps.zero?

          destination = ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"].to_s
          raise SellerNotReady, "Dintero platform payout destination is not configured" if destination.empty?

          { type: "proportional", destinations: [ destination ] }
        end

        def platform_fee_bps
          Integer(ENV.fetch(COMMISSION_ENV, "0"), 10)
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
