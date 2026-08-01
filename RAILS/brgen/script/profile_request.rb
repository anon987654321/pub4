# frozen_string_literal: true

# Profile a request in-process, locally. No VPS, no server, no log parsing.
#
#   RBENV_VERSION=3.4.9 rbenv exec bundle exec rails runner script/profile_request.rb /
#   ... script/profile_request.rb /communities/3 --seed=200
#
# Written after profiling on the box itself took production down: reading
# /var/log/messages to count queries pulled 504 MB into a 1 GB VM, memory hit
# 0%, emergency_cpu killed both Falcon workers and all four apps went with them.
# Query counts and N+1 shapes reproduce at any data size — only absolute latency
# needs production volume, and --seed builds that here instead.

require "benchmark"

path = ARGV.find { |a| !a.start_with?("--") } || "/"
seed = ARGV.find { |a| a.start_with?("--seed=") }&.split("=")&.last.to_i
runs = (ARGV.find { |a| a.start_with?("--runs=") }&.split("=")&.last || 5).to_i

if seed.positive?
  city = City.find_by(domain: "brgen.no") || City.first
  ActsAsTenant.current_tenant = city
  author = User.strict_loading(false).first ||
           User.create!(email_address: "prof@brgen.no", password: "password123")
  community = Community.create!(name: "Profile #{SecureRandom.hex(3)}", slug: "prof-#{SecureRandom.hex(4)}")
  seed.times { |i| Post.create!(user: author, community:, title: "Profile #{i}", content: "…") }
  puts "seeded community #{community.id} (#{community.slug}) with #{seed} posts"
  path = "/communities/#{community.id}"
end

session = ActionDispatch::Integration::Session.new(Rails.application)
session.host = "brgen.no"

queries = Hash.new(0)
view_ms = Hash.new(0.0)

ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, payload|
  next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])

  queries[payload[:sql].gsub(/\d+/, "?").gsub(/'[^']*'/, "?").squeeze(" ")] += 1
end
ActiveSupport::Notifications.subscribe("render_partial.action_view") do |_n, start, finish, _i, payload|
  view_ms[payload[:identifier].to_s.sub(Rails.root.to_s, "")] += (finish - start) * 1000
end

session.get(path) # warm
queries.clear
view_ms.clear

times = runs.times.map { Benchmark.realtime { session.get(path) } * 1000 }
total_q = queries.values.sum / runs

puts
puts "#{path}  ->  #{session.response.status}   #{(session.response.body.bytesize / 1024.0).round}KB"
puts format("wall: min=%.0fms  p50=%.0fms  max=%.0fms   queries/request=%d",
            times.min, times.sort[runs / 2], times.max, total_q)
puts
puts "top query shapes (per request):"
queries.sort_by { |_, n| -n }.first(8).each do |sql, n|
  puts format("  %4d  %s", n / runs, sql[0, 96])
end
puts
puts "slowest partials (ms per request):"
view_ms.sort_by { |_, ms| -ms }.first(8).each do |file, ms|
  puts format("  %7.1f  %s", ms / runs, file)
end
