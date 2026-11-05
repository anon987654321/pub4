# frozen_string_literal: true

require "json"

module Marketplace
  module Payments
    class DinteroCheckout
      # How a Dintero payment is divided: the seller's payout destination, the
      # platform's commission (DINTERO_PLATFORM_COMMISSION_BPS, in basis
      # points) and the contract each order line is frozen to at checkout, so
      # a seller whose destination changes before capture is refused rather
      # than paid somewhere new. Included into DinteroCheckout's singleton, so
      # these are its private class methods.
      module Splits
        private

        def persist_split_contracts!(payable)
          orders = payable.is_a?(Marketplace::Checkout) ? payable.order_lines.to_a : [ payable ]
          # Validate the complete basket before writing any line. A seller can
          # lose ACTIVE status between the controller preflight and this call;
          # one later failure must not leave earlier lines with a partial set of
          # frozen payout contracts.
          contracts = orders.map do |order|
            [ order, { splits: split_for(order), fee_split: fee_split }.compact ]
          end

          contracts.each do |order, contract|
            order.update_columns(dintero_split_json: JSON.generate(contract))
          end
        end

        def ensure_capture_destination!(order, contract)
          store = store_for_listing(order.listing)
          seller_destination = contract[:splits].filter_map do |split|
            split[:payout_destination_id]
          end.first
          unless store&.dintero_ready? &&
                 store.dintero_payout_destination_id.to_s == seller_destination.to_s
            raise SellerNotReady,
                  "Dintero seller payout destination changed or is no longer ACTIVE"
          end
        end

        def stored_split_contract!(order)
          raw = order.respond_to?(:dintero_split_json) ? order.dintero_split_json.to_s : ""
          raise SellerNotReady, "Dintero split contract is missing for order #{order.id}" if raw.empty?

          JSON.parse(raw, symbolize_names: true).tap do |contract|
            raise SellerNotReady, "Dintero split contract is invalid for order #{order.id}" unless contract[:splits].is_a?(Array)
          end
        rescue JSON::ParserError
          raise SellerNotReady, "Dintero split contract is invalid for order #{order.id}"
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
