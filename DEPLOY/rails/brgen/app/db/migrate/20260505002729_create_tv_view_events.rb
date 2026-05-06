class CreateTvViewEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_view_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tv_video, null: false, foreign_key: true
      t.integer :watch_time_seconds
      t.boolean :completed

      t.timestamps
    end
  end
end
