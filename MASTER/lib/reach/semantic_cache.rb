# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  module Reach
    class SemanticCache
      MAX_ENTRIES = 1000
      DEFAULT_TTL = 300
      BYTES_PER_KB = 1024.0
      INDEX_PATH = "llm_cache.yml".freeze

      def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
        @project_root = root
        @root = File.join(root, ".master", "cache")
        @index_path = File.join(root, ".master", INDEX_PATH)
        @ttl = ttl.to_i.positive? ? ttl.to_i : DEFAULT_TTL
        @bus = event_bus
        @lru = []
        @lock = Monitor.new
        FileUtils.mkdir_p(@root)
        load_index!
      end

      def fetch(prompt, model, &blk)
        key = cache_key(prompt, model)
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
        File.delete(path) rescue nil
        prune_index_for(path)
        nil
      end

      def drop_entry!(path)
        File.delete(path) rescue nil
        @lru.delete(path)
        prune_index_for(path)
        nil
      end

      def prune_index_for(path)
        return unless File.exist?(@index_path)
        rows = Master.load_yaml(@index_path) || {}
        rows.reject! { |_, entry| (entry["path"] || entry[:path]) == path }
        File.write(@index_path, rows.to_yaml)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.prune_index_for", event_bus: @bus)
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
        ts = Time.now.to_i
        File.write(path, JSON.generate({ ts:, value: payload }))
        promote_lru(path)
        persist_index!(key, path, ts)
        @bus&.publish("cache:write", key:)
      end

      def load_index!
        return unless File.exist?(@index_path)
        rows = Master.load_yaml(@index_path) || {}
        rows.each_value do |entry|
          path = entry["path"] || entry[:path]
          next unless path && File.exist?(path)
          promote_lru(path)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.load_index!", event_bus: @bus)
      end

      def persist_index!(key, path, ts)
        rows = File.exist?(@index_path) ? (Master.load_yaml(@index_path) || {}) : {}
        rows[key] = { "ts" => ts, "path" => path }
        FileUtils.mkdir_p(File.dirname(@index_path))
        File.write(@index_path, rows.to_yaml)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.persist_index!", event_bus: @bus)
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
        kind = payload.fetch(:__master_result) { payload["__master_result"] }
        value = payload.fetch(:value) { payload["value"] }
        message = payload.fetch(:message) { payload["message"] }
        cat = payload.fetch(:category) { payload["category"] }
        category = cat.to_s.empty? ? :unknown : cat.to_sym
        category = :unknown unless Master::Result::CATEGORIES.key?(category)
        case kind
        when "ok" then Result.ok(value)
        when "err" then Result.err(message, category: category)
        when "raw" then value
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
        File.delete(oldest) rescue nil
      end
    end
  end
end
