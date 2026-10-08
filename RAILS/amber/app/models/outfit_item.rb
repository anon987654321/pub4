# frozen_string_literal: true

class OutfitItem < ApplicationRecord
  belongs_to :outfit
  belongs_to :item

  validates :outfit, :item, presence: true
  validates :item_id, uniqueness: { scope: :outfit_id }
  validate :item_belongs_to_outfit_owner
  default_scope { order(:position) }

  private

  def item_belongs_to_outfit_owner
    return if item.blank? || outfit.blank?
    return if item.user_id == outfit.user_id

    errors.add(:item_id, :invalid)
  end
end
