class Bookmark < ApplicationRecord
  belongs_to :verse
  belongs_to :user

  validates :verse_id, uniqueness: { scope: :user_id }

  after_create_commit -> { broadcast_append_to [user, "bookmarks"] }
end
