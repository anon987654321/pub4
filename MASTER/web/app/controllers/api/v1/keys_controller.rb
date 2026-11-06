# frozen_string_literal: true

module Api
  module V1
    # The key's own account: usage, a replacement key, and Stripe's portal for
    # the card, the plan and cancelling.
    class KeysController < BaseController
      rate_limit to: 10, within: 1.minute, by: -> { @api_key.id }, only: %i[rotate portal],
                 with: -> { refuse(:too_many_requests, "rate_limited") }

      def show
        render json: { plan: @api_key.plan_key, status: @api_key.status, usage: @api_key.usage.to_h }
      end

      def rotate = render(json: { key: @api_key.rotate! })

      def portal
        render json: { url: Shared::StripeBilling.portal_url(user: @api_key, return_url: api_url) }
      rescue Shared::StripeBilling::Error => e
        Rails.logger.warn("[api] portal: #{e.message}")
        refuse(:service_unavailable, "billing_unavailable")
      end
    end
  end
end
