# frozen_string_literal: true

require 'yaml'

module Master
  # Central source for kernel axioms, philosophy, and workflow rules.
  # All data is loaded once (optionally from a custom root) and frozen
  # to guarantee immutability and fast repeated access.
  class Axioms
    DATA_PATH     = File.join(File.expand_path('../../..', __dir__), 'data', 'axioms.yml').freeze
    WORKFLOW_PATH = File.join(File.expand_path('../../..', __dir__), 'data', 'workflow.yml').freeze

    def initialize(root: nil)
      @axioms_path   = root ? File.join(root, 'data', 'axioms.yml')   : DATA_PATH
      @workflow_path = root ? File.join(root, 'data', 'workflow.yml') : WORKFLOW_PATH
      @data          = load_yaml(@axioms_path)   || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    # Public API ---------------------------------------------------------

    def kernel
      @kernel ||= (@data['kernel'] || {}).freeze
    end

    def workflow
      @workflow.freeze
    end

    # Returns philosophy items sorted by ascending priority.
    # If +limit+ is provided, only that many items are returned.
    def philosophy(limit: nil)
      @philosophy ||= begin
        items = (@data.dig('philosophy', 'prioritized_top_25') || [])
        items
          .map { |h| h.transform_keys(&:to_s) }
          .sort_by { |h| h['priority'].to_i }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    # Formatted blocks for display (e.g. in prompts) --------------------

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Axioms (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?

      top = items.map { |a| "  #{a['id']}: #{a['statement']}" }.join("\n")
      "## Core Philosophy (top #{items.size})\n#{top}"
    end

    # Workflow rule lookup ------------------------------------------------

    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    # General lookup -------------------------------------------------------

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] ||
        philosophy.find { |a| a['id'] == id_str }&.dig('statement')
    end

    def empty?
      @data.empty?
    end

    # ---------------------------------------------------------------------

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true)
    rescue StandardError
      nil
    end
  end
end