class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.string :conversation_type
      t.string :name

      t.timestamps
    end
  end
end
