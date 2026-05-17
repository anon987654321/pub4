class WearLog < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :outfit, optional: true

  validates :worn_on, presence: true
  validates :context, length: { maximum: 300 }

  scope :recent, -> { order(worn_on: :desc, created_at: :desc) }
end
