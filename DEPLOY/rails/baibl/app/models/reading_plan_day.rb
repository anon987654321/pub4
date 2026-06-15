# frozen_string_literal: true

class ReadingPlanDay < ApplicationRecord
  belongs_to :reading_plan
  belongs_to :book

  validates :day_number, presence: true
  validates :day_number, uniqueness: { scope: :reading_plan_id }

  scope :ordered, -> { order(:day_number) }

  def completed? = completed_at.present?
end
