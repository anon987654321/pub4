# frozen_string_literal: true

require 'yaml'

module Master
  class Axioms
    def self.data_file_path(filename)
      File.join(File.expand_path('../../..', __dir__), 'data', filename)
    end

    DATA_PATH     = self.data_file_path('axioms.yml').freeze
    WORKFLOW_PATH = self.data_file_path('workflow.yml').freeze

    def initialize(root: nil)
      axioms_path   = build_data_path('axioms.yml', root)
      workflow_path = build_data_path('workflow.yml', root)
      begin
        @data = load_yaml_safe(axioms_path)
        @workflow = load_yaml_safe(workflow_path)
      rescue StandardError
        @data = {}
        @workflow = {}
      end
    end

    def kernel   = @data.fetch('kernel', {})
    def workflow = @workflow

    def philosophy(limit: nil)
      items = (@data.dig('philosophy', 'prioritized_top_25') || [])
              .sort_by { |a| a['priority'].to_i }
      limit ? items.first(limit) : items
    end

    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    def lookup(id)
      kernel[id.to_s] ||
        philosophy.find { |a| a['id'] == id.to_s }&.dig('statement')
    end

    def empty? = @data.empty?

    def kernel_block
      block_for(:kernel)
    end

    def philosophy_block(limit: 5)
      block_for(:philosophy, limit: limit)
    end

    private

    def build_data_path(filename, root)
      root ? File.join(root, 'data', filename) : self.class.data_file_path(filename)
    end

    def load_yaml_safe(path)
      File.exist?(path) ? YAML.safe_load_file(path) : {}
    end

    def block_for(type, limit: nil)
      config = block_config(type, limit)
      return nil unless config
      header, collection, formatter = config
      build_block(header, collection, &formatter)
    end

    def block_config(type, limit)
      case type
      when :kernel
        [ "## Kernel Axioms (enforced)", kernel, ->(id, stmt) { "  #{id}: #{stmt}" } ]
      when :philosophy
        collection = philosophy(limit: limit)
        [ "## Core Philosophy (top #{collection.size})", collection, ->(a) { "  #{a['id']}: #{a['statement']}" } ]
      else
        nil
      end
    end

    def build_block(header, collection)
      return nil if collection.empty?
      body = collection.map { |*args| yield(*args) }.join("\n")
      "#{header}\n#{body}"
    end
  end
end