# frozen_string_literal: true

require "digest"
require "json"

module Master3
  class SemanticCache
    MAX_ENTRIES = 1000

    def initialize(root:, ttl: 3600, event_bus: nil)
      @root    = File.join(root, ".master3", "cache")
      @ttl     = ttl
      @bus     = event_bus
      @lru     = []
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      if (hit = read_entry(path))
        @bus&.publish("cache:hit", key:)
        return hit
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      write_entry(path, result, key)
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      File.delete(path) if File.exist?(path)
    end

    private

    def cache_key(prompt, model)
      Digest::SHA256.hexdigest("#{prompt}::#{model}")
    end

    def cache_path(key)
      File.join(@root, "#{key}.json")
    end

    def read_entry(path)
      return nil unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      if Time.now.to_i - entry[:ts] > @ttl
        @lru.delete(path)
        File.delete(path)
        return nil
      end
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      $stderr.puts "semantic_cache: corrupt entry at #{path}, deleting"
      File.delete(path)
      @lru.delete(path)
      nil
    end

    def write_entry(path, value, key)
      evict_lru while @lru.size >= MAX_ENTRIES
      File.write(path, JSON.generate({ ts: Time.now.to_i, value: }))
      @lru.push(path)
    end

    def promote_lru(path)
      @lru.delete(path)
      @lru.push(path)
    end

    def evict_lru
      oldest = @lru.shift
      File.delete(oldest) if oldest && File.exist?(oldest)
    end
  end
end
