class CreatePlannedOutfits < ActiveRecord::Migration[8.1]
  def change
    create_table :planned_outfits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :outfit, null: false, foreign_key: true
      t.date :planned_date
      t.text :notes

      t.timestamps
    end
  end
end
