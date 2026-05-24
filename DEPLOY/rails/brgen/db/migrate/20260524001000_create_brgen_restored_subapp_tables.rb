# frozen_string_literal: true

class CreateBrgenRestoredSubappTables < ActiveRecord::Migration[8.0]
  def change
    create_table :playlist_sets, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :privacy, default: "public"
      t.boolean :collaborative, null: false, default: false
      t.timestamps
    end

    create_table :playlist_collaborations, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :set, foreign_key: { to_table: :playlist_sets }
      t.references :playlist
      t.string :role, null: false, default: "editor"
      t.timestamps
    end
    add_index :playlist_collaborations, %i[user_id set_id playlist_id], unique: true, name: "idx_playlist_collab_unique", if_not_exists: true

    create_table :playlist_likes, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :set, foreign_key: { to_table: :playlist_sets }
      t.references :playlist
      t.timestamps
    end
    add_index :playlist_likes, %i[user_id set_id playlist_id], unique: true, name: "idx_playlist_likes_unique", if_not_exists: true

    create_table :takeaway_delivery_drivers, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :vehicle_type
      t.string :license_number
      t.boolean :available, null: false, default: false
      t.decimal :current_lat, precision: 10, scale: 6
      t.decimal :current_lng, precision: 10, scale: 6
      t.timestamps
    end
    add_index :takeaway_delivery_drivers, %i[available current_lat current_lng], name: "idx_takeaway_drivers_available_location", if_not_exists: true

    create_table :tv_live_streams, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :channel, foreign_key: { to_table: :tv_channels }
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "scheduled"
      t.integer :viewer_count, null: false, default: 0
      t.string :stream_key
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end
    add_index :tv_live_streams, :stream_key, unique: true, if_not_exists: true
    add_index :tv_live_streams, %i[status updated_at], if_not_exists: true

    create_table :tv_stream_chats, if_not_exists: true do |t|
      t.references :live_stream, null: false, foreign_key: { to_table: :tv_live_streams }
      t.references :user, null: false, foreign_key: true
      t.text :message, null: false
      t.timestamps
    end
    add_index :tv_stream_chats, %i[live_stream_id created_at], if_not_exists: true

    create_table :tv_video_notes, if_not_exists: true do |t|
      t.references :video, null: false, foreign_key: { to_table: :tv_videos }
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :timestamp
      t.timestamps
    end
    add_index :tv_video_notes, %i[video_id timestamp created_at], if_not_exists: true
  end
end
