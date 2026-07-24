# frozen_string_literal: true

class AddGeoToPostsForLive < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:posts, :latitude)

    add_column :posts, :latitude, :decimal, precision: 10, scale: 6
    add_column :posts, :longitude, :decimal, precision: 10, scale: 6
    add_index :posts, %i[latitude longitude], name: "index_posts_on_latitude_and_longitude"
  end
end
