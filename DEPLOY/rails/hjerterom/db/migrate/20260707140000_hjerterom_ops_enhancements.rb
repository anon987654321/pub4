# frozen_string_literal: true

class HjerteromOpsEnhancements < ActiveRecord::Migration[8.1]
  def change
    change_table :volunteers, bulk: true do |t|
      t.references :user, foreign_key: true, null: true
    end

    change_table :beneficiaries, bulk: true do |t|
      t.float :latitude
      t.float :longitude
      t.string :address
    end

    change_table :donors, bulk: true do |t|
      t.float :latitude
      t.float :longitude
      t.string :address
    end

    change_table :food_items, bulk: true do |t|
      t.string :condition_label
      t.string :size_label
      t.string :age_range
      t.string :language_label
      t.string :reuse_status, default: "intake", null: false
    end

    create_table :delivery_routes do |t|
      t.date :route_date, null: false
      t.integer :status, default: 0, null: false
      t.references :volunteer, foreign_key: true, null: true
      t.text :notes
      t.timestamps
    end

    create_table :delivery_stops do |t|
      t.references :delivery_route, null: false, foreign_key: true
      t.integer :sequence, null: false, default: 0
      t.integer :stop_kind, default: 0, null: false
      t.string :label, null: false
      t.float :latitude
      t.float :longitude
      t.string :reference_type
      t.bigint :reference_id
      t.timestamps
      t.index %i[reference_type reference_id]
    end
  end
end