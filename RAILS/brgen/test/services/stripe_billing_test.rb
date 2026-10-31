# frozen_string_literal: true

require "test_helper"

# Shared::StripeBilling keeps Shared::BillingSubscription in step with the
# subscription events Stripe sends; Shared::Billable reads it back as
# entitlements.
class StripeBillingTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "billing-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "billing_#{SecureRandom.hex(3)}", city: @city
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def subscription_event(type, status:, id: "sub_1")
    {
      "type" => type,
      "data" => { "object" => {
        "id" => id, "status" => status, "customer" => "cus_1", "cancel_at_period_end" => false,
        "items" => { "data" => [{ "current_period_end" => 30.days.from_now.to_i }] },
        "metadata" => { "plan" => "brgen_business_presence", "user_id" => @user.id.to_s },
      } },
    }
  end

  test "a created subscription entitles its user, and a replay writes the same row" do
    event = subscription_event("customer.subscription.created", status: "active")
    2.times { assert Shared::StripeBilling.handle(event) }

    assert_equal 1, Shared::BillingSubscription.where(stripe_subscription_id: "sub_1").count
    assert @user.reload.entitled?(:featured_listings)
    assert_equal "cus_1", @user.stripe_customer_id
  end

  test "past_due and deleted subscriptions stop entitling" do
    Shared::StripeBilling.handle(subscription_event("customer.subscription.created", status: "active"))
    Shared::StripeBilling.handle(subscription_event("customer.subscription.updated", status: "past_due"))
    refute @user.reload.entitled?(:featured_listings)

    Shared::StripeBilling.handle(subscription_event("customer.subscription.deleted", status: "canceled"))
    refute @user.reload.entitled?(:featured_listings)
  end

  test "an unknown plan or user writes nothing, and other events are not billing's" do
    event = subscription_event("customer.subscription.created", status: "active")
    event["data"]["object"]["metadata"]["plan"] = "no_such_plan"
    Shared::StripeBilling.handle(event)
    assert_equal 0, Shared::BillingSubscription.count

    refute Shared::StripeBilling.handle({ "type" => "checkout.session.completed", "data" => { "object" => {} } })
  end

  test "a plan is not offered while its price or the Stripe key is unset" do
    plan = Shared::BillingPlan.find("brgen_business_presence")
    with_env("STRIPE_SECRET_KEY" => nil, plan.price_env => "price_1") { refute plan.available? }
    with_env("STRIPE_SECRET_KEY" => "sk_live_x", plan.price_env => nil) { refute plan.available? }
    with_env("STRIPE_SECRET_KEY" => "sk_live_x", plan.price_env => "price_1") { assert plan.available? }
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    yield
  ensure
    previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
