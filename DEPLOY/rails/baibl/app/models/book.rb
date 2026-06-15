# frozen_string_literal: true

class Book < ApplicationRecord
  # Engine-ize
  include Shared.concern(:Reactable) rescue nil
  has_many :chapters, dependent: :destroy
  has_many :verses, dependent: :destroy

  TESTAMENTS = %w[Old New].freeze

  validates :name, :abbreviation, :testament, presence: true
  validates :testament, inclusion: { in: TESTAMENTS }
  validates :abbreviation, uniqueness: true

  scope :old_testament, -> { where(testament: "Old").order(:order_index) }
  scope :new_testament, -> { where(testament: "New").order(:order_index) }
  scope :ordered,       -> { order(:order_index) }
end
