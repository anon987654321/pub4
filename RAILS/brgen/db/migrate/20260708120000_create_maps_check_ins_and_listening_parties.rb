# frozen_string_literal: true

class CreateMapsCheckInsAndListeningParties < ActiveRecord::Migration[8.1]
  def change
    create_table :place_check_ins do |t|
      t.references :place, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :note
      t.datetime :checked_in_at, null: false
      t.timestamps
    end
    add_index :place_check_ins, %i[place_id user_id checked_in_at]

    create_table :playlist_listening_parties do |t|
      t.references :playlist_set, null: false, foreign_key: true
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "active"
      t.references :current_track, foreign_key: { to_table: :playlist_tracks }
      t.integer :position_seconds, null: false, default: 0
      t.string :join_code, null: false
      t.timestamps
    end
    add_index :playlist_listening_parties, :join_code, unique: true
    add_index :playlist_listening_parties, %i[playlist_set_id status]

    create_table :playlist_party_messages do |t|
      t.references :listening_party, null: false, foreign_key: { to_table: :playlist_listening_parties }
      t.references :user, null: false, foreign_key: true
      t.string :body, null: false, limit: 500
      t.timestamps
    end
    add_index :playlist_party_messages, %i[listening_party_id created_at],
              name: "idx_party_messages_on_party_and_created_at"
  end
end