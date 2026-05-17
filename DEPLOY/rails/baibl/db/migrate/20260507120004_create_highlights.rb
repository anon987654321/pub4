class CreateHighlights < ActiveRecord::Migration[8.1]
  def change
    create_table :highlights do |t|
      t.references :verse, foreign_key: true
      t.references :user, foreign_key: true
      t.string :color
      t.text :note
      t.timestamps
    end
  end
end
