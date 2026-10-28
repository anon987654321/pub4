#!/usr/bin/env ruby
# frozen_string_literal: true

# Dead CSS and dead routes, proposed and never silently deleted.
#
#   ruby MASTER/tools/dead_css_sweep.rb                 report every app (static scan, plus
#                                                       any rendered coverage on disk)
#   ruby MASTER/tools/dead_css_sweep.rb --app brgen     one app
#   ruby MASTER/tools/dead_css_sweep.rb --capture       render the declared surfaces with a
#                                                       real browser and fold rule usage into
#                                                       MASTER/.master/dead_css/coverage/
#   ruby MASTER/tools/dead_css_sweep.rb --app brgen --apply
#                                                       delete the rules proven dead by BOTH
#                                                       coverage and the static scan, one app,
#                                                       through WriteGuard and a Transaction
#
# The report lands in MASTER/.master/dead_css/report.{txt,json}.

require "optparse"
require "tmpdir"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
require_relative "../lib/fix/dead_css_sweep"

opts = { apps: [], apply: false, capture: false }
OptionParser.new do |o|
  o.on("--app NAME") { |v| opts[:apps] << v }
  o.on("--apply") { opts[:apply] = true }
  o.on("--capture") { opts[:capture] = true }
end.parse!

sweep = Master::Fix::DeadCssSweep.new

if opts[:capture]
  require File.expand_path("../checks/support/geometry_probe", __dir__)
  require File.expand_path("../checks/support/composition_probe", __dir__)
  repo = sweep.root
  abort "dead_css_sweep: no browser available" unless Deploy::GeometryProbe.available?

  surfaces = Deploy::GeometryProbe.reachable(Deploy::GeometryProbe.surfaces(root: repo), root: repo)
  abort "dead_css_sweep: no app is listening; boot them with bin/operator triangle up" if surfaces.empty?

  store = Master::Fix::DeadCssCoverage.new
  Dir.mktmpdir("dead-css") do |dir|
    Deploy::GeometryProbe.with_browser(root: repo, warm: surfaces) do |cdp|
      surfaces.each do |surface|
        next unless Deploy::GeometryProbe.ok?(Deploy::GeometryProbe.walk(cdp, surface))

        store.track(cdp, surface) { Deploy::CompositionProbe.capture(cdp, surface, dir:, pass: 1, limit: 12) }
      end
    end
  end
  warn "dead_css_sweep: captured #{surfaces.size} surfaces; #{store.errors.size} tracking errors"
  store.errors.first(5).each { |e| warn "  #{e}" }
end

if opts[:apply]
  abort "dead_css_sweep: --apply takes exactly one --app" unless opts[:apps].size == 1
  outcome = sweep.apply(opts[:apps].first)
  abort "dead_css_sweep: #{outcome[:error]}" if outcome[:error]
  puts "dead_css_sweep: removed #{outcome[:removed]} rules from #{outcome[:files].join(", ")}"
  exit 0
end

results = opts[:apps].empty? ? sweep.run : sweep.run(apps: opts[:apps])
findings = sweep.findings(results) + sweep.route_findings
path = sweep.write_report(results, findings)
results.each_value do |r|
  s = r[:summary]
  puts format("%-10s rules=%d dead=%d static_only=%d state_only=%d dead_share=%.1f%% (%s)",
              s[:app], s[:rules_total], s[:dead], s[:static_only], s[:state_only], s[:dead_share_pct], s[:basis])
end
puts "routes/views: #{findings.count { |f| f[:law] == 'DEAD_ROUTE' }} candidates"
puts "report: #{path}"
