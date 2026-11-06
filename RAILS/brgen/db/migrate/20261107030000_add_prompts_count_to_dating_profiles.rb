# frozen_string_literal: true

# The deck ranked effort by a correlated COUNT over dating_prompts for every
# candidate profile, re-sorted on every deck render and every swipe frame.
# A counter cache column answers the same question from the row itself.
# Backfilled once here; kept in sync afterwards by the has_many's
# counter_cache, which every prompt path already honours (creation and
# destroy both go through the profile association).
class AddPromptsCountToDatingProfiles < ActiveRecord::Migration[8.2]
  def up
    add_column :dating_profiles, :prompts_count, :integer, default: 0, null: false
    execute <<~SQL.squish
      UPDATE dating_profiles SET prompts_count =
        (SELECT COUNT(*) FROM dating_prompts WHERE dating_prompts.profile_id = dating_profiles.id)
    SQL
  end

  def down
    remove_column :dating_profiles, :prompts_count
  end
end
