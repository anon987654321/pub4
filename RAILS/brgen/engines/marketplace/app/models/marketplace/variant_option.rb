# frozen_string_literal: true

# What makes a variant different: name is the axis (Størrelse), value is the
# point on it (M). A row rather than a column, so a listing can vary along two
# axes without the schema knowing which two.
class Marketplace::VariantOption < ApplicationRecord
  belongs_to :variant, class_name: "Marketplace::Variant", inverse_of: :options

  validates :name, presence: true, length: { maximum: 40 }
  validates :value, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: :variant_id }
end
