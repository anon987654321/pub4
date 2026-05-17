class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name
      t.integer :posts_count, default: 0
      t.timestamps
    end
    add_index :tags, :name, unique: true
  end
end
