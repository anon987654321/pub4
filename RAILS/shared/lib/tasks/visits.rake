# frozen_string_literal: true

# The read surface for Shared::VisitCount, in the engine because the counter is:
# Rails::Engine#run_tasks_blocks loads lib/tasks/**/*.rake, so every host app
# gets these tasks from this one copy.
#
# The read surface for Shared::VisitCount. A rake task rather than a dashboard
# page: the question this answers — which of seven city domains anyone reaches —
# is asked when deciding where to spend effort, not continuously, and a page
# would need auth, a route and a design decision to serve the same numbers.
namespace :visits do
  desc "Visits per host over the last N days (default 30)"
  task :hosts, [ :days ] => :environment do |_, args|
    days = (args[:days].presence || 30).to_i
    since = days.days.ago.to_date
    by_host = Shared::VisitCount.by_host(since:)
    total = by_host.values.sum

    puts "Visits since #{since} (#{days} days)"
    if by_host.empty?
      puts "  (nothing recorded yet — Shared::VisitCounting counts successful HTML GETs)"
      next
    end

    width = by_host.keys.map(&:length).max
    by_host.each do |host, count|
      share = total.positive? ? (count * 100.0 / total).round(1) : 0.0
      puts format("  %-#{width}s  %8d  %5.1f%%", host, count, share)
    end
    puts format("  %-#{width}s  %8d", "TOTAL", total)
  end

  desc "Visits per route, optionally for one host: rake visits:routes[oshlo.no,30]"
  task :routes, %i[host days] => :environment do |_, args|
    days = (args[:days].presence || 30).to_i
    since = days.days.ago.to_date
    by_route = Shared::VisitCount.by_route(host: args[:host].presence, since:)

    puts "Routes since #{since}#{args[:host].present? ? " on #{args[:host]}" : ""}"
    next puts("  (nothing recorded yet)") if by_route.empty?

    width = by_route.keys.map(&:length).max
    by_route.first(40).each { |route, count| puts format("  %-#{width}s  %8d", route, count) }
  end

  # Visits are the denominator Shared::OutboundClick has been missing: a click
  # rate is the number that decides whether affiliate work is worth more of it.
  desc "Click-through rate: outbound clicks against visits over N days"
  task :ctr, [ :days ] => :environment do |_, args|
    days = (args[:days].presence || 30).to_i
    visits = Shared::VisitCount.total(since: days.days.ago.to_date)
    clicks = Shared::OutboundClick.since(days.days.ago).count

    puts "Last #{days} days"
    puts format("  visits            %8d", visits)
    puts format("  outbound clicks   %8d", clicks)
    if visits.positive?
      puts format("  click-through     %8.2f%%", clicks * 100.0 / visits)
    else
      puts "  click-through     n/a (no visits recorded)"
    end
    puts
    puts "Clicks per merchant:"
    merchants = Shared::OutboundClick.by_merchant(since: days.days.ago)
    next puts("  (none)") if merchants.empty?

    merchants.first(20).each { |merchant, count| puts format("  %-28s %6d", merchant || "(unattributed)", count) }
  end
end
