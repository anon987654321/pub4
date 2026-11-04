# frozen_string_literal: true

class Dependency < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :port
  belongs_to :depends_on, class_name: "Port"

  TYPES = %w[build run test lib].freeze
  MAX_GRAPH_DEPTH = 6
  MAX_GRAPH_NODES = 60

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
        param: child_port&.to_param,
        children: child_port ? tree_for(child_port, seen:, depth: depth + 1) : []
      }
    end
  end

  # Return a bounded graph of facts already present in the local index.
  # The text tree remains the accessible source of truth; this is its compact
  # visual counterpart, not a replacement or an independent data importer.
  def self.graph_for(port)
    root = {
      id: port.id,
      name: port.name,
      pkgpath: port.pkgpath,
      version: port.version,
      depth: 0
    }
    nodes = { port.id => root }
    edges = []
    frontier = [port]
    depth = 0
    truncated = false

    while frontier.any?
      if depth >= MAX_GRAPH_DEPTH
        truncated ||= where(port_id: frontier.map(&:id)).exists?
        break
      end

      next_frontier = []
      includes(:depends_on).where(port_id: frontier.map(&:id)).order(:port_id, :id).each do |dependency|
        child = dependency.depends_on
        next unless child

        unless nodes.key?(child.id)
          if nodes.size >= MAX_GRAPH_NODES
            truncated = true
            next
          end

          nodes[child.id] = {
            id: child.id,
            name: child.name,
            pkgpath: child.pkgpath,
            version: child.version,
            depth: depth + 1
          }
          next_frontier << child
        end

        edges << {
          id: dependency.id,
          from: dependency.port_id,
          to: child.id,
          type: dependency.dep_type.presence || "run"
        }
      end

      frontier = next_frontier
      depth += 1
    end

    { nodes: nodes.values, edges:, truncated: }
  end
end
