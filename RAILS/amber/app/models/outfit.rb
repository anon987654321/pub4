# frozen_string_literal: true

class Outfit < ApplicationRecord
  # Engine-ize Shared via pub4-shared
  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  # Same card/thumb sizes as Item photos for grid consistency.
  IMAGE_VARIANTS = Item::PHOTO_VARIANTS

  has_one_attached :image do |attachable|
    IMAGE_VARIANTS.each do |name, transformations|
      attachable.variant(name, **transformations)
    end
  end

  scope :with_images_for_display, -> {
    includes(
      image_attachment: { blob: :variant_records },
      items: { photos_attachments: { blob: :variant_records } }
    )
  }

  validates :name, presence: true
  accepts_nested_attributes_for :outfit_items, allow_destroy: true, reject_if: :reject_blank_outfit_item

  broadcasts_refreshes

  def like!
    increment!(:likes_count)
  end

  def context_label
    [ season, category, occasion ].compact_blank.join(" · ")
  end

  def total_wears
    items.sum { |item| item.times_worn.to_i }
  end

  def estimated_value
    items.sum { |item| item.price_cents.to_i } / 100.0
  end

  def reject_blank_outfit_item(attrs)
    attrs["item_id"].blank? && attrs["_destroy"].blank?
  end
end
