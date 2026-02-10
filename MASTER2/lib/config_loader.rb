# frozen_string_literal: true

module MASTER
  # Shared YAML config loader with mtime-based caching
  # Eliminates duplicated YAML loading across modules
  module ConfigLoader
    def self.load(path, symbolize: true, default: nil)
      @cache ||= {}
      entry = @cache[path]
      
      unless File.exist?(path)
        return default
      end

      current_mtime = File.mtime(path)
      if entry && entry[:mtime] == current_mtime
        return entry[:data]
      end

      data = YAML.safe_load_file(path, symbolize_names: symbolize)
      @cache[path] = { data: data || default, mtime: current_mtime }
      data || default
    rescue StandardError => e
      $stderr.puts "MASTER: Failed to load #{path}: #{e.message}" if ENV["MASTER_DEBUG"]
      default
    end

    def self.invalidate(path = nil)
      if path
        @cache&.delete(path)
      else
        @cache = {}
      end
    end
  end
end
