# frozen_string_literal: true

class FixMarketplaceOrderForeignKeys < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :marketplace_orders, :buyers if foreign_key_exists?(:marketplace_orders, :buyers)
    remove_foreign_key :marketplace_orders, :listings if foreign_key_exists?(:marketplace_orders, :listings)
    add_foreign_key :marketplace_orders, :users, column: :buyer_id unless foreign_key_exists?(:marketplace_orders, column: :buyer_id)
    add_foreign_key :marketplace_orders, :marketplace_listings, column: :listing_id unless foreign_key_exists?(:marketplace_orders, column: :listing_id)
  end

  def down
    remove_foreign_key :marketplace_orders, :users, column: :buyer_id if foreign_key_exists?(:marketplace_orders, column: :buyer_id)
    remove_foreign_key :marketplace_orders, :marketplace_listings, column: :listing_id if foreign_key_exists?(:marketplace_orders, column: :listing_id)
    add_foreign_key :marketplace_orders, :buyers, column: :buyer_id
    add_foreign_key :marketplace_orders, :listings, column: :listing_id
  end
end