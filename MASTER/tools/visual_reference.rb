#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../checks/support/geometry_probe"
require_relative "../lib/fix/visual_reference"

# Reference comparison for tuning a pub4 page toward a reference product (Design2Code's idea):
#
#   ruby MASTER/tools/visual_reference.rb capture URL OUT.json [WIDTH HEIGHT]
#   ruby MASTER/tools/visual_reference.rb compare OURS.json REFERENCE.json
#
# capture writes the page's geometry walk; keep reference captures outside the repository.
# compare prints the per-element deltas. It is a report, never a gate: it exits 0 either way.
module VisualReferenceTool
  Page = Struct.new(:url)

  module_function

  def capture(url, out, width = 390, height = 844)
    Deploy::CdpSession.open do |cdp|
      cdp.viewport(width.to_i, height.to_i, mobile: width.to_i < 768)
      cdp.navigate(url)
      File.write(out, JSON.pretty_generate(Deploy::GeometryProbe.measure_current(cdp, Page.new(url))))
    end
    out
  end

  def compare(ours, theirs)
    elements = [ours, theirs].map { |path| JSON.parse(File.read(path)).fetch("elements", []) }
    Master::Fix::VisualReference.report(Master::Fix::VisualReference.compare(*elements))
  end
end

return unless $PROGRAM_NAME == __FILE__

command, *args = ARGV
case command
when "capture" then puts VisualReferenceTool.capture(*args)
when "compare" then puts VisualReferenceTool.compare(*args)
else abort "usage: visual_reference.rb capture URL OUT.json [WIDTH HEIGHT] | compare OURS.json REFERENCE.json"
end
