# frozen_string_literal: true

class CreatorWardrobeItem < ApplicationRecord
  belongs_to :creator_profile
  belongs_to :item

  validates :item_id, uniqueness: { scope: :creator_profile_id }
  validates :caption, length: { maximum: 300 }
end
