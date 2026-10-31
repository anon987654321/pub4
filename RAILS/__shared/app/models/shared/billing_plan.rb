# frozen_string_literal: true

module Shared
  # One paid plan from config/plans.yml. The page, checkout and the entitlement
  # check read plans here and nowhere else.
  BillingPlan = Data.define(:key, :app, :amount, :currency, :interval, :price_env, :entitlements) do
    def self.all
      @all ||= YAML.safe_load_file(File.expand_path("../../../config/plans.yml", __dir__))
                   .fetch("plans").map { |key, row| from_row(key, row) }.freeze
    end

    def self.from_row(key, row)
      new(key:, app: row.fetch("app"), amount: Integer(row.fetch("amount")), currency: row.fetch("currency"),
          interval: row.fetch("interval"), price_env: row.fetch("price_env"),
          entitlements: Array(row.fetch("entitlements")).map(&:to_s).freeze)
    end

    def self.keys = all.map(&:key)

    def self.for_app(app) = all.select { |plan| plan.app == app.to_s }

    def self.find(key) = all.find { |plan| plan.key == key.to_s }

    def self.keys_granting(entitlement) = all.select { |plan| plan.grants?(entitlement) }.map(&:key)

    # The Stripe Price id, or nil while the operator has not created it.
    def price_id = ENV[price_env].to_s.strip.presence

    def available? = price_id.present? && Shared::StripeBilling.configured?

    def grants?(entitlement) = entitlements.include?(entitlement.to_s)
  end
end
