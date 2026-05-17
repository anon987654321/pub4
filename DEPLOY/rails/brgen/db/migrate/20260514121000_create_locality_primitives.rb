class CreateLocalityPrimitives < ActiveRecord::Migration[8.0]
  def change
    create_table :cities do |t|
      t.string :country_code, null: false
      t.string :currency, null: false
      t.string :domain, null: false
      t.decimal :latitude, precision: 10, scale: 6
      t.string :locale, null: false
      t.decimal :longitude, precision: 10, scale: 6
      t.string :name, null: false
      t.string :slug, null: false
      t.string :time_zone
      t.timestamps
    end

    add_index :cities, :domain, unique: true
    add_index :cities, :slug, unique: true

    create_table :neighborhoods do |t|
      t.references :city, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end

    add_index :neighborhoods, [:city_id, :slug], unique: true

    create_table :places do |t|
      t.references :city, null: false, foreign_key: true
      t.references :neighborhood, foreign_key: true
      t.string :address
      t.string :kind, null: false
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.string :name, null: false
      t.string :slug
      t.timestamps
    end

    add_index :places, [:city_id, :kind]
    add_index :places, [:city_id, :slug]
  end
end
