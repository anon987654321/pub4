# frozen_string_literal: true

class ItemOption < ApplicationRecord
  include LocalizedColumns

  KINDS = %w[sauce topping extra].freeze

  belongs_to :menu_item

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :price_ore, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }
  scope :of_kind, ->(kind) { where(kind: kind).ordered }
end
