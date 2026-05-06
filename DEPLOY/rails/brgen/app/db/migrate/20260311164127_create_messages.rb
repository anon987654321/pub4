class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :sender_id
      t.text :content
      t.string :message_type
      t.datetime :expires_at

      t.timestamps
    end
  end
end
