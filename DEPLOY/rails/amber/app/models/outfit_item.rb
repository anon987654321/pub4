# frozen_string_literal: true

class OutfitItem < ApplicationRecord
  belongs_to :outfit
  belongs_to :item

  validates :outfit, :item, presence: true
  validates :item_id, uniqueness: { scope: :outfit_id }
  default_scope { order(:position) }
end
