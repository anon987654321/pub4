# frozen_string_literal: true

# Two changes to how dating works here.
#
# First: the deck was ORDER BY RANDOM(). Orientation, neighbourhood and a 20 km
# radius filtered the pool and nothing ranked it, so someone who last opened the
# app in March sat in the deck beside someone who is online now — and every
# reload reshuffled, so nobody could find a profile they had just seen.
#
# Second: prompts. The current shape of this category is Hinge, not Tinder —
# you like a specific answer or photo and say something about it, rather than
# swiping on a whole person. A like that carries a sentence is a different
# product from a like that carries nothing.
class CreateDatingPrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_prompts do |t|
      t.references :profile, null: false, foreign_key: { to_table: :dating_profiles }
      t.string :question, null: false
      t.string :answer, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :dating_prompts, %i[profile_id position]

    change_table :dating_likes, bulk: true do |t|
      # Hinge's whole interaction: the like points at the thing it is about.
      t.references :dating_prompt, foreign_key: { to_table: :dating_prompts }
      t.string :comment
    end

    change_table :dating_profiles, bulk: true do |t|
      # Ranking input. Distinct from updated_at, which changes when a photo is
      # processed in the background and would otherwise read as activity.
      t.datetime :last_active_at
    end
    add_index :dating_profiles, %i[visible last_active_at]
  end
end
