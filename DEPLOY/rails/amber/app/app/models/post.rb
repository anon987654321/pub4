class Post < ApplicationRecord
  belongs_to :user
  belongs_to :outfit, optional: true
  belongs_to :item,   optional: true
  validates :body, presence: true, length: { maximum: 500 }
  scope :recent, -> { order(created_at: :desc) }
  def like! = increment!(:likes_count)
end
