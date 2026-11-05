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

  # The fourteen allergens EU food information rules name, in their usual
  # order. A dish stores the keys it contains. nil means the kitchen has not
  # said, which the menu shows as exactly that; [] means none of the fourteen.
  # Only the kitchen knows what is in its food, so nothing here guesses.
  ALLERGENS = %w[
    gluten crustaceans eggs fish peanuts soybeans milk nuts celery mustard sesame sulphites lupin molluscs
  ].freeze
  serialize :allergens, coder: JSON

  validates :name, :price_cents, presence: true
  validate :allergens_are_the_fourteen
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

  def allergens_stated? = !allergens.nil?

  # The stated allergens in the regulation's order.
  def allergen_keys = ALLERGENS & Array(allergens)

  # "fish and milk", in the reader's language.
  def allergen_sentence = allergen_keys.map { I18n.t("takeaway.allergen_names.#{_1}") }.to_sentence

  # Each of the fourteen with whether this dish is stated to contain it; the
  # kitchen's form draws one box per pair.
  def allergen_choices = ALLERGENS.map { [ _1, allergen_keys.include?(_1) ] }

  # From the form: the ticked boxes, kept only when the kitchen also ticked
  # that it has checked them. Unticked, the dish stays (or goes back to) unstated.
  def self.allergens_from(params)
    return nil unless ActiveModel::Type::Boolean.new.cast(params[:allergens_stated])

    ALLERGENS & Array(params[:allergens]).map(&:to_s)
  end

  private

  def allergens_are_the_fourteen
    return if allergens.nil?

    errors.add(:allergens, :invalid) unless allergens.is_a?(Array) && (allergens - ALLERGENS).empty?
  end

  def menu_category_belongs_to_this_restaurant
    return unless menu_category && restaurant
    return if menu_category.restaurant_id == restaurant.id

    errors.add(:menu_category, :invalid)
  end
end
