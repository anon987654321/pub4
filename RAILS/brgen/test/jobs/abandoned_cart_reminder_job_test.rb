# frozen_string_literal: true

require "test_helper"

class AbandonedCartReminderJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @buyer = User.strict_loading(false).create!(
      email_address: "cart_buyer_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      city: @city
    )
    @seller = User.strict_loading(false).create!(
      email_address: "cart_seller_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      city: @city
    )
    @category = Marketplace::Category.create!(name: "Cart-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: @seller,
      title: "Quietly waiting bike",
      description: "A basket test listing",
      category: @category,
      price_cents: 50_000,
      status: "active"
    )
    @checkout = @buyer.marketplace_checkouts.create!(currency: "NOK", status: "open")
    @order = Marketplace::Order.create!(
      buyer: @buyer,
      listing: @listing,
      price_cents: @listing.price_cents,
      marketplace_checkout_id: @checkout.id
    )
    @checkout.update_columns(created_at: 5.hours.ago, updated_at: 5.hours.ago)
    ActsAsTenant.current_tenant = @city
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "sends one reminder to a verified marketing subscriber" do
    EmailSubscription.create!(email: @buyer.email_address, confirmed: true, agreed_to_marketing: true)

    assert_enqueued_emails 1 do
      assert_equal 1, AbandonedCartReminderJob.perform_now
    end
    assert_not_nil @checkout.reload.abandoned_cart_reminded_at
  end

  test "does not send to a user without marketing consent" do
    EmailSubscription.create!(email: @buyer.email_address, confirmed: true, agreed_to_marketing: false)

    assert_no_enqueued_emails do
      assert_equal 0, AbandonedCartReminderJob.perform_now
    end
    assert_nil @checkout.reload.abandoned_cart_reminded_at
  end

  test "never sends a second reminder once marked" do
    EmailSubscription.create!(email: @buyer.email_address, confirmed: true, agreed_to_marketing: true)
    @checkout.update_columns(abandoned_cart_reminded_at: 1.hour.ago)

    assert_no_enqueued_emails do
      assert_equal 0, AbandonedCartReminderJob.perform_now
    end
  end
end
