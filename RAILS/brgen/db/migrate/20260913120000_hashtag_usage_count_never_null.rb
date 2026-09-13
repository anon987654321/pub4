# frozen_string_literal: true

# usage_count carries the number of records using a tag, and Taggable moves it
# with increment! and decrement!. Both raise on nil, so every hashtag created
# before this migration was one edit away from breaking the save that touched
# it — and a tag is created by the same after_save that then increments it.
#
# The backfill counts taggings rather than writing zero, because the column has
# been nullable for long enough that some of those tags are in use.
class HashtagUsageCountNeverNull < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE hashtags
         SET usage_count = (SELECT COUNT(*) FROM taggings WHERE taggings.hashtag_id = hashtags.id)
       WHERE usage_count IS NULL
    SQL
    change_column_default :hashtags, :usage_count, 0
    change_column_null :hashtags, :usage_count, false
  end

  def down
    change_column_null :hashtags, :usage_count, true
    change_column_default :hashtags, :usage_count, nil
  end
end
