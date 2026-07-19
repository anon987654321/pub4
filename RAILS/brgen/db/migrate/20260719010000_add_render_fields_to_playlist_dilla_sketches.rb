# frozen_string_literal: true

class AddRenderFieldsToPlaylistDillaSketches < ActiveRecord::Migration[8.1]
  def change
    change_table :playlist_dilla_sketches, bulk: true do |t|
      t.string :render_status, default: "idle", null: false unless column_exists?(:playlist_dilla_sketches, :render_status)
      t.string :style, default: "dilla" unless column_exists?(:playlist_dilla_sketches, :style)
      t.integer :bars, default: 12 unless column_exists?(:playlist_dilla_sketches, :bars)
      unless column_exists?(:playlist_dilla_sketches, :track_id)
        t.references :track, foreign_key: { to_table: :playlist_tracks }, null: true
      end
      t.text :render_error unless column_exists?(:playlist_dilla_sketches, :render_error)
      t.datetime :rendered_at unless column_exists?(:playlist_dilla_sketches, :rendered_at)
    end
  end
end
