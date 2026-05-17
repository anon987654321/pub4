class CreateDatingDislikes < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_dislikes do |t|
      t.references :disliker, null: false, foreign_key: true
      t.references :dislikee, null: false, foreign_key: true

      t.timestamps
    end
  end
end
