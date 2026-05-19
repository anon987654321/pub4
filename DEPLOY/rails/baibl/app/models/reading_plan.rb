# frozen_string_literal: true

class ReadingPlan < ApplicationRecord
  belongs_to :user, optional: true
  has_many :reading_plan_days, dependent: :destroy

  validates :name, presence: true
  validates :duration_days, numericality: { greater_than: 0 }, allow_nil: true

  def progress
    return 0.0 if reading_plan_days.empty?
    reading_plan_days.where.not(completed_at: nil).count.to_f / reading_plan_days.count
  end
end
