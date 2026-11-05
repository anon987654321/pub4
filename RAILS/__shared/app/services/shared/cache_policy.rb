# frozen_string_literal: true

module Shared
  # The TTLs the apps write with: :search_results in Tradedoubler, and
  # brgen's weekly and monthly rollup jobs. The legal pages revalidate with an
  # ETag instead of keeping a TTL (PagesController#show).
  module CachePolicy
    TTL = {
      search_results: 900,
      weekly_stats: 604_800,
      monthly_rollup: 7_776_000,
    }.freeze

    def self.ttl_for(key_type)
      TTL.fetch(key_type.to_sym)
    end
  end
end
