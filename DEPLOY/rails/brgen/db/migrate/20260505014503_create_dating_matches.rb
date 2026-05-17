class CreateDatingMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_matches do |t|
      t.references :initiator, null: false, foreign_key: true
      t.references :receiver, null: false, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
