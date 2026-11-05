# frozen_string_literal: true

class MenuItem < ApplicationRecord
  include LocalizedColumns

  # The "best of the world's kebab" tour — every I18n origins.<origin> story
  # key comes from this list.
  # Bergen, not Oslo: one kitchen, Solheimsgaten 60 (Danmarksplass) — the home city origin.
  ORIGINS = %w[damaskus beirut berlin adana bergen dubai tel_aviv bursa gaziantep familie stockholm sydney].freeze

  # The 14 allergens food sold at a distance must name before purchase
  # (matinformasjonsforskriften vedlegg II, the EU's Annex II). allergens holds
  # a comma list of these keys, or "none"; blank means the kitchen has not
  # recorded the dish yet, and the item sheet says so instead of guessing.
  ALLERGENS = %w[gluten crustaceans eggs fish peanuts soybeans milk nuts celery mustard sesame sulphites
                 lupin molluscs].freeze
  NO_ALLERGENS = "none"

  belongs_to :menu_category
  has_many :item_options, dependent: :destroy

  validates :name, presence: true
  validates :price_ore, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :heat, inclusion: { in: 0..3 }
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  validate :allergens_are_known

  # The menu only sells what the kitchen can make today.
  scope :available, -> { where(available: true).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  # badges:string is a comma list ("signature,veg"); views render them as chips.
  def badges_list
    badges.to_s.split(",").map(&:strip).compact_blank
  end

  def listed_allergens
    allergens.to_s.split(",").map(&:strip).compact_blank - [ NO_ALLERGENS ]
  end

  def allergens_recorded?
    allergens.present?
  end

  private

  def allergens_are_known
    listed = allergens.to_s.split(",").map(&:strip).compact_blank
    return if listed == [ NO_ALLERGENS ] || (listed - ALLERGENS).empty?

    errors.add(:allergens, :inclusion)
  end
end
