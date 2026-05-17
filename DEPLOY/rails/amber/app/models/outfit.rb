class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  validates :name, presence: true

  broadcasts_refreshes

  def like!
    increment!(:likes_count)
  end
end
