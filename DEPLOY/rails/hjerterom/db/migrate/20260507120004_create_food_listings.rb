class CreateFoodListings < ActiveRecord::Migration[8.1]
  def change
    create_table :food_listings do |t|
      t.references :user, foreign_key: true
      t.string :title
      t.text :description
      t.integer :quantity
      t.string :unit
      t.datetime :available_from
      t.datetime :available_until
      t.string :pickup_address
      t.string :city
      t.float :latitude
      t.float :longitude
      t.string :status
      t.string :dietary_info
      t.timestamps
    end
  end
end
