# frozen_string_literal: true

require "yaml"
require_relative "measure"

module Master
  module Convergence
    module Architecture
      module_function

      def render(root: Master::REPO_ROOT, target: "")
        inventory = Measure.inventory(root:)
        rows = if target.to_s.empty?
          inventory[:trees]
        else
          inventory[:trees].slice(target.to_s.upcase)
        end
        return "explain: unknown tree #{target}" if rows.empty?

        lines = [
          "architecture: #{target.to_s.empty? ? "PUB4" : target.to_s.upcase}",
          "architecture: four-tree boundary MASTER / RAILS / OPENBSD / STUDIO",
        ]
        rows.each do |name, row|
          largest = row[:largest].first(3).map { |entry| "#{entry[:path]}(#{entry[:bytes]})" }.join(", ")
          lines << "architecture: #{name} files=#{row[:files]} bytes=#{row[:bytes]} ruby_lines=#{row[:ruby_lines]}"
          lines << "architecture: #{name} largest=#{largest}"
        end

        ownership = File.join(root, "MASTER", "PATH_OWNERSHIP.yml")
        if File.file?(ownership)
          data = YAML.safe_load_file(ownership, aliases: false)
          owners = Array(data["paths"] || data["ownership"]).size
          lines << "architecture: ownership_registry_entries=#{owners}" if owners.positive?
        end
        lines.join("\n")
      rescue StandardError => e
        "explain0: inconclusive — #{e.class}: #{e.message}"
      end
    end
  end
end
