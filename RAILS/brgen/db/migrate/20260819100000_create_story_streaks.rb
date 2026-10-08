# frozen_string_literal: true

# How many days running two people have answered each other's stories.
#
# The Snapchat shape: a streak is mutual, not a personal posting habit. One row
# per pair, with the pair stored in id order so a lookup never has to try both
# ways round.
class CreateStoryStreaks < ActiveRecord::Migration[8.1]
  def change
    create_table :story_streaks do |t|
      t.references :user_a, null: false, foreign_key: { to_table: :users }
      t.references :user_b, null: false, foreign_key: { to_table: :users }
      t.integer :days, null: false, default: 0
      # A date, not a timestamp: a streak is counted in days, and the question
      # asked of this column is always "was that yesterday".
      t.date :last_day
      t.timestamps
    end

    add_index :story_streaks, %i[user_a_id user_b_id], unique: true
  end
end
