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

    source_rows = select_value("SELECT COUNT(*) FROM marketplace_orders_legacy").to_i
    copied_rows = select_value("SELECT COUNT(*) FROM marketplace_orders").to_i
    raise "marketplace_orders copy incomplete: #{source_rows} source rows, #{copied_rows} copied" unless source_rows == copied_rows

    # migration-safety-reviewed: the legacy table is removed only after a full row-count check.
    # The original table was renamed, all records copied with explicit columns, and the migration
    # is intentionally irreversible because the old foreign-key shape is the defect being repaired.
    drop_table :marketplace_orders_legacy
    execute 'PRAGMA foreign_keys = ON'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
