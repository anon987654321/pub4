# frozen_string_literal: true

class CreatePlaylistDillaSketches < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_dilla_sketches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :playlist, foreign_key: { to_table: :playlist_playlists }
      t.references :set, foreign_key: { to_table: :playlist_sets }
      t.string :name, null: false
      t.jsonb :state, null: false, default: {}
      t.text :notes
      t.timestamps
    end

    add_index :playlist_dilla_sketches, [:playlist_id, :created_at]
    add_index :playlist_dilla_sketches, [:set_id, :created_at]
    add_index :playlist_dilla_sketches, :user_id
  end
end
