class CreateFoodRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :food_requests do |t|
      t.references :food_listing, foreign_key: true
      t.references :user, foreign_key: true
      t.text :message
      t.string :status
      t.datetime :pickup_time
      t.timestamps
    end
  end
end
