# frozen_string_literal: true

# A crosspost is the same content in a second community, with its own comment
# thread — the Reddit shape, and a different act from a repost, which boosts
# into followers' timelines and carries no community of its own.
class AddCrosspostsToPosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :posts, :crossposted_from, null: true, foreign_key: { to_table: :posts }
    # The source post says how far it travelled. A counter, because the post page
    # renders it and a COUNT per card is a query per card.
    add_column :posts, :crossposts_count, :integer, default: 0, null: false
  end
end
