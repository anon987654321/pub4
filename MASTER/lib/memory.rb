# frozen_string_literal: true

require "yaml"

module Master
  class Memory
    STORE_FILE = "memory.yml"

    def initialize(root:)
      @root = root
    end

    def remember(key, value)
      store = load_store
      store[key.to_s] = value
      File.write(store_path, store.to_yaml)
    end

    def recall(key)
      load_store[key.to_s]
    end

    def context_summary
      store = load_store
      return nil if store.empty?
      store.map { |k, v| "#{k}: #{v}" }.join(", ")
    end

    private

    def store_path
      File.join(@root, STORE_FILE)
    end

    def load_store
      return {} unless File.exist?(store_path)
      YAML.safe_load_file(store_path) || {}
    rescue Psych::Exception
      {}
    end
  end
end
