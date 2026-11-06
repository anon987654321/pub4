# frozen_string_literal: true

require "digest"
require "securerandom"

# A key to the MASTER law API, one per Stripe subscription to a plan of this
# app in __shared/config/plans.yml. Stripe's webhook keeps status and period
# in step; the success page after checkout reveals the key once. Only the
# key's SHA-256 is kept, so a lost key is replaced (rotate!), never shown again.
class ApiKey < ApplicationRecord
  PREFIX = "mk_live_"
  Usage = Data.define(:period, :used, :quota)

  validates :plan_key, inclusion: { in: ->(_record) { Shared::BillingPlan.for_app("master").map(&:key) } }
  validates :status, :stripe_subscription_id, presence: true

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # The key a bearer token names, or nil. Only the digest is looked up.
  def self.authenticate(token)
    token = token.to_s
    find_by(token_digest: digest(token)) if token.start_with?(PREFIX)
  end

  # The row for a Stripe subscription object (webhook or expanded checkout),
  # created or brought up to date. nil when it is not one of this app's plans.
  def self.sync!(subscription, email: nil)
    plan_key = subscription.dig("metadata", "plan").to_s
    return unless Shared::BillingPlan.find(plan_key)&.app == "master"

    row = find_or_initialize_by(stripe_subscription_id: subscription.fetch("id"))
    row.update!(plan_key:, status: subscription["status"].to_s, stripe_customer_id: subscription["customer"],
                current_period_end: Shared::StripeBilling.period_end(subscription), email: email || row.email)
    row
  end

  def self.current_period = Time.now.utc.strftime("%Y-%m")

  def quota = plan&.quota.to_i

  def entitling? = Shared::StripeBilling::ENTITLING_STATUSES.include?(status)

  # The new key, the first time it is asked for; nil once it has been shown.
  def reveal!
    with_lock { token_digest ? nil : issue_token }
  end

  # A new key in place of the old one, which stops working at once.
  def rotate! = with_lock { issue_token }

  # Counts +checks+ against this month's quota. The Usage after counting, or
  # nil, counting nothing, when they do not fit.
  def charge!(checks)
    with_lock do
      period = self.class.current_period
      used = (usage_period == period ? usage_count : 0) + checks
      next if used > quota

      update!(usage_period: period, usage_count: used)
      usage
    end
  end

  def usage
    period = self.class.current_period
    Usage.new(period:, used: usage_period == period ? usage_count : 0, quota:)
  end

  private

  def plan = Shared::BillingPlan.find(plan_key)

  def issue_token
    token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    update!(token_digest: self.class.digest(token), token_hint: token.last(4))
    token
  end
end
