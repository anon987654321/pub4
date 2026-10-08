# frozen_string_literal: true

module Shared
  module CachePolicy
    TTL = {
      feed_fragment: 300,
      user_profile: 3600,
      search_results: 900,
      static_page: 86_400,
      weekly_stats: 604_800,
      monthly_rollup: 7_776_000,
    }.freeze

    def self.ttl_for(key_type)
      TTL.fetch(key_type.to_sym)
    end
  end
end
