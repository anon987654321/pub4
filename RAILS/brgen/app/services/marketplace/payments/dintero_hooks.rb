# frozen_string_literal: true

module Marketplace
  module Payments
    class DinteroHooks
      EVENTS = %w[
        checkout_authorization
        checkout_transaction
        approval_payout_destination_update
        approval_payout_destination_delete
        account_payout_destination_add
        account_payout_destination_update
        account_payout_destination_delete
        settlement_add
      ].freeze

      class << self
        def configured?
          DinteroClient.hooks_configured?
        end

        def create!
          raise NotConfigured, "Dintero hooks" unless configured?

          DinteroClient.post(
            "/v1/accounts/#{DinteroClient.account_id}/hooks/subscriptions",
            subscription_body,
            idempotency_key: "brgen-dintero-hooks-#{Digest::SHA256.hexdigest(webhook_url)}"
          )
        rescue DinteroClient::Error => e
          raise ProviderError, e.message
        end

        def list(limit: 100, starting_after: nil, include_deleted: false)
          query = {
            limit: limit.to_i.clamp(1, 100),
            include_deleted: include_deleted
          }
          query[:starting_after] = starting_after if starting_after.present?

          DinteroClient.get(
            "/v1/accounts/#{DinteroClient.account_id}/hooks/subscriptions?#{URI.encode_www_form(query)}"
          )
        rescue DinteroClient::Error => e
          raise ProviderError, e.message
        end

        def subscription_body
          {
            config: {
              url: webhook_url,
              content_type: "application/json",
              secret: ENV.fetch("DINTERO_HOOK_SECRET")
            },
            events: EVENTS
          }
        end

        private

        def webhook_url
          url = ENV["DINTERO_HOOK_URL"].to_s.strip
          url = "https://markedsplass.brgen.no/webhooks/dintero" if url.empty?
          uri = URI(url)
          raise ArgumentError, "DINTERO_HOOK_URL must use HTTPS" unless uri.is_a?(URI::HTTPS)
          raise ArgumentError, "DINTERO_HOOK_URL must include a host" if uri.host.blank?

          url
        rescue URI::InvalidURIError
          raise ArgumentError, "DINTERO_HOOK_URL is invalid"
        end
      end
    end
  end
end
