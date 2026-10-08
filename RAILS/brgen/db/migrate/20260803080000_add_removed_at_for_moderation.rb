# frozen_string_literal: true

# Content takedown: resolving a moderation report must be able to actually remove
# the reported post/comment, not just close the flag. A nullable timestamp keeps
# it reversible (un-remove = set NULL) and auditable (when), and feeds filter on
# `removed_at IS NULL` via the `kept` scope.
class AddRemovedAtForModeration < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :removed_at, :datetime unless column_exists?(:posts, :removed_at)
    add_column :comments, :removed_at, :datetime unless column_exists?(:comments, :removed_at)
    add_index :posts, :removed_at unless index_exists?(:posts, :removed_at)
    add_index :comments, :removed_at unless index_exists?(:comments, :removed_at)
  end
end
