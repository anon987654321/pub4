# frozen_string_literal: true

class AddLocalDiscoveryAndBuyBox < ActiveRecord::Migration[8.2]
  def change
    add_reference :posts, :neighborhood, foreign_key: true
    add_column :dating_profiles, :location_discovery_enabled, :boolean, default: false, null: false
    add_column :marketplace_listings, :buy_box_key, :string
    add_index :marketplace_listings, %i[city_id buy_box_key],
              where: "buy_box_key IS NOT NULL",
              name: "index_marketplace_listings_on_city_and_buy_box_key"

    create_table :dating_location_pings do |t|
      t.references :city, null: false, foreign_key: true
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :neighborhood, foreign_key: true
      t.decimal :latitude, precision: 8, scale: 3, null: false
      t.decimal :longitude, precision: 8, scale: 3, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :dating_location_pings, :user_id, unique: true
    add_index :dating_location_pings, %i[city_id expires_at]

    create_table :dating_path_crossings do |t|
      t.references :city, null: false, foreign_key: true
      t.references :user_a, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :user_b, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :neighborhood, foreign_key: true
      t.date :crossing_on, null: false
      t.datetime :crossed_at, null: false
      t.decimal :approx_latitude, precision: 5, scale: 2
      t.decimal :approx_longitude, precision: 5, scale: 2
      t.timestamps
    end
    add_index :dating_path_crossings, %i[city_id user_a_id user_b_id crossing_on],
              unique: true, name: "index_dating_path_crossings_on_pair_and_day"
    add_index :dating_path_crossings, %i[city_id crossed_at]
  end
end
