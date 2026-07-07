# frozen_string_literal: true

class WireSocialLiveMessagesAndWardrobeIntelligence < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :addressee, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :connections, %i[requester_id addressee_id], unique: true
    add_index :connections, %i[addressee_id status]

    create_table :live_streams do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "scheduled"
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :ended_at
      t.integer :viewer_count, null: false, default: 0
      t.timestamps
    end
    add_index :live_streams, %i[status scheduled_at]

    create_table :messages do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :read_at
      t.timestamps
    end
    add_index :messages, %i[recipient_id read_at created_at]
    add_index :messages, %i[sender_id recipient_id created_at]

    add_column :items, :analysis_status, :string, default: "pending", null: false unless column_exists?(:items, :analysis_status)
    change_column_default :items, :analysis_status, from: nil, to: "pending" if column_exists?(:items, :analysis_status)
    change_column_null :items, :analysis_status, false, "pending" if column_exists?(:items, :analysis_status)
    add_index :items, :analysis_status unless index_exists?(:items, :analysis_status)
  end
end
