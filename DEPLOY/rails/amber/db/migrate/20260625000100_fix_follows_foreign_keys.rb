# frozen_string_literal: true

class FixFollowsForeignKeys < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:follows)

    remove_foreign_key :follows, column: :follower_id if foreign_key_exists?(:follows, column: :follower_id)
    remove_foreign_key :follows, column: :followee_id if foreign_key_exists?(:follows, column: :followee_id)
    add_foreign_key :follows, :users, column: :follower_id unless foreign_key_exists?(:follows, column: :follower_id)
    add_foreign_key :follows, :users, column: :followee_id unless foreign_key_exists?(:follows, column: :followee_id)
  end

  def down
    return unless table_exists?(:follows)

    remove_foreign_key :follows, column: :follower_id if foreign_key_exists?(:follows, column: :follower_id)
    remove_foreign_key :follows, column: :followee_id if foreign_key_exists?(:follows, column: :followee_id)
  end
end