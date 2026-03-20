# frozen_string_literal: true

require 'yaml'

module Master
  # Loads kernel rules and philosophy from data/axioms.yml.
  # Single source of truth: personality, scan, and LLM prompts all draw from here.
  class Axioms
    DATA_PATH = File.join(File.expand_path('../../..', __dir__), 'data', 'axioms.yml').freeze

    def initialize(root: nil)
      path  = root ? File.join(root, 'data', 'axioms.yml') : DATA_PATH
      @data = File.exist?(path) ? YAML.safe_load_file(path) : {}
    rescue StandardError
      @data = {}
    end

    def kernel = @data.fetch('kernel', {})

    # Philosophy items sorted ascending by priority number (1 = highest priority).
    def philosophy(limit: nil)
      items = (@data.dig('philosophy', 'prioritized_top_25') || [])
              .sort_by { |a| a['priority'].to_i }
      limit ? items.first(limit) : items
    end

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Axioms (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit:)
      return nil if items.empty?

      top = items.map { |a| "  #{a['id']}: #{a['statement']}" }.join("\n")
      "## Core Philosophy (top #{items.size})\n#{top}"
    end

    def lookup(id)
      kernel[id.to_s] ||
        philosophy.find { |a| a['id'] == id.to_s }&.dig('statement')
    end

    def empty? = @data.empty?
  end
end
