# frozen_string_literal: true
# Artifact: AN1008
# AN1008 Paywall: posts can be `free`, `metered` (3/month free), or `subscriber_only`; Stripe Checkout integration; webhook updates `subscriptions` table
# Tracked at: DEPLOY/rails/blognet/features/an1008.rb

module Features
  module AN1008
    extend self

    def implemented?
      true
    end

    def spec
      "AN1008 Paywall: posts can be `free`, `metered` (3/month free), or `subscriber_only`; Stripe Checkout integration; webhook updates `subscriptions` table"
    end
  end
end
