# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module LLMCache
        # LLM response caching for repeated queries
        
        def initialize_cache
          @llm_cache = {}
          @cache_hits = 0
          @cache_misses = 0
        end
        
        def cached_llm_query(prompt, **options)
          cache_key = generate_cache_key(prompt, options)
          
          if @llm_cache.key?(cache_key)
            @cache_hits += 1
            @last_cached = true
            return @llm_cache[cache_key]
          end
          
          @cache_misses += 1
          @last_cached = false
          result = yield
          
          # Cache successful results
          if result.is_a?(Result) && result.ok?
            @llm_cache[cache_key] = result
            # Limit cache size
            @llm_cache = @llm_cache.to_a.last(50).to_h if @llm_cache.size > 100
          end
          
          result
        end
        
        def cache_stats
          total = @cache_hits + @cache_misses
          return "Cache: empty" if total == 0
          
          hit_rate = (@cache_hits.to_f / total * 100).round(1)
          "Cache: #{@cache_hits} hits, #{@cache_misses} misses (#{hit_rate}% hit rate)"
        end
        
        def clear_cache
          @llm_cache.clear
          @cache_hits = 0
          @cache_misses = 0
          "LLM cache cleared"
        end
        
        private
        
        def generate_cache_key(prompt, options)
          # Simple hash of prompt + relevant options
          key_data = [prompt, options[:persona], options[:temperature]].compact.join('|')
          Digest::SHA256.hexdigest(key_data)[0..16]
        end
      end
    end
  end
end
