# frozen_string_literal: true

class Dependency < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :port
  belongs_to :depends_on, class_name: "Port"

  TYPES = %w[build run test lib].freeze

  validates :dep_type, inclusion: { in: TYPES }, allow_nil: true
  validates :port_id, uniqueness: { scope: %i[depends_on_id dep_type] }

  scope :runtime, -> { where(dep_type: "run") }
  scope :buildtime, -> { where(dep_type: "build") }

  def label
    [ dep_type.presence || "run", depends_on&.name ].compact.join(": ")
  end

  def self.tree_for(port, seen: Set.new, depth: 0)
    return [] if depth > 6 || seen.include?(port.id)

    seen = seen.dup.add(port.id)
    includes(:depends_on).where(port: port).map do |dependency|
      child_port = dependency.depends_on
      {
        id: dependency.id,
        label: dependency.label,
        pkgpath: child_port&.pkgpath,
        children: child_port ? tree_for(child_port, seen:, depth: depth + 1) : [],
      }
    end
  end
end
