# frozen_string_literal: true

class CreateTvComments < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_comments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :video, null: false, foreign_key: { to_table: :tv_videos }
      t.text :body, null: false
      t.timestamps
    end
  end
end
