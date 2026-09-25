class CreateDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :domains do |t|
      t.string :name, null: false
      t.string :state, null: false, default: "pending"
      t.datetime :expires_at
      t.string :registry_id
      t.timestamps
    end

    add_index :domains, :name, unique: true
    add_index :domains, :state
    add_index :domains, :expires_at
  end
end
