class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :name
      t.string :abbreviation
      t.string :testament
      t.integer :chapter_count
      t.integer :order_index
      t.timestamps
    end
  end
end
