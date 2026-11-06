# frozen_string_literal: true

# Profile the crawler pattern: every request arrives without a session cookie,
# so every request is a different guest user. A profiler that reuses one session
# cannot show this — it holds one guest and hits the cache from the second
# request on, which is why the naive local numbers looked fine.
#
#   rails runner script/profile_cookieless.rb [path] [--runs=8]

require "benchmark"

path = ARGV.find { |a| !a.start_with?("--") } || "/"
runs = (ARGV.find { |a| a.start_with?("--runs=") }&.split("=")&.last || 8).to_i

Rails.cache.clear
puts "cache cleared; caching=#{ActionController::Base.perform_caching}"

writes = 0
hits = 0
ActiveSupport::Notifications.subscribe("cache_write.active_support") { writes += 1 }
ActiveSupport::Notifications.subscribe("cache_read.active_support") { |_n, _s, _f, _i, p| hits += 1 if p[:hit] }

times = runs.times.map do
  # A brand new session each time == no cookie == a new guest, like a crawler.
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host = "brgen.no"
  Benchmark.realtime { session.get(path) } * 1000
end

puts format("%-22s p50=%6.0fms  min=%5.0fms  max=%6.0fms", path, times.sort[runs / 2], times.min, times.max)
puts format("cache: %d writes, %d hits across %d cookieless requests", writes, hits, runs)
puts format("per request: %.1f writes, %.1f hits", writes.to_f / runs, hits.to_f / runs)
