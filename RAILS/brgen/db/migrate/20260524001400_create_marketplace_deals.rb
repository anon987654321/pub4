# frozen_string_literal: true

class CreateMarketplaceDeals < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_deals, if_not_exists: true do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.string :headline, null: false
      t.string :badge
      t.integer :discount_percent
      t.integer :priority, null: false, default: 0
      t.boolean :featured, null: false, default: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end

    add_index :marketplace_deals, %i[featured priority], if_not_exists: true
    add_index :marketplace_deals, %i[starts_at ends_at], if_not_exists: true
  end
end
