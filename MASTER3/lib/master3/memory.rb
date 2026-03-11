# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master3
  # Persistent cross-session memory store.
  # Stored at .master3/memory.yml — survives restarts.
  class Memory
    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master3", "memory.yml")
      @store = load_store
    end

    def remember(key, value)
      @store[key.to_s] = { value: value.to_s, ts: Time.now.to_i }
      persist
    end

    # Keys are always stored and retrieved as strings.
    # Symbol fallback removed: YAML safe_load with symbolize_names: false guarantees
    # string keys, so a symbol lookup would never match and could mask missing entries.
    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @store.delete(key.to_s)
      persist
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Returns a compact string suitable for injection into system prompts.
    def context_summary
      return nil if @store.empty?
      lines = @store.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
      "Memory:\n#{lines.join("\n")}"
    end

    private

    def load_store
      return {} unless File.exist?(@path)
      YAML.safe_load_file(@path, symbolize_names: false) || {}
    rescue
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end
  end
end
