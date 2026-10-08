# frozen_string_literal: true

# tv_videos.likes_count and comments_count were created with the table and
# nothing has written or read either since: Tv::Comment carries no counter
# cache, and reactions count through Shared::Reactable. A column that always
# reads nil invites a ranking or a card to trust it.
class DropUnwrittenTvVideoCounters < ActiveRecord::Migration[8.1]
  def change
    remove_column :tv_videos, :likes_count, :integer
    remove_column :tv_videos, :comments_count, :integer
  end
end
