# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  class SemanticCache
    MAX_ENTRIES = 1000

    def initialize(root:, ttl: 3600, event_bus: nil)
      @root    = File.join(root, ".master", "cache")
      @ttl     = ttl
      @bus     = event_bus
      @lru     = []
      @lock    = Monitor.new
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        if (hit = read_entry(path))
          @bus&.publish("cache:hit", key:)
          return hit
        end
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      @lock.synchronize { write_entry(path, result, key) }
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      @lock.synchronize { File.delete(path) if File.exist?(path) }
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue nil }
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum { |f| File.size(f) rescue 0 }
        { entries: files.size, size_kb: (bytes / 1024.0).round(1) }
      end
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
      File.delete(path) rescue nil
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
