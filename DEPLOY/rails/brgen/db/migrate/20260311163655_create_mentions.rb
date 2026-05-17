class CreateMentions < ActiveRecord::Migration[8.0]
  def change
    create_table :mentions do |t|
      t.references :mentionable, polymorphic: true, null: false
      t.references :mentioned_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
