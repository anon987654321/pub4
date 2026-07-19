# frozen_string_literal: true

class AddRenderFieldsToPlaylistDillaSketches < ActiveRecord::Migration[8.1]
  def change
    change_table :playlist_dilla_sketches, bulk: true do |t|
      t.string :render_status, default: "idle", null: false
      t.string :style, default: "dilla"
      t.integer :bars, default: 12
      t.references :track, foreign_key: { to_table: :playlist_tracks }, null: true
      t.text :render_error
      t.datetime :rendered_at
    end
  end
end
