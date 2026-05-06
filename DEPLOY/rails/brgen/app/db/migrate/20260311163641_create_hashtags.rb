class CreateHashtags < ActiveRecord::Migration[8.1]
  def change
    create_table :hashtags do |t|
      t.string :name
      t.integer :usage_count

      t.timestamps
    end
    add_index :hashtags, :name, unique: true
  end
end
