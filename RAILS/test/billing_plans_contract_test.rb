# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# Paid plans are data (__shared/config/plans.yml). This holds every plan to
# the pieces that make it sellable in its app, read as source so it runs
# without a Rails boot: a price, both locales, and in the selling app the
# table, the Billable user, the routes and the controller that names it.
class BillingPlansContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PLANS = YAML.safe_load_file(File.join(ROOT, "__shared/config/plans.yml")).fetch("plans")
  CURRENCIES = %w[NOK EUR GBP USD SEK DKK].freeze
  # A plan with a quota is an API plan, sold as a key rather than to a user.
  USER_APPS = PLANS.values.reject { |plan| plan.key?("quota") }.map { |plan| plan.fetch("app") }.uniq
  API_APPS = PLANS.values.select { |plan| plan.key?("quota") }.map { |plan| plan.fetch("app") }.uniq

  def read(relative) = File.read(File.join(ROOT, relative), encoding: "UTF-8")

  def test_every_plan_has_a_price_a_stripe_price_variable_and_entitlements
    PLANS.each do |key, plan|
      assert_operator Integer(plan.fetch("amount")), :>, 0, key
      assert_includes CURRENCIES, plan.fetch("currency"), key
      assert_includes %w[month year], plan.fetch("interval"), key
      assert_match(/\ASTRIPE_PRICE_[A-Z0-9_]+\z/, plan.fetch("price_env"), key)
      refute_empty Array(plan.fetch("entitlements")), key
    end
    envs = PLANS.values.map { |plan| plan["price_env"] }
    assert_equal envs.uniq, envs, "two plans cannot share one Stripe price"
  end

  def test_every_plan_is_named_and_described_in_both_locales
    %w[en nb].each do |locale|
      names = YAML.safe_load_file(File.join(ROOT, "__shared/config/locales/billing.#{locale}.yml"))
                  .dig(locale, "billing", "plans")
      PLANS.each_key do |key|
        assert names.dig(key, "name").to_s.strip != "", "#{locale} #{key} name"
        assert names.dig(key, "summary").to_s.strip != "", "#{locale} #{key} summary"
      end
    end
  end

  def test_every_selling_app_has_the_table_the_user_the_routes_and_the_controller
    USER_APPS.each do |app|
      assert(Dir.glob(File.join(ROOT, app, "db/migrate/*_create_billing_subscriptions.rb")).any?, "#{app} migration")
      assert_includes read("#{app}/db/schema.rb"), %(create_table "billing_subscriptions"), app
      assert_includes read("#{app}/app/models/user.rb"), "include Shared::Billable", app
      assert_match(/billing/, read("#{app}/config/routes.rb"), "#{app} routes")
      assert_includes read("#{app}/app/controllers/billing_controller.rb"), %(def billing_app = "#{app}"), app
    end
  end

  # Subscription events reach billing from each selling app's Stripe endpoint.
  def test_each_selling_apps_stripe_webhook_hands_events_to_billing
    USER_APPS.each do |app|
      controller = read("#{app}/app/controllers/webhooks/stripe_controller.rb")
      assert_includes controller, "Shared::StripeSignature.verify!", app
      assert_includes controller, "Shared::StripeBilling.handle(event)", app
    end
  end

  # An API plan has a positive monthly quota, and its app holds the keys
  # table, the ApiKey model, the routes, and a webhook that keeps keys in step.
  def test_every_api_plan_has_a_quota_and_its_app_sells_keys
    PLANS.each { |key, plan| assert_operator Integer(plan["quota"]), :>, 0, key if plan.key?("quota") }
    API_APPS.each do |app|
      assert_includes read("#{app}/db/schema.rb"), %(create_table "api_keys"), app
      assert_includes read("#{app}/app/models/api_key.rb"), "Shared::BillingPlan.for_app(\"#{app}\")", app
      assert_includes read("#{app}/config/routes.rb"), %(post "lint" => "lint#create"), app
      webhook = read("#{app}/app/controllers/api/stripe_webhooks_controller.rb")
      assert_includes webhook, "Shared::StripeSignature.verify!", app
      assert_includes webhook, "ApiKey.sync!", app
    end
  end

  # Paid placement is labelled on the card, before the click.
  def test_paid_presence_listings_carry_the_sponsored_label
    partial = read("brgen_marketplace/app/views/marketplace/_top_offers.html.erb")
    assert_includes partial, %(t("marketplace.sponsored"))
    %w[en nb].each do |locale|
      label = YAML.safe_load_file(File.join(ROOT, "brgen_marketplace/config/locales/#{locale}.yml"))
                  .dig(locale, "marketplace", "sponsored")
      assert label.to_s.strip != "", locale
    end
  end
end
