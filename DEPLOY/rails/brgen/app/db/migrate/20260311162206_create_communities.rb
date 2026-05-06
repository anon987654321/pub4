class CreateCommunities < ActiveRecord::Migration[8.1]
  def change
    create_table :communities do |t|
      t.string :name
      t.text :description
      t.string :subdomain
      t.string :slug

      t.timestamps
    end
    add_index :communities, :subdomain, unique: true
    add_index :communities, :slug, unique: true
  end
end
