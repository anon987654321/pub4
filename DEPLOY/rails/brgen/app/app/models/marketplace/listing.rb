class Marketplace::Listing < ApplicationRecord
  belongs_to :user
  belongs_to :category, class_name: "Marketplace::Category",
             foreign_key: :category_id, optional: true
  has_many :orders, class_name: "Marketplace::Order",
           foreign_key: :listing_id, dependent: :destroy
  has_many_attached :photos

  CONDITIONS = %w[new like_new good fair poor].freeze
  STATUSES   = %w[active sold reserved removed].freeze

  validates :title, presence: true, length: { maximum: 200 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :condition, inclusion: { in: CONDITIONS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  before_validation { self.status ||= "active"; self.currency ||= "NOK" }

  scope :active,   -> { where(status: "active") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :popular,  -> { order(views_count: :desc) }

  def price_display  = "#{price_cents / 100.0} #{currency}"
  def sold?          = status == "sold"
end
