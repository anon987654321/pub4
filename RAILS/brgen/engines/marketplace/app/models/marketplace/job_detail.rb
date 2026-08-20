# frozen_string_literal: true

# What a job advert carries that a bicycle does not.
class Marketplace::JobDetail < ApplicationRecord
  EMPLOYMENT_TYPES = %w[full_time part_time contract seasonal internship].freeze

  belongs_to :listing, class_name: "Marketplace::Listing"

  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }, allow_blank: true
  validates :employer, length: { maximum: 120 }
  validates :salary_min_cents, :salary_max_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :range_reads_forwards

  def salary_display
    return nil if salary_min_cents.blank? && salary_max_cents.blank?
    return Shared::MoneyDisplay.format(salary_min_cents) if salary_max_cents.blank?
    return Shared::MoneyDisplay.format(salary_max_cents) if salary_min_cents.blank?

    "#{Shared::MoneyDisplay.format(salary_min_cents)}–#{Shared::MoneyDisplay.format(salary_max_cents)}"
  end

  private

  # An advert that says nothing about pay is normal and stays sayable. What is
  # not sayable is a range running backwards, which reads as a typo nobody can
  # act on.
  def range_reads_forwards
    return if salary_min_cents.blank? || salary_max_cents.blank?
    return if salary_max_cents >= salary_min_cents

    errors.add(:salary_max_cents, :below_minimum)
  end
end
