# frozen_string_literal: true

# Quote-post is a Repost that carries a comment, not a Post. Post includes
# Shared::Sluggable (title unique per city), so a quote-as-Post would collide
# with the thing it quoted. Empty comment stays a boost; uniqueness on
# user+post is unchanged, so one row is either a boost or a quote.
class AddCommentToReposts < ActiveRecord::Migration[8.1]
  def change
    add_column :reposts, :comment, :text
  end
end
