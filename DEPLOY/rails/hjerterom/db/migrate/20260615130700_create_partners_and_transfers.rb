# frozen_string_literal: true

class CreatePartnersAndTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :partners do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "food_bank"
      t.string :contact_email
      t.string :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    create_table :transfers do |t|
      t.references :partner, null: false, foreign_key: true
      t.references :beneficiary, foreign_key: true
      t.references :box, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :scheduled_at
      t.datetime :completed_at
      t.integer :items_count, default: 0
      t.text :notes
      t.timestamps
    end

    add_column :beneficiaries, :dietary_needs, :text
    add_column :beneficiaries, :preferred_categories, :text
    add_column :food_items, :match_score, :integer
  end
end