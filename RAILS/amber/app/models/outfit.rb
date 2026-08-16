# frozen_string_literal: true

class Outfit < ApplicationRecord
  # Engine-ize Shared via pub4-shared
  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  # Three tables carry a foreign key to outfits and this model declared none of
  # them, so `OutfitsController#destroy` raised ActiveRecord::InvalidForeignKey
  # — a 500 on the delete button — for any outfit that had ever been worn or
  # planned. The schema has the constraint; only the model did not know.
  #
  # The two dependent options are different on purpose:
  #
  #   wear_logs        nullify. A wear happened. Deleting the outfit deletes the
  #                    grouping, not the history, and every garment's times_worn
  #                    already counts it. WearLog#outfit is `optional: true`,
  #                    which is the same statement from the other side.
  #   planned_outfits  destroy. A plan to wear an outfit that no longer exists
  #                    is not a plan.
  has_many :wear_logs, dependent: :nullify, strict_loading: false
  has_many :planned_outfits, dependent: :destroy, strict_loading: false

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
