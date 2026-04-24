# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  class SemanticCache
    MAX_ENTRIES = 1000
    DEFAULT_TTL = 3600
    BYTES_PER_KB = 1024.0

    def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
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
      @lock.synchronize do
        # Intentional deletion of cached entry
        File.delete(path) if File.exist?(path)
      end
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each do |f|
          begin
            # Intentional deletion of all cache files
            File.delete(f)
          rescue Errno::ENOENT
            # Ignore if file already removed
          end
        end
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum do |f|
          File.size(f)
        rescue Errno::ENOENT
          0
        end
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
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
        # Intentional deletion of expired cache file
        File.delete(path)
        return nil
      end
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      begin
        # Intentional deletion of corrupt cache file
        File.delete(path)
      rescue Errno::ENOENT
        # Ignore if already removed
      end
      @lru.delete(path)
      nil
    end

    def write_entry(path, value, key)
      # Unwrap Result objects for JSON serialization
      value = value.value! if value.respond_to?(:ok?) && value.ok?
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
      return unless oldest && File.exist?(oldest)
      # Intentional deletion of oldest cache file (LRU eviction)
      File.delete(oldest)
    end
  end
end
