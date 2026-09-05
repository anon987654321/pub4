# frozen_string_literal: true

class Marketplace::Category < ApplicationRecord
  # Engine-ize
  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :parent, class_name: "Marketplace::Category", optional: true
  has_many :children, class_name: "Marketplace::Category", foreign_key: :parent_id, dependent: :nullify,
           inverse_of: :parent
  has_many :listings, class_name: "Marketplace::Listing", foreign_key: :category_id, dependent: :nullify,
           inverse_of: :category

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation { self.slug ||= name.to_s.parameterize }

  scope :roots, -> { where(parent_id: nil) }

  def to_param = slug
end
