# frozen_string_literal: true

class BeneficiaryMatchingService
  def self.match_inventory
    new.match_inventory
  end

  def match_inventory
    beneficiaries = Beneficiary.active.priority_first
    items = FoodItem.where(box_id: nil).includes(:donation)

    beneficiaries.flat_map do |beneficiary|
      items.filter_map do |item|
        score = score_item(beneficiary, item)
        next if score < 40

        item.update!(match_score: score) if item.has_attribute?(:match_score)
        { beneficiary:, item:, score: }
      end.sort_by { |m| -m[:score] }.first(5)
    end.flatten
  end

  private

  def score_item(beneficiary, item)
    score = 50
    score += 20 if category_match?(beneficiary, item)
    score += 15 if beneficiary.household_size.to_i >= 4 && item.quantity.to_i >= 3
    score += 10 if item.best_before.present? && item.best_before > 2.days.from_now.to_date
    score -= 30 if dietary_conflict?(beneficiary, item)
    score
  end

  def category_match?(beneficiary, item)
    prefs = beneficiary.preferred_category_list
    return true if prefs.empty?

    prefs.include?(item.category.to_s)
  end

  def dietary_conflict?(beneficiary, item)
    needs = beneficiary.dietary_needs.to_s.downcase
    return false if needs.blank?

    needs.include?("gluten-free") && item.name.to_s.downcase.include?("bread")
  end
end