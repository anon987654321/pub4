# frozen_string_literal: true

class Beneficiary < ApplicationRecord
  has_many :boxes, dependent: :nullify

  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :priority_first, -> { order(priority: :desc, updated_at: :asc) }

  def household_label
    people = household_size.to_i.positive? ? "#{household_size} people" : "household size unknown"
    [name, people, area.presence].compact.join(" · ")
  end

  def preferred_category_list
    preferred_categories.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
