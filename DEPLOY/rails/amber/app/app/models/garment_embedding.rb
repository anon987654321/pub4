class GarmentEmbedding < ApplicationRecord
  belongs_to :item

  validates :provider, :model, presence: true
  validates :dimensions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  serialize :vector, coder: JSON
  serialize :metadata, coder: JSON
end
