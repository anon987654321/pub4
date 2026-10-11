#!/usr/bin/env ruby
# frozen_string_literal: true

# The same shared primitive, compared across apps. Needs the apps running
# (bin/operator triangle up) and a browser; it renders each declared surface,
# reads computed styles for header, nav link, footer, button and form control,
# and reports the values that differ between brgen, its verticals and bsdports,
# with the RAILS/__shared stylesheet that should own them. Amber's deviations
# are listed as informational. Report only, to MASTER/.master/cross_app/.
#
#   ruby MASTER/tools/cross_app_consistency.rb [--viewport mobile|desktop]

require "optparse"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
require File.expand_path("../gates/support/geometry_probe", __dir__)
require_relative "../lib/fix/cross_app_consistency"
require_relative "../lib/fix/cross_app_probe"

viewport = nil
OptionParser.new { |o| o.on("--viewport V") { |v| viewport = v } }.parse!

repo = File.expand_path("../..", __dir__)
abort "cross_app_consistency: no browser available" unless Deploy::GeometryProbe.available?

surfaces = Deploy::GeometryProbe.reachable(Deploy::GeometryProbe.surfaces(root: repo), root: repo)
surfaces = surfaces.select { |s| s.viewport == viewport } if viewport
abort "cross_app_consistency: no app is listening; boot them with bin/operator triangle up" if surfaces.empty?

samples = []
Deploy::GeometryProbe.with_browser(root: repo, warm: surfaces) do |cdp|
  surfaces.each do |surface|
    payload = Deploy::GeometryProbe.walk(cdp, surface)
    next unless Deploy::GeometryProbe.ok?(payload)

    capture = { surface:, payload: payload.merge("composition" => { "state" => "resting" }) }
    samples.concat(Master::Fix::CrossAppConsistency.from_captures([capture]))
    samples.concat(Master::Fix::CrossAppProbe.samples(cdp, surface))
  end
end

out = File.expand_path("../.master/cross_app", __dir__)
checker = Master::Fix::CrossAppConsistency.new(samples, out_dir: out)
report = checker.report
checker.write(report)
puts report[:text]
puts "report: #{out}/cross_app.txt"
