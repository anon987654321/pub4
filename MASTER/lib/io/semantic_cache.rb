# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "monitor"
require "yaml"
require_relative "semantic_index"

module Master
  module Io
    class SemanticCache
      MAX_ENTRIES = 1000
      DEFAULT_TTL = 300
      BYTES_PER_KB = 1024.0

      def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
        @master_root = File.join(root, ".master")
        @root = File.join(@master_root, "cache")
        @manifest_path = File.join(@master_root, "llm_cache.yml")
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

        exact = exact_cache_hit(path, key)
        return exact if exact

        near = fuzzy_cache_hit(prompt, key)
        return near if near

        @bus&.publish("cache:miss", key:)
        result = blk.call
        store_result(prompt, result, path:, key:)
        result
      end

      def exact_cache_hit(path, key)
        @lock.synchronize do
          hit = read_entry(path)
          next nil unless hit

          @bus&.publish("cache:hit", key:)
          restore_value(hit)
        end
      end

      def fuzzy_cache_hit(prompt, key)
        near = fuzzy_index.nearest(prompt)
        return unless near

        @bus&.publish("cache:fuzzy_hit", key:)
        near
      end

      def store_result(prompt, result, path:, key:)
        return unless cacheable_result?(result)

        fuzzy_index.remember(prompt, result)
        @lock.synchronize { write_entry(path:, value: result, key:) }
      end

      # Fuzzy near-hit layer over the exact disk cache; no-op with embeddings off.
      def fuzzy_index
        @fuzzy_index ||= SemanticIndex.new(embedder: Master::Review::Embeddings)
      end

      def invalidate!(prompt, model)
        key = cache_key(prompt, model)
        path = cache_path(key)
        @lock.synchronize do
          File.delete(path) if File.exist?(path)
          delete_manifest_entry(key)
        end
      end

      def invalidate_all!
        @lock.synchronize do
          Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT } # scan: intentional — clearing this cache is the method's whole job
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

      TRANSIENT_ERROR_CATEGORIES = %i[timeout no_api_key rate_limit].freeze

      private

      def cacheable_result?(result)
        return false if phantom?(result)
        return true unless defined?(Master::Result::Err) && result.is_a?(Master::Result::Err)

        !TRANSIENT_ERROR_CATEGORIES.include?(result.category)
      end

      # A response the phantom guard rejects must not be stored, because storing
      # it makes the rejection the permanent answer to that prompt. The guard
      # runs after this cache returns, so a degenerate response is served again
      # on the next identical question, trips the same detector again, and the
      # ladder in PhantomRecovery — which counts consecutive phantoms — climbs
      # to a halt with no clean response in between to reset it. Measured on
      # vm23: the same question halted on the second and third ask while the
      # first, on a cache miss, answered correctly.
      #
      # Only a positively identified degenerate string refuses the cache.
      # Anything this cannot read as text is stored as before, so an unfamiliar
      # result shape loses caching rather than silently skipping it.
      def phantom?(result)
        return false unless defined?(Master::PhantomRecovery)

        text = cacheable_text(result)
        return false if text.nil? || text.empty?

        # bus: nil by default, so probing here publishes no phantom:detected.
        !Master::PhantomRecovery.detect(text).nil?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Io::SemanticCache.phantom?") if defined?(Master::Ground::Swallow)
        false
      end

      def cacheable_text(result)
        value = result.respond_to?(:value) ? result.value : result
        case value
        when String then value
        when Hash then value[:rendered].is_a?(String) ? value[:rendered] : nil
        end
      end

      def cache_key(prompt, model) = Digest::SHA256.hexdigest("#{prompt}::#{model}")
      def cache_path(key) = File.join(@root, "#{key}.json")

      def stale?(entry) = Time.now.to_i - entry.fetch(:ts, 0).to_i > @ttl

      def expire_entry!(path)
        @lru.delete(path)
        File.delete(path) rescue nil
        delete_manifest_entry(File.basename(path, ".json"))
        nil
      end

      def drop_entry!(path)
        File.delete(path) rescue nil
        @lru.delete(path)
        delete_manifest_entry(File.basename(path, ".json"))
        nil
      end

      def read_entry(path)
        return unless File.exist?(path) || manifest_entry(File.basename(path, ".json"))
        entry = if File.exist?(path)
                  JSON.parse(File.read(path), symbolize_names: true)
                else
                  manifest_entry(File.basename(path, ".json"))
                end
        return expire_entry!(path) if stale?(entry)
        promote_lru(path)
        entry[:value]
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.read_entry", event_bus: @bus, path:)
        drop_entry!(path)
      end

      def write_entry(path:, value:, key:)
        payload = serialize_value(value)
        ts = Time.now.to_i
        evict_lru while @lru.size >= MAX_ENTRIES
        File.write(path, JSON.generate({ ts:, value: payload }))
        write_manifest_entry(key, ts:, value: payload)
        promote_lru(path)
        @bus&.publish("cache:write", key:)
      end

      def manifest
        return {} unless File.exist?(@manifest_path)

        data = YAML.safe_load_file(@manifest_path, permitted_classes: [Symbol], aliases: false)
        data.is_a?(Hash) ? data : {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "semantic_cache.read_manifest", event_bus: @bus, path: @manifest_path)
        {}
      end

      def manifest_entry(key)
        entry = manifest.fetch(key, nil) || manifest.fetch(key.to_s, nil)
        entry = stringify_or_symbolize(entry)
        entry if entry.is_a?(Hash)
      end

      def write_manifest_entry(key, ts:, value:)
        FileUtils.mkdir_p(@master_root)
        entries = manifest
        entries[key] = { "ts" => ts, "value" => stringify_for_yaml(value) }
        File.write(@manifest_path, entries.to_yaml)
      end

      def delete_manifest_entry(key)
        entries = manifest
        entries.delete(key)
        entries.delete(key.to_s)
        if entries.empty?
          File.delete(@manifest_path) if File.exist?(@manifest_path)
        else
          File.write(@manifest_path, entries.to_yaml)
        end
      end

      def stringify_for_yaml(value)
        value.transform_keys(&:to_s).transform_values do |item|
          item.is_a?(Hash) ? stringify_for_yaml(item) : item
        end
      end

      def stringify_or_symbolize(value)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, item), acc|
          sym_key = key.respond_to?(:to_sym) ? key.to_sym : key
          acc[sym_key] = item.is_a?(Hash) ? stringify_or_symbolize(item) : item
        end
      end

      def serialize_value(value)
        return { __master_result: "ok", value: value.value! } if defined?(Master::Result::Ok) && value.is_a?(Master::Result::Ok)

        if defined?(Master::Result::Err) && value.is_a?(Master::Result::Err)
          return { __master_result: "err", message: value.message, category: value.category }
        end

        { __master_result: "raw", value: }
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
        when "err" then Result.err(message, category:)
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
