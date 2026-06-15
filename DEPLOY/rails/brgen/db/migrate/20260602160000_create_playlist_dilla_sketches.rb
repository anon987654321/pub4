# frozen_string_literal: true

class CreatePlaylistDillaSketches < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_dilla_sketches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :playlist, foreign_key: { to_table: :playlist_playlists }
      t.references :set, foreign_key: { to_table: :playlist_sets }
      t.string :name, null: false
      t.json :state, null: false, default: {}
      t.text :notes
      t.timestamps
    end

    add_index :playlist_dilla_sketches, %i[playlist_id created_at], if_not_exists: true
    add_index :playlist_dilla_sketches, %i[set_id created_at], if_not_exists: true
  end
end
