# frozen_string_literal: true

class Dependency < ApplicationRecord
  belongs_to :port
  belongs_to :depends_on, class_name: "Port"

  TYPES = %w[build run test lib].freeze

  validates :dep_type, inclusion: { in: TYPES }, allow_nil: true
  validates :port_id, uniqueness: { scope: %i[depends_on_id dep_type] }
end
