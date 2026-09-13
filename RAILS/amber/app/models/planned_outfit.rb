# frozen_string_literal: true

class PlannedOutfit < ApplicationRecord
  belongs_to :user
  belongs_to :outfit

  validates :planned_date, presence: true
  validates :planned_date, uniqueness: { scope: :user_id }

  scope :upcoming, -> { where("planned_date >= ?", Date.current).order(:planned_date) }
  # Date.current is the Oslo day; Date.today is the server's, which is UTC on
  # vm23 and put the week one day behind between midnight and 02:00.
  scope :this_week, -> { where(planned_date: Date.current..(Date.current + 7)) }

  after_commit :broadcast_live_refresh

  private

  def broadcast_live_refresh
    broadcast_refresh_to "planned_outfits"
    broadcast_refresh_to self
  end
end
