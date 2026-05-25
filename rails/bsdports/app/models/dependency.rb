# frozen_string_literal: true

class Dependency < ApplicationRecord
  self.table_name = "bsdports_dependencies"
  belongs_to :port
  belongs_to :depends_on, class_name: "Port"
  validates :dep_type, inclusion: { in: %w[run build test library] }
end
