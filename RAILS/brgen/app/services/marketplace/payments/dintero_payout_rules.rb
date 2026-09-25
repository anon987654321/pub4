# frozen_string_literal: true

require "json"
require "uri"

module Marketplace
  module Payments
    class DinteroPayoutRules
      RULE_TYPE = "order.items.store.id"
      COMMISSION_ENV = "DINTERO_PLATFORM_COMMISSION_BPS"
      PLATFORM_DESTINATION_ENV = "DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"

      class ConfigurationError < ProviderError; end

      class << self
        def ensure_for!(store)
          raise ConfigurationError, "Dintero seller is not ready" unless store&.dintero_ready?

          seller_destination = store.dintero_payout_destination_id.to_s
          platform_destination = ENV[PLATFORM_DESTINATION_ENV].to_s
          commission = commission_percentage

          existing = find_rule(rule_id(store))
          expected = destinations(
            platform_destination:,
            seller_destination:,
            commission:
          )

          return existing if existing && same_destinations?(existing["destinations"], expected)

          raise ConfigurationError, "Dintero payout rule #{rule_id(store)} does not match BRGEN commission" if existing

          DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/billing/payout-rules",
            {
              rule_type: RULE_TYPE,
              rule_id: rule_id(store),
              destinations: expected,
              metadata: {
                source: "brgen",
                store_id: store.id.to_s
              }
            },
            idempotency_key: "brgen-payout-rule-#{store.id}-#{commission}"
          )
        rescue DinteroClient::Error => error
          raise ConfigurationError, error.message
        end

        def rule_id(store)
          "brgen-store-#{store.id}"
        end

        def item_store(store)
          { id: rule_id(store) }
        end

        def destinations(platform_destination:, seller_destination:, commission:)
          if commission.zero?
            return [
              {
                type: "percentage",
                value: 100,
                destination: seller_destination
              }
            ]
          end

          raise ConfigurationError, "Dintero platform payout destination is not configured" if platform_destination.empty?

          [
            {
              type: "percentage",
              value: commission,
              destination: platform_destination
            },
            {
              type: "remaining_amount",
              destinations: [
                {
                  type: "percentage",
                  value: 100,
                  destination: seller_destination
                }
              ]
            }
          ]
        end

        def commission_percentage
          bps = Integer(ENV.fetch(COMMISSION_ENV, "0"), 10)
          raise ConfigurationError, "#{COMMISSION_ENV} must be between 0 and 10000" unless bps.between?(0, 10_000)

          bps / 100.0
        rescue ArgumentError
          raise ConfigurationError, "#{COMMISSION_ENV} must be an integer"
        end

        private

        def find_rule(rule_id)
          response = DinteroClient.get(
            "/v1/accounts/#{DinteroClient.account_id}/billing/payout-rules?#{URI.encode_www_form(
              rule_type: RULE_TYPE,
              rule_id: rule_id,
              include_deleted: false
            )}"
          )
          Array(response["payout_rules"]).first
        end

        def same_destinations?(actual, expected)
          canonical(actual) == canonical(expected)
        end

        def canonical(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), normalized|
              normalized[key.to_s] = canonical(item)
            end.sort.to_h
          when Array
            value.map { |item| canonical(item) }
          when Numeric
            value.to_f
          else
            value
          end
        end
      end
    end
  end
end
