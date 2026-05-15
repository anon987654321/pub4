class CalculateSustainabilityJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
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
    return nil unless item.price.present?
    wear_discount = [item.times_worn.to_i * 0.015, 0.75].min
    (item.price * (0.65 - wear_discount)).clamp(0, item.price).round(2)
  end

  def estimated_repair_cost(item)
    return nil unless item.price.present?
    (item.price * 0.12).round(2)
  end

  def environmental_score(item)
    worn = item.times_worn.to_i
    base = worn.positive? ? [worn * 4, 100].min : 5
    item.spark_joy? ? [base + 10, 100].min : base
  end
end
