# frozen_string_literal: true

class CreateHjerteromCore < ActiveRecord::Migration[8.0]
  def change
    create_table :donors do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    create_table :beneficiaries do |t|
      t.string :name, null: false
      t.string :area
      t.integer :household_size
      t.integer :priority, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    create_table :donations do |t|
      t.references :donor, foreign_key: true
      t.string :source_name, null: false
      t.string :pickup_window
      t.integer :status, null: false, default: 0
      t.text :notes
      t.timestamps
    end

    create_table :boxes do |t|
      t.references :beneficiary, foreign_key: true
      t.date :week_start, null: false
      t.integer :status, null: false, default: 0
      t.text :notes
      t.timestamps
    end

    create_table :food_items do |t|
      t.references :donation, null: false, foreign_key: true
      t.references :box, foreign_key: true
      t.string :name, null: false
      t.integer :quantity
      t.integer :category, null: false, default: 6
      t.integer :quality_state, null: false, default: 0
      t.date :best_before
      t.text :notes
      t.timestamps
    end

    create_table :volunteers do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    create_table :shifts do |t|
      t.references :volunteer, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :kind, null: false, default: 1
      t.integer :state, null: false, default: 0
      t.string :location
      t.text :notes
      t.timestamps
    end
  end
end
