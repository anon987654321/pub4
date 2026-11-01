# frozen_string_literal: true

class MenuItem < ApplicationRecord
  # The "best of the world's kebab" tour — every I18n origins.<origin> story
  # key comes from this list.
  # Bergen, not Oslo: one kitchen, Strandgaten 47 — the home city origin.
  ORIGINS = %w[damaskus beirut berlin adana bergen dubai tel_aviv bursa gaziantep familie stockholm sydney].freeze

  belongs_to :menu_category
  has_many :item_options, dependent: :destroy

  validates :name, presence: true
  validates :price_ore, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :heat, inclusion: { in: 0..3 }
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true

  # The menu only sells what the kitchen can make today.
  scope :available, -> { where(available: true).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  # badges:string is a comma list ("signature,veg"); views render them as chips.
  def badges_list
    badges.to_s.split(",").map(&:strip).compact_blank
  end
end
