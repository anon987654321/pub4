class Highlight < ApplicationRecord
  belongs_to :verse
  belongs_to :user

  COLORS = %w[yellow green blue pink orange].freeze

  validates :color, inclusion: { in: COLORS }
  validates :verse_id, uniqueness: { scope: :user_id }

  after_create_commit -> { broadcast_replace_to [user, "highlights"] }
end
