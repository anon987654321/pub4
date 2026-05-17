class CreatorProfile < ApplicationRecord
  belongs_to :user
  has_many :creator_wardrobe_items, dependent: :destroy
  has_many :items, through: :creator_wardrobe_items

  validates :handle, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9_\.\-]+\z/ }
  validates :display_name, presence: true, length: { maximum: 80 }
  validates :bio, length: { maximum: 1_000 }

  normalizes :handle, with: ->(value) { value.to_s.strip.downcase }

  scope :publicly_visible, -> { where(public: true) }
end
