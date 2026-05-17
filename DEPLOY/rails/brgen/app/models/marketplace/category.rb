class Marketplace::Category < ApplicationRecord
  belongs_to :parent, class_name: "Marketplace::Category", optional: true
  has_many :children, class_name: "Marketplace::Category", foreign_key: :parent_id, dependent: :nullify
  has_many :listings, class_name: "Marketplace::Listing", foreign_key: :category_id, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation { self.slug ||= name.to_s.parameterize }

  scope :roots, -> { where(parent_id: nil) }

  def to_param = slug
end
