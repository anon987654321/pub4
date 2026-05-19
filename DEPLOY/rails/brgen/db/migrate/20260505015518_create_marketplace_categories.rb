# frozen_string_literal: true

class CreateMarketplaceCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_categories do |t|
      t.string :name
      t.string :slug
      t.integer :parent_id

      t.timestamps
    end
  end
end
