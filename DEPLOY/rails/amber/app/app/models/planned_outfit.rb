class PlannedOutfit < ApplicationRecord
  belongs_to :user
  belongs_to :outfit

  validates :planned_date, presence: true
  validates :planned_date, uniqueness: { scope: :user_id }

  scope :upcoming, -> { where("planned_date >= ?", Date.today).order(:planned_date) }
  scope :this_week, -> { where(planned_date: Date.today..7.days.from_now) }
end
