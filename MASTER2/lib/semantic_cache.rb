# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module MASTER
  # SemanticCache - Cache LLM responses by prompt similarity
  # Uses local file-based cache with optional Weaviate for semantic matching
  # Writes to Paths.semantic_cache (var/cache/semantic/)
  module SemanticCache
    CACHE_VERSION = 1
    MAX_CACHE_SIZE = 1000        # Max cached entries
    SIMILARITY_THRESHOLD = 0.92  # Cosine similarity threshold for cache hits
    MAX_ENTRY_AGE = 7 * 24 * 3600  # 7 days TTL

    class << self
      # Check cache for a similar prompt
      def lookup(prompt, tier: nil)
        # Step 1: Exact match by SHA256 hash
        exact = exact_lookup(prompt)
        return Result.ok(exact) if exact

        # Step 2: Semantic match via Weaviate (if available)
        if weaviate_available?
          semantic = semantic_lookup(prompt, tier: tier)
          return Result.ok(semantic) if semantic
        end

        Result.err("cache miss.")
      rescue StandardError => e
        Logging.warn("SemanticCache lookup failed: #{e.message}") if defined?(Logging)
        Result.err("cache error: #{e.message}")
      end

      # Store a response in cache
      def store(prompt, response_data, tier: nil)
        key = cache_key(prompt)
        entry = {
          version: CACHE_VERSION,
          key: key,
          prompt_hash: Digest::SHA256.hexdigest(prompt.strip.downcase),
          prompt_preview: prompt[0, 200],
          tier: tier&.to_s,
          response: response_data,
          created_at: Time.now.utc.iso8601,
          hit_count: 0
        }

        # Write to file cache
        path = entry_path(key)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(entry))

        # Also store in Weaviate for semantic search
        if weaviate_available?
          Weaviate.store(
            content: prompt,
            type: "cache",
            source: key,
            metadata: { tier: tier&.to_s, cost: response_data[:cost] }
          )
        end

        evict_if_needed
        Result.ok(key)
      rescue StandardError => e
        Logging.warn("SemanticCache store failed: #{e.message}") if defined?(Logging)
        Result.err(e.message)
      end

      # Cache stats
      def stats
        entries = Dir.glob(File.join(cache_dir, "*.json"))
        total_size = entries.sum { |f| File.size(f) rescue 0 }
        {
          entries: entries.size,
          size_bytes: total_size,
          size_human: format_size(total_size),
          cache_dir: cache_dir
        }
      end

      # Clear all cache
      def clear!
        FileUtils.rm_rf(Dir.glob(File.join(cache_dir, "*.json")))
      end

      private

      def cache_dir
        Paths.semantic_cache
      end

      def cache_key(prompt)
        Digest::SHA256.hexdigest(prompt.strip.downcase)[0, 16]
      end

      def entry_path(key)
        File.join(cache_dir, "#{key}.json")
      end

      def exact_lookup(prompt)
        key = cache_key(prompt)
        path = entry_path(key)
        return nil unless File.exist?(path)

        entry = JSON.parse(File.read(path, symbolize_names: true), symbolize_names: true)
        return nil if entry[:version] != CACHE_VERSION
        return nil if expired?(entry)

        # Verify exact hash match
        return nil unless entry[:prompt_hash] == Digest::SHA256.hexdigest(prompt.strip.downcase)

        # Update hit count
        entry[:hit_count] += 1
        entry[:last_hit] = Time.now.utc.iso8601
        File.write(path, JSON.pretty_generate(entry))

        Dmesg.log("cache0", message: "exact hit: #{key}") if defined?(Dmesg)
        entry[:response]
      end

      def semantic_lookup(prompt, tier: nil)
        result = Weaviate.search(query: prompt, limit: 1, type: "cache")
        return nil unless result.ok?

        matches = result.value
        return nil if matches.empty?

        best = matches.first
        return nil if best[:distance] && best[:distance] > (1.0 - SIMILARITY_THRESHOLD)

        source_key = best[:source]
        return nil unless source_key

        path = entry_path(source_key)
        return nil unless File.exist?(path)

        entry = JSON.parse(File.read(path, symbolize_names: true), symbolize_names: true)
        return nil if expired?(entry)

        Dmesg.log("cache0", message: "semantic hit: #{source_key} (dist=#{best[:distance]})") if defined?(Dmesg)
        entry[:response]
      end

      def expired?(entry)
        created = Time.parse(entry[:created_at]) rescue Time.now
        (Time.now - created) > MAX_ENTRY_AGE
      end

      def weaviate_available?
        defined?(Weaviate) && Weaviate.respond_to?(:available?) && Weaviate.available?
      end

      def evict_if_needed
        entries = Dir.glob(File.join(cache_dir, "*.json"))
        return if entries.size <= MAX_CACHE_SIZE

        # Evict entries with lowest hit count, then oldest last_hit
        entries_with_data = entries.map do |path|
          begin
            entry = JSON.parse(File.read(path, symbolize_names: true), symbolize_names: true)
            {
              path: path,
              hit_count: entry[:hit_count] || 0,
              last_hit: entry[:last_hit] ? Time.parse(entry[:last_hit]) : File.mtime(path)
            }
          rescue StandardError => e
            { path: path, hit_count: 0, last_hit: File.mtime(path) }
          end
        end

        sorted = entries_with_data.sort_by { |e| [e[:hit_count], e[:last_hit]] }
        to_remove = sorted.first(entries.size - MAX_CACHE_SIZE)
        to_remove.each do |e|
          begin; File.delete(e[:path]); rescue SystemCallError => err; Logging.warn("SemanticCache", "cleanup failed: #{err.message}"); end
        end
      end

      def format_size(bytes)
        return "0B" if bytes == 0
        units = %w[B KB MB GB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = units.size - 1 if exp >= units.size
        "#{(bytes.to_f / 1024**exp).round(1)}#{units[exp]}"
      end
    end
  end
end
