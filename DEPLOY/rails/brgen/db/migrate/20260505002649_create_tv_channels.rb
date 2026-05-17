class CreateTvChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_channels do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :slug
      t.integer :subscribers_count
      t.integer :total_views

      t.timestamps
    end
  end
end
