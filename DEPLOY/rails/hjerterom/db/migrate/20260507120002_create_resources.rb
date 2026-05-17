class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.references :user, foreign_key: true
      t.references :category, foreign_key: true
      t.string :title
      t.text :description
      t.string :url
      t.string :address
      t.string :city
      t.string :postal_code
      t.float :latitude
      t.float :longitude
      t.string :phone
      t.string :email
      t.boolean :verified, default: false
      t.string :resource_type
      t.text :opening_hours
      t.timestamps
    end
  end
end
