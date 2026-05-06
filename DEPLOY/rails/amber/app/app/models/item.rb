class Item < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :outfits, through: :outfit_items
  has_many_attached :photos

  validates :title, :category, presence: true
  validates :times_worn, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :joy,          -> { where(spark_joy: true) }
  scope :by_category,  ->(c) { where(category: c) }
  scope :by_mood,      ->(m) { where(mood_effect: m) }
  scope :by_occasion,  ->(o) { where("occasion_tags LIKE ?", "%#{o}%") }
  scope :current_self, -> { where(life_phase: "current") }
  scope :recent,       -> { order(created_at: :desc) }
  scope :worn_most,    -> { order(times_worn: :desc) }
  scope :never_worn,   -> { where("times_worn = 0 OR times_worn IS NULL") }
  scope :aging_unworn, -> { never_worn.where("purchase_date < ?", 6.months.ago) }

  CATEGORIES   = %w[Tops Bottoms Dresses Shoes Accessories Outerwear].freeze
  SEASONS      = %w[Spring Summer Autumn Winter All-Season].freeze
  MOOD_EFFECTS = %w[energising calming confident playful neutral].freeze
  LIFE_PHASES  = %w[current past-self aspirational].freeze
  OCCASIONS    = %w[work casual formal gym date travel].freeze

  def cost_per_wear
    return nil unless price.present? && times_worn.to_i > 0
    (price / times_worn).round(2)
  end

  def occasions
    occasion_tags.to_s.split(",").map(&:strip)
  end

  def wear!
    increment!(:times_worn)
    touch
  end
end
