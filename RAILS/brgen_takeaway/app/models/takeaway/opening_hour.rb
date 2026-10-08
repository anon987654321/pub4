# frozen_string_literal: true

module Takeaway
  # When a kitchen is open.
  #
  # A row per weekday rather than a JSON blob, because "is this open now" is a
  # query — a blob turns the restaurant list into a Ruby loop over every row on
  # the page.
  #
  # Minutes past midnight rather than a time, because a Time carries a date and
  # a zone that mean nothing here, and because closing after midnight is normal
  # for a kitchen: closes_minute may exceed 1440 and that is how a place open
  # until 02:00 is expressed.
  class OpeningHour < ApplicationRecord
    self.table_name = "takeaway_opening_hours"

    DAY_MINUTES = 24 * 60

    belongs_to :restaurant, class_name: "Takeaway::Restaurant"

    validates :weekday, inclusion: { in: 0..6 }
    validates :opens_minute, numericality: { greater_than_or_equal_to: 0, less_than: DAY_MINUTES }
    validates :closes_minute, numericality: { greater_than: 0, less_than_or_equal_to: DAY_MINUTES * 2 }
    validate :closes_after_it_opens

    scope :for_weekday, ->(wday) { where(weekday: wday) }

    def self.open_at?(restaurant_id, moment = Time.current)
      minute = moment.hour * 60 + moment.min

      # Today's window, plus yesterday's window if it runs past midnight — a
      # place open until 02:00 is open at 00:30, and reading only today's row
      # says it is shut.
      today = where(restaurant_id: restaurant_id, weekday: moment.wday)
              .where(opens_minute: ..minute).where(closes_minute: (minute + 1)..)
      yesterday = where(restaurant_id: restaurant_id, weekday: (moment.wday - 1) % 7)
                  .where(closes_minute: (minute + DAY_MINUTES + 1)..)

      today.exists? || yesterday.exists?
    end

    def to_s
      "#{format_minute(opens_minute)}–#{format_minute(closes_minute % DAY_MINUTES)}"
    end

    private

    def format_minute(minute)
      format("%02d:%02d", (minute / 60) % 24, minute % 60)
    end

    def closes_after_it_opens
      return if opens_minute.blank? || closes_minute.blank?
      return if closes_minute > opens_minute

      errors.add(:closes_minute, :before_open)
    end
  end
end
