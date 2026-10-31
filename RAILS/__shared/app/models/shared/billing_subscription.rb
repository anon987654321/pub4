# frozen_string_literal: true

module Shared
  # A reader's subscription to one plan in config/plans.yml, kept in step with
  # Stripe by Shared::StripeBilling from the webhook. Stripe is the source of
  # truth for money; this row is what the app asks at request time.
  class BillingSubscription < ApplicationRecord
    self.table_name = "billing_subscriptions"

    # Stripe's statuses; only active and trialing give access.
    ENTITLING = Shared::StripeBilling::ENTITLING_STATUSES
    STATUSES = %w[incomplete incomplete_expired trialing active past_due canceled unpaid paused].freeze

    belongs_to :user, class_name: "::User"

    validates :plan_key, inclusion: { in: ->(_record) { Shared::BillingPlan.keys } }
    validates :status, inclusion: { in: STATUSES }
    validates :stripe_subscription_id, presence: true, uniqueness: true

    scope :entitling, -> { where(status: ENTITLING) }
    scope :granting, ->(entitlement) { entitling.where(plan_key: Shared::BillingPlan.keys_granting(entitlement)) }

    def plan = Shared::BillingPlan.find(plan_key)

    def entitling? = ENTITLING.include?(status)
  end
end
