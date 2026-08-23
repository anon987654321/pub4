# frozen_string_literal: true

class CalculateSustainabilityJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    # Preloaded, not bare: ApplicationRecord sets strict_loading_by_default in
    # every environment, so reading the association off a plain find raised
    # StrictLoadingViolationError on every run of this job — and a job has no
    # request spec to notice.
    item = Item.includes(:sustainability_metric).find(item_id)
    metric = item.sustainability_metric || item.build_sustainability_metric
    metric.assign_attributes(
      resale_value: estimated_resale_value(item),
      repair_cost_estimate: estimated_repair_cost(item),
      environmental_score: environmental_score(item)
    )
    metric.save!
  end

  private

  def estimated_resale_value(item)
    return nil unless item.price_cents.present?

    price = item.price_cents / 100.0
    wear_discount = [ item.times_worn.to_i * 0.015, 0.75 ].min
    (price * (0.65 - wear_discount)).clamp(0, price).round(2)
  end

  def estimated_repair_cost(item)
    return nil unless item.price_cents.present?

    (item.price_cents / 100.0 * 0.12).round(2)
  end

  def environmental_score(item)
    worn = item.times_worn.to_i
    base = worn.positive? ? [ worn * 4, 100 ].min : 5
    item.spark_joy? ? [ base + 10, 100 ].min : base
  end
end
