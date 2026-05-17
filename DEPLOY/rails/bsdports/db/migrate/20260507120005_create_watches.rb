class CreateWatches < ActiveRecord::Migration[8.1]
  def change
    create_table :watches do |t|
      t.references :user, foreign_key: true
      t.references :port, foreign_key: true
      t.boolean :notify_on_update, default: true
      t.timestamps
    end
  end
end
