# frozen_string_literal: true

class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.string :title
      t.string :category
      t.string :color
      t.string :size
      t.string :material
      t.string :brand
      t.decimal :price
      t.integer :times_worn
      t.date :purchase_date
      t.boolean :spark_joy
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
