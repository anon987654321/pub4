# frozen_string_literal: true

class SustainabilityMetric < ApplicationRecord
  belongs_to :item

  validates :resale_value, :repair_cost_estimate, :environmental_score,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def unused?
    item.times_worn.to_i.zero?
  end

  def cost_per_wear = item.cost_per_wear
end
