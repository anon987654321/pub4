# frozen_string_literal: true

class PlannedOutfit < ApplicationRecord
  belongs_to :user
  belongs_to :outfit

  validates :planned_date, presence: true
  validates :planned_date, uniqueness: { scope: :user_id }

  scope :upcoming, -> { where("planned_date >= ?", Date.current).order(:planned_date) }
  scope :this_week, -> { where(planned_date: Date.today..7.days.from_now) }

  after_commit :broadcast_live_refresh

  private

  def broadcast_live_refresh
    broadcast_refresh_to "planned_outfits"
    broadcast_refresh_to self
  end
end
