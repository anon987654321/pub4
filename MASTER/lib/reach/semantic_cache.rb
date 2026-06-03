# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "monitor"
require "yaml"

module Master
  module Reach
    class SemanticCache
      MAX_ENTRIES = 1000
      DEFAULT_TTL = 300
      BYTES_PER_KB = 1024.0

      def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
        @root = File.join(root, ".master", "cache")
        @manifest_path = File.join(root, ".master", "llm_cache.yml")
        @ttl = ttl.to_i.positive? ? ttl.to_i : DEFAULT_TTL
        @bus = event_bus
        @lru = []
        @lock = Monitor.new
        FileUtils.mkdir_p(@root)
        FileUtils.mkdir_p(File.dirname(@manifest_path))
      end

      def fetch(prompt, model, &blk)
        key = cache_key(prompt, model)
        path = cache_path(key)

        @lock.synchronize do
          hit = read_entry(path, key)
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
        @lock.synchronize do
          File.delete(path) if File.exist?(path)
          update_manifest { |manifest| manifest.delete(cache_key(prompt, model)) }
        end
      end

      def invalidate_all!
        @lock.synchronize do
          Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT }
          File.delete(@manifest_path) if File.exist?(@manifest_path)
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

      def expire_entry!(path, key = nil)
        @lru.delete(path)
        File.delete(path) rescue nil
        update_manifest { |manifest| manifest.delete(key) } if key
        nil
      end

      def drop_entry!(path)
        File.delete(path) rescue nil
        @lru.delete(path)
        nil
      end

      def read_entry(path, key)
        entry = read_json_entry(path) || read_manifest_entry(key)
        return unless entry
        return expire_entry!(path, key) if stale?(entry)
        promote_lru(path)
        entry[:value]
      end

      def read_json_entry(path)
        return unless File.exist?(path)
        JSON.parse(File.read(path), symbolize_names: true)
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.read_entry", event_bus: @bus, path:)
        drop_entry!(path)
      end

      def read_manifest_entry(key)
        entry = read_manifest[key]
        return unless entry.is_a?(Hash)

        entry.transform_keys(&:to_sym)
      end

      def write_entry(path, value, key)
        payload = serialize_value(value)
        evict_lru while @lru.size >= MAX_ENTRIES
        entry = { ts: Time.now.to_i, value: payload }
        File.write(path, JSON.generate(entry))
        update_manifest { |manifest| manifest[key] = entry }
        promote_lru(path)
        @bus&.publish("cache:write", key:, ttl: @ttl, path: @manifest_path)
      end

      def read_manifest
        return {} unless File.exist?(@manifest_path)
        YAML.safe_load_file(@manifest_path, permitted_classes: [Symbol], aliases: false) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.read_manifest", event_bus: @bus, path: @manifest_path)
        {}
      end

      def update_manifest
        manifest = read_manifest
        yield manifest
        manifest = manifest.sort_by { |_, entry| -entry_timestamp(entry) }.first(MAX_ENTRIES).to_h
        File.write(@manifest_path, manifest.to_yaml)
      end

      def entry_timestamp(entry)
        return 0 unless entry.is_a?(Hash)

        (entry[:ts] || entry["ts"] || 0).to_i
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
