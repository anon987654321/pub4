# frozen_string_literal: true

class FixTakeawayOrderItemForeignKeys < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:takeaway_order_items)

    execute "PRAGMA foreign_keys = OFF"
    rename_table :takeaway_order_items, :takeaway_order_items_legacy
    create_table :takeaway_order_items do |t|
      t.references :order, null: false, foreign_key: { to_table: :takeaway_orders }
      t.references :menu_item, null: false, foreign_key: { to_table: :takeaway_menu_items }
      t.integer :quantity
      t.integer :unit_price_cents
      t.timestamps
    end
    execute <<~SQL.squish
      INSERT INTO takeaway_order_items (id, order_id, menu_item_id, quantity, unit_price_cents, created_at, updated_at)
      SELECT id, order_id, menu_item_id, quantity, unit_price_cents, created_at, updated_at
      FROM takeaway_order_items_legacy
    SQL
    drop_table :takeaway_order_items_legacy
    execute "PRAGMA foreign_keys = ON"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end