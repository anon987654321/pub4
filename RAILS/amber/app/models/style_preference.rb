# frozen_string_literal: true

class StylePreference < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :weight, numericality: true

  enum :kind, {
    aesthetic: "aesthetic",
    color: "color",
    fit: "fit",
    material: "material",
    occasion: "occasion",
    avoid: "avoid",
  }, default: :aesthetic
end
