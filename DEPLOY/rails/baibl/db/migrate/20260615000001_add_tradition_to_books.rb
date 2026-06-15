class AddTraditionToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :tradition, :string
    add_index :books, :tradition
  end
end
