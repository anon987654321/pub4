# frozen_string_literal: true

# Query Cache - Advanced LRU TTL cache system migrated from ai3_old
# Manages caching of user queries and their responses with cognitive optimization

require 'logger'

begin
  require 'lru_redux'
rescue LoadError
  puts 'Warning: lru_redux gem not available. Using basic hash cache.'
end

class QueryCache
  attr_reader :cache, :logger

  def initialize(ttl: 3600, max_size: 100)
    if defined?(LruRedux)
      @cache = LruRedux::TTL::Cache.new(max_size, ttl)
    else
      @cache = {}
      @ttl = ttl
      @max_size = max_size
    end

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    log_message(:info, "QueryCache initialized with TTL: #{ttl} seconds and max size: #{max_size}.")
  end

  # Add a query and its response to the cache
  def add(query, response)
    log_message(:info, "Adding query to cache: #{query}")

    if defined?(LruRedux)
      @cache[query] = response
    else
      # Basic implementation without LruRedux
      evict_expired_entries
      evict_if_full
      @cache[query] = { response: response, timestamp: Time.now }
    end
  rescue StandardError => e
    log_message(:error, "Failed to add query to cache: #{e.message}")
  end

  # Retrieve a cached response for a given query
  def retrieve(query)
    if defined?(LruRedux)
      response = @cache[query]
    else
      # Basic implementation check
      entry = @cache[query]
      response = entry && !expired?(entry) ? entry[:response] : nil
    end

    if response
      log_message(:info, "Cache hit for query: #{query}")
      response
    else
      log_message(:info, "Cache miss for query: #{query}")
      nil
    end
  rescue StandardError => e
    log_message(:error, "Failed to retrieve query from cache: #{e.message}")
    nil
  end

  # Clear cache or specific query
  def clear(query: nil)
    if query
      @cache.delete(query)
      log_message(:info, "Cleared cache for query: #{query}")
    else
      @cache.clear
      log_message(:info, 'Cleared entire cache')
    end
  end

  # Get cache statistics for cognitive monitoring
  def stats
    size = @cache.size
    log_message(:info, "Cache statistics - Size: #{size}/#{@max_size}")
    { size: size, max_size: @max_size, utilization: (size.to_f / @max_size * 100).round(2) }
  end

  private

  # Log messages with different severity levels
  def log_message(severity, message)
    case severity
    when :info
      @logger.info(message)
    when :warn
      @logger.warn(message)
    when :error
      @logger.error(message)
    else
      @logger.debug(message)
    end
  end

  # Basic TTL implementation when LruRedux not available
  def expired?(entry)
    return false unless @ttl

    Time.now - entry[:timestamp] > @ttl
  end

  def evict_expired_entries
    return if defined?(LruRedux)

    @cache.delete_if { |_query, entry| expired?(entry) }
  end

  def evict_if_full
    return if defined?(LruRedux) || @cache.size < @max_size

    # Remove oldest entry
    oldest_key = @cache.min_by { |_query, entry| entry[:timestamp] }[0]
    @cache.delete(oldest_key)
  end
end
