# frozen_string_literal: true

class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.references :post, foreign_key: true
      t.references :user, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :prep_time_minutes
      t.integer :cook_time_minutes
      t.integer :servings
      t.string :cuisine
      t.timestamps
    end

    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :name, null: false
      t.string :quantity
      t.string :unit
      t.integer :position, default: 0
      t.timestamps
    end
  end
end