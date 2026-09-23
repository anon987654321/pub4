#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "tmpdir"
require "chunky_png"

require_relative "support/geometry_probe"

ROOT = File.expand_path("../..", __dir__)

options = {
  target: "RAILS",
  out: File.join(Dir.tmpdir, "master-visual-evidence-#{$$}"),
  pass: 1,
  max_surfaces: Integer(ENV.fetch("MASTER_VISUAL_MAX_SURFACES", "8")),
}

OptionParser.new do |o|
  o.banner = "usage: visual_evidence.rb --target RAILS|MASTER --out DIR [--pass N]"
  o.on("--target NAME") { |v| options[:target] = v }
  o.on("--out DIR") { |v| options[:out] = v }
  o.on("--pass N", Integer) { |v| options[:pass] = v }
  o.on("--max-surfaces N", Integer) { |v| options[:max_surfaces] = v }
end.parse!

def target_apps(rows, target)
  case target.to_s.upcase
  when "MASTER"
    rows.select { |s| s.app == "master" }
  when "RAILS"
    app = ENV["MASTER_VISUAL_APP"].to_s.strip.downcase
    app.empty? ? rows.reject { |s| s.app == "master" } : rows.select { |s| s.app == app }
  else
    abort "visual_evidence: unknown target #{target.inspect} (use RAILS or MASTER)"
  end
end

def canonical_rows(rows, max:, pass:)
  grouped = rows.group_by(&:app)
  core = grouped.keys.sort.flat_map do |app|
    group = grouped.fetch(app)
    mobile = group.find { |s| s.viewport == "mobile" }
    desktop = group.find { |s| s.viewport == "desktop" }
    [mobile || group.first, desktop || group.find { |s| s != mobile }]
  end.compact.uniq

  extras = rows.reject { |s| core.include?(s) }.sort_by(&:id)
  return core.first(max) if extras.empty? || core.size >= max

  offset = (pass - 1) % extras.size
  (core + extras.rotate(offset)).first(max)
end

def safe_slug(value)
  value.to_s.gsub(%r{[^a-zA-Z0-9._-]+}, "_")
end

def contact_sheet(paths, output)
  images = paths.map { |path| ChunkyPNG::Image.from_file(path) }
  cols = 2
  cell_w = images.map(&:width).max
  cell_h = images.map(&:height).max
  rows = (images.size.to_f / cols).ceil
  sheet = ChunkyPNG::Image.new(cols * cell_w, rows * cell_h, ChunkyPNG::Color::WHITE)

  images.each_with_index do |image, index|
    ox = (index % cols) * cell_w
    oy = (index / cols) * cell_h
    image.height.times do |y|
      image.width.times { |x| sheet[ox + x, oy + y] = image[x, y] }
    end
  end
  sheet.save(output)
  output
end

surfaces = canonical_rows(
  target_apps(Deploy::GeometryProbe.surfaces(root: ROOT), options[:target])
    .select { |s| options[:target].to_s.upcase == "MASTER" || s.snapshot },
  max: [options[:max_surfaces], 1].max,
  pass: options[:pass],
)

FileUtils.mkdir_p(options[:out])
entries = []

Deploy::GeometryProbe.with_browser(root: ROOT, warm: surfaces) do |cdp|
  surfaces.each_with_index do |surface, index|
    payload = Deploy::GeometryProbe.walk(cdp, surface)
    next unless Deploy::GeometryProbe.ok?(payload)

    slug = safe_slug(surface.id)
    shot = File.join(options[:out], format("%02d-%s.png", index, slug))
    cdp.screenshot(shot)
    evidence_path = File.join(options[:out], "#{slug}.json")
    File.write(evidence_path, JSON.pretty_generate(payload) + "\n")

    entries << {
      "index" => index + 1,
      "surface" => surface.id,
      "app" => surface.app,
      "label" => surface.label,
      "viewport" => surface.viewport,
      "path" => surface.path,
      "profile" => surface.profile,
      "screenshot" => shot,
      "geometry" => evidence_path,
      "elements" => Array(payload["elements"]).size,
      "gaps" => Array(payload["gaps"]).size,
      "colors" => payload["colors"].is_a?(Hash) ? payload["colors"].size : 0,
      "h1_count" => payload["h1_count"],
      "scroll_width" => payload["scroll_width"],
      "client_width" => payload["client_width"],
      "first_screen" => payload["first_screen"],
    }
  end
end

manifest = {
  "schema" => 1,
  "target" => options[:target].to_s.upcase,
  "pass" => options[:pass],
  "root" => ROOT,
  "entries" => entries,
}
if entries.any?
  manifest["sheet"] = contact_sheet(
    entries.map { |e| e["screenshot"] },
    File.join(options[:out], "contact-sheet.png"),
  )
end

manifest_path = File.join(options[:out], "manifest.json")
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
puts JSON.pretty_generate(manifest)

exit(entries.empty? ? 3 : 0)
