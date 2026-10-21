# frozen_string_literal: true

# One owner's care record on an Item, not a second garment model: the Item is
# what the garment is, and condition belongs to one owner's copy of it.
class WardrobeItem < ApplicationRecord
  CONDITIONS = %w[new excellent good worn repair retire].freeze

  belongs_to :user
  belongs_to :item

  validates :condition, inclusion: { in: CONDITIONS }, allow_blank: true
  validates :user_id, uniqueness: { scope: :item_id }
  validate :item_belongs_to_user

  scope :recent, -> { order(created_at: :desc) }
  scope :needs_attention, -> { where(condition: %w[repair retire]) }

  def item_belongs_to_user
    return if item_id.blank? || user_id.blank?
    return if Item.where(id: item_id, user_id: user_id).exists?

    errors.add(:item_id, :invalid)
  end

  def age_in_days
    return 0 unless acquisition_date

    (Date.current - acquisition_date).to_i
  end
end
