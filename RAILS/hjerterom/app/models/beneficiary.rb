# frozen_string_literal: true

class Beneficiary < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  include Shared::GeoLocatable
  has_many :boxes, dependent: :nullify
  has_many :food_items, dependent: :nullify

  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :priority_first, -> { order(priority: :desc, updated_at: :asc) }

  def household_label
    people = household_size.to_i.positive? ? "#{household_size} people" : "household size unknown"
    [ name, people, area.presence ].compact.join(" · ")
  end

  def dietary_restriction_list
    raw = dietary_restrictions.to_s
    return [] if raw.blank?

    parsed = JSON.parse(raw)
    Array(parsed).map(&:to_s).reject(&:blank?)
  rescue JSON::ParserError
    raw.split(/[,;]/).map(&:strip).reject(&:blank?)
  end
end
