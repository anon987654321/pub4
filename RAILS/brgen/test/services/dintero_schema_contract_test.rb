# frozen_string_literal: true

require "test_helper"

class DinteroSchemaContractTest < ActiveSupport::TestCase
  SCHEMA = File.read(Rails.root.join("db", "schema.rb"))

  def table(name)
    start = SCHEMA.index(%(create_table "#{name}"))
    assert start, "missing #{name}"
    finish = SCHEMA.index("  create_table ", start + 1) || SCHEMA.length
    SCHEMA[start...finish]
  end

  test "Dintero columns and indexes occur exactly once" do
    checkout = table("marketplace_checkouts")
    orders = table("marketplace_orders")
    stores = table("marketplace_stores")
    deliveries = table("marketplace_webhook_deliveries")

    assert_equal 1, checkout.scan(/t\.string "dintero_(order_id|session_id|transaction_id)"/).length
    assert_equal 1, orders.scan(/t\.string "dintero_(order_id|session_id|transaction_id)"/).length
    assert_equal 1, stores.scan(/t\.string "dintero_payout_destination_id"/).length
    assert_equal 1, deliveries.scan(/create_table "marketplace_webhook_deliveries"/).length

    assert_match(/index_marketplace_checkouts_on_dintero_order_id.*unique: true/, checkout)
    assert_match(/index_marketplace_orders_on_dintero_order_id/, orders)
    assert_match(/index_marketplace_webhook_deliveries_identity.*unique: true/, deliveries)
  end
end
