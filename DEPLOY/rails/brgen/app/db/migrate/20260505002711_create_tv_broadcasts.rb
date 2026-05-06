class CreateTvBroadcasts < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_broadcasts do |t|
      t.references :tv_channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.string :status
      t.string :stream_key
      t.integer :viewer_count
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end
  end
end
