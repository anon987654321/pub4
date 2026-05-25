# frozen_string_literal: true

module Shared
  class CacheFast
    def self.write(key, value, ttl = 300)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
          "INSERT OR REPLACE INTO transient_cache(cache_key, cache_value, expires_at) VALUES(?, ?, ?)",
          key, value.to_json, (Time.current + ttl).to_i
        ])
      )
    end

    def self.read(key)
      row = ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT cache_value FROM transient_cache WHERE cache_key = ? AND expires_at > ?",
          key, Time.current.to_i
        ])
      )
      row ? JSON.parse(row["cache_value"]) : nil
    end
  end
end
