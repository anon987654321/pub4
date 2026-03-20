# frozen_string_literal: true

require 'yaml'

module Master
  # Loads kernel rules and philosophy from data/axioms.yml.
  # Also loads data/workflow.yml — operational norms for editing, scanning, and fixing.
  # Single source of truth: personality, scan, and LLM prompts all draw from here.
  class Axioms
    def self.data_file_path(filename)
      File.join(File.expand_path('../../..', __dir__), 'data', filename)
    end

    DATA_PATH     = self.data_file_path('axioms.yml').freeze
    WORKFLOW_PATH = self.data_file_path('workflow.yml').freeze

    def initialize(root: nil)
      axioms_path   = build_data_path('axioms.yml', root)
      workflow_path = build_data_path('workflow.yml', root)
      @data         = File.exist?(axioms_path)   ? YAML.safe_load_file(axioms_path)   : {}
      @workflow     = File.exist?(workflow_path) ? YAML.safe_load_file(workflow_path) : {}
    rescue StandardError
      @data     = {}
      @workflow = {}
    end

    def kernel   = @data.fetch('kernel', {})
    def workflow  = @workflow

    # Philosophy items sorted ascending by priority number (1 = highest priority).
    def philosophy(limit: nil)
      items = (@data.dig('philosophy', 'prioritized_top_25') || [])
              .sort_by { |a| a['priority'].to_i }
      limit ? items.first(limit) : items
    end

    def kernel_block
      build_block("## Kernel Axioms (enforced)", kernel) { |id, stmt| "  #{id}: #{stmt}" }
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit:)
      build_block("## Core Philosophy (top #{items.size})", items) { |a| "  #{a['id']}: #{a['statement']}" }
    end

    # Workflow rule lookup — e.g. axioms.workflow_rule("file_reading")
    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    def lookup(id)
      kernel[id.to_s] ||
        philosophy.find { |a| a['id'] == id.to_s }&.dig('statement')
    end

    def empty? = @data.empty?

    private

    def build_data_path(filename, root)
      root ? File.join(root, 'data', filename) : self.class.data_file_path(filename)
    end

    def build_block(header, collection)
      return nil if collection.empty?
      body = collection.map { |*args| yield(*args) }.join("\n")
      "#{header}\n#{body}"
    end
  end
end