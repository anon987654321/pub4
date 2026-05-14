# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  module Reach
  class SemanticCache
    MAX_ENTRIES = 1000
    DEFAULT_TTL = 3600
    BYTES_PER_KB = 1024.0

    def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
      @root = File.join(root, ".master", "cache")
      @ttl  = ttl
      @bus  = event_bus
      @lru  = []
      @lock = Monitor.new
      FileUtils.mkdir_p(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        hit = read_entry(path)
        if hit
          @bus&.publish("cache:hit", key:)
          return restore_value(hit)
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
        Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT }
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum { |f| File.exist?(f) ? File.size(f) : 0 }
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
      end
    end

    private

    def cache_key(prompt, model) = Digest::SHA256.hexdigest("#{prompt}::#{model}")
    def cache_path(key) = File.join(@root, "#{key}.json")

    def stale?(entry) = Time.now.to_i - entry.fetch(:ts, 0).to_i > @ttl

    def expire_entry!(path)
      @lru.delete(path)
      File.delete(path) rescue Errno::ENOENT
      nil
    end

    def drop_entry!(path)
      File.delete(path) rescue Errno::ENOENT
      @lru.delete(path)
      nil
    end

    def read_entry(path)
      return unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      return expire_entry!(path) if stale?(entry)
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError => e
      Master::Ground::Swallow.log(e, context: "semantic_cache.read_entry", event_bus: @bus, path:)
      drop_entry!(path)
    end

    def write_entry(path, value, key)
      payload = serialize_value(value)
      evict_lru while @lru.size >= MAX_ENTRIES
      File.write(path, JSON.generate({ ts: Time.now.to_i, value: payload }))
      promote_lru(path)
      @bus&.publish("cache:write", key:)
    end

    def serialize_value(value)
      if defined?(Master::Result::Ok) && value.is_a?(Master::Result::Ok)
        { __master_result: "ok", value: value.value! }
      elsif defined?(Master::Result::Err) && value.is_a?(Master::Result::Err)
        { __master_result: "err", message: value.message, category: value.category }
      else
        { __master_result: "raw", value: value }
      end
    end

    def restore_value(payload)
      return payload unless payload.is_a?(Hash)
      case payload[:__master_result] || payload["__master_result"]
      when "ok"  then Result.ok(payload[:value] || payload["value"])
      when "err" then Result.err(payload[:message] || payload["message"], category: payload[:category] || payload["category"])
      when "raw" then payload[:value] || payload["value"]
      else payload
      end
    end

    def promote_lru(path)
      @lru.delete(path)
      @lru.push(path)
    end

    def evict_lru
      oldest = @lru.shift
      return unless oldest && File.exist?(oldest)
      File.delete(oldest) rescue Errno::ENOENT
    end
  end
  end
end
