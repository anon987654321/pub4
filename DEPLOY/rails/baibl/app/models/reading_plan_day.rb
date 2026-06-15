# frozen_string_literal: true

class ReadingPlanDay < ApplicationRecord
  belongs_to :reading_plan
  belongs_to :book

  validates :day_number, presence: true
  validates :day_number, uniqueness: { scope: :reading_plan_id }

  scope :ordered, -> { order(:day_number) }
  scope :due_today, -> { ordered.where(completed_at: nil).limit(1) }

  def completed? = completed_at.present?

  def reading_reference
    return "#{book.name} #{chapter_start}" if book && chapter_start == chapter_end
    return "#{book.name} #{chapter_start}-#{chapter_end}" if book

    "Day #{day_number}"
  end

  def scheduled_on
    reading_plan.created_at.to_date + (day_number - 1).days
  end
end
