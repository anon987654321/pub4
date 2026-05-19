# frozen_string_literal: true

class CreateMarketplaceOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_orders do |t|
      t.references :buyer, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.string :status
      t.text :message
      t.integer :price_cents

      t.timestamps
    end
  end
end
