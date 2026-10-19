# frozen_string_literal: true

class SustainabilityMetric < ApplicationRecord
  include MoneyInOre
  money_reader :resale_value
  money_reader :repair_cost_estimate

  belongs_to :item

  validates :resale_value_cents, :repair_cost_estimate_cents, :environmental_score,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def unused?
    item.times_worn.to_i.zero?
  end

  def cost_per_wear = item.cost_per_wear
end
