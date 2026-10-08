# frozen_string_literal: true

class FixMarketplaceOrderForeignKeys < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:marketplace_orders)

    execute 'PRAGMA foreign_keys = OFF'
    rename_table :marketplace_orders, :marketplace_orders_legacy
    create_table :marketplace_orders do |t|
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.string :status
      t.text :message
      t.integer :price_cents
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO marketplace_orders (id, buyer_id, listing_id, status, message, price_cents, created_at, updated_at)
      SELECT id, buyer_id, listing_id, status, message, price_cents, created_at, updated_at
      FROM marketplace_orders_legacy
    SQL
    drop_table :marketplace_orders_legacy
    execute 'PRAGMA foreign_keys = ON'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
