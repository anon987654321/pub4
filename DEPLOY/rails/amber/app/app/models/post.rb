class Post < ApplicationRecord
  belongs_to :user
  belongs_to :outfit, optional: true, touch: true
  belongs_to :item,   optional: true, touch: true

  validates :body, presence: true, length: { maximum: 500 }

  scope :recent, -> { order(created_at: :desc) }

  broadcasts_refreshes

  def like! = increment!(:likes_count)
end
