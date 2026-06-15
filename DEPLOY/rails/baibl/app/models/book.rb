# frozen_string_literal: true

class Book < ApplicationRecord
  # Engine-ize
  include Shared.concern(:Reactable) rescue nil
  has_many :chapters, dependent: :destroy
  has_many :verses, dependent: :destroy

  TRADITIONS = %w[bible quran gita other].freeze

  validates :name, :abbreviation, presence: true
  validates :tradition, inclusion: { in: TRADITIONS }, allow_nil: true
  validates :abbreviation, uniqueness: true

  scope :by_tradition, ->(t) { where(tradition: t).order(:order_index) }
  scope :bible,        -> { by_tradition("bible") }
  scope :quran,        -> { by_tradition("quran") }
  scope :gita,         -> { by_tradition("gita") }
  scope :ordered,      -> { order(:order_index) }
end
