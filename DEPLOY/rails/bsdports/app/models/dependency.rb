# frozen_string_literal: true

class Dependency < ApplicationRecord
  belongs_to :port
  belongs_to :depends_on, class_name: "Port"

  TYPES = %w[build run test lib].freeze

  validates :dep_type, inclusion: { in: TYPES }, allow_nil: true
  validates :port_id, uniqueness: { scope: %i[depends_on_id dep_type] }

  scope :runtime, -> { where(dep_type: "run") }
  scope :buildtime, -> { where(dep_type: "build") }

  def label
    [dep_type.presence || "run", depends_on&.name].compact.join(": ")
  end
end
