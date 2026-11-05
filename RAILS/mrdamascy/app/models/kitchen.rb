# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :menu_categories, dependent: :destroy
  has_many :menu_items, through: :menu_categories
  has_many :orders, dependent: :destroy

  # weekly_hours keys, in Date#wday order. A day the hash leaves out is closed.
  DAYS = %w[sun mon tue wed thu fri sat].freeze
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d\z/

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :weekly_hours_are_open_close_pairs

  # The hours in the reader's language; Norwegian is the kitchen's own wording
  # and the fallback when no English one is set.
  def localized_opening_hours
    (I18n.locale == :en && opening_hours_en.presence) || opening_hours
  end

  # Checkout follows the hours only once they are set; empty hours (the
  # default) leave ordering unlimited by the clock, as before.
  def hours_set?
    weekly_hours.present?
  end

  def open_at?(time)
    return true unless hours_set?

    opens, closes = slot_for(time.to_date)
    opens.present? && time >= opens && time < closes
  end

  # The next moment the kitchen opens after time, within a week; nil when no
  # day of the week has hours.
  def next_opening(time)
    openings = (0..7).filter_map { |ahead| slot_for(time.to_date + ahead).first }
    openings.find { |opens| opens > time }
  end

  private

  def slot_for(date)
    open_close = weekly_hours.to_h[DAYS[date.wday]]
    return [] unless open_close

    zone = Time.zone
    open_close.map { |clock| zone.parse("#{date.iso8601} #{clock}") }
  end

  def weekly_hours_are_open_close_pairs
    return if weekly_hours.blank?

    valid = weekly_hours.is_a?(Hash) && weekly_hours.all? do |day, pair|
      DAYS.include?(day) && pair.is_a?(Array) && pair.size == 2 && pair.all? { |clock| CLOCK.match?(clock.to_s) } &&
        pair.first < pair.last
    end
    errors.add(:weekly_hours, :invalid) unless valid
  end
end
