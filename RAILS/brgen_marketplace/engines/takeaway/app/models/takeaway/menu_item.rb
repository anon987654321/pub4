# frozen_string_literal: true

class Takeaway::MenuItem < ApplicationRecord
  include Shared::MediaProcessable
  tracks_activity created: "TakeawayMenuItemCreated", updated: "TakeawayMenuItemUpdated", source_vertical: "takeaway", actor: :restaurant_owner

  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  belongs_to :menu_category, class_name: "Takeaway::MenuCategory", optional: true
  has_one_attached :photo
  process_media_variants :photo, variants: {
    thumb: { resize_to_limit: [ 320, 320 ], format: :webp },
    card: { resize_to_limit: [ 720, 540 ], format: :webp },
  }

  validates :name, :price_cents, presence: true
  validates :price_cents, numericality: { greater_than: 0 }
  validate :menu_category_belongs_to_this_restaurant
  before_validation { self.available = true if available.nil? }

  scope :available, -> { where(available: true) }

  def price_display = Shared::MoneyDisplay.format(price_cents)
  # tracks_activity actor — runs in an after_commit on a menu item loaded by id,
  # where `restaurant&.user` was a lazy read. See Shared::StrictSafeAssociations.
  def restaurant_owner = strict_safe(:restaurant)&.user
  # OrderItem validates through this on a dish a controller found by id, with
  # no restaurant preloaded; a plain read raised before the order was saved.
  def available_for_order? = available? && strict_safe(:restaurant)&.active?

  private

  def menu_category_belongs_to_this_restaurant
    return unless menu_category && restaurant
    return if menu_category.restaurant_id == restaurant.id

    errors.add(:menu_category, :invalid)
  end
end
