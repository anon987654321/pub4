# frozen_string_literal: true

class CreateTvShowsAndEpisodes < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_shows do |t|
      t.references :channel, null: false, foreign_key: { to_table: :tv_channels }
      t.string :title, null: false
      t.text :description
      t.string :slug, null: false
      t.boolean :published, null: false, default: false
      t.timestamps
    end
    add_index :tv_shows, %i[channel_id slug], unique: true

    create_table :tv_episodes do |t|
      t.references :show, null: false, foreign_key: { to_table: :tv_shows }
      t.references :video, foreign_key: { to_table: :tv_videos }
      t.string :title, null: false
      t.integer :number, null: false
      t.timestamps
    end
    add_index :tv_episodes, %i[show_id number], unique: true
  end
end
