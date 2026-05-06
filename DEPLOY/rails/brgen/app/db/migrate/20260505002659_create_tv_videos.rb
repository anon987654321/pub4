class CreateTvVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_videos do |t|
      t.references :tv_channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.string :status
      t.integer :duration_seconds
      t.integer :views_count
      t.integer :likes_count
      t.integer :comments_count
      t.datetime :published_at
      t.string :thumbnail_url

      t.timestamps
    end
  end
end
