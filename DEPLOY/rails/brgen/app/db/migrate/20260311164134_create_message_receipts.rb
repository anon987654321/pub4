class CreateMessageReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :message_receipts do |t|
      t.references :message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :delivered_at
      t.datetime :read_at

      t.timestamps
    end
  end
end
