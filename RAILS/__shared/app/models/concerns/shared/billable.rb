# frozen_string_literal: true

module Shared
  # A User that can hold paid plans. The app asks entitled?(:name) and never a
  # plan key, so a plan can be repriced or split without touching what it gates.
  module Billable
    extend ActiveSupport::Concern

    included do
      has_many :billing_subscriptions, class_name: "Shared::BillingSubscription", dependent: :destroy,
                                       inverse_of: :user
    end

    def entitled?(entitlement)
      billing_subscriptions.entitling.any? { |subscription| subscription.plan&.grants?(entitlement) }
    end

    # The Stripe customer this user pays as, once a checkout has made one.
    def stripe_customer_id
      with_customer = billing_subscriptions.where.not(stripe_customer_id: nil)
      with_customer.pick(:stripe_customer_id)
    end
  end
end
