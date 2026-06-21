#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("../..", __dir__)
WEB_ROOT = File.join(ROOT, "MASTER", "web")
ASSETS_DIR = File.join(WEB_ROOT, "public", "assets")
MANIFEST = File.join(ASSETS_DIR, ".manifest.json")
REQUIRED = %w[face.css face.js chat.js three.module.js].freeze

failures = []
unless File.file?(MANIFEST)
  failures << "missing #{MANIFEST} — run: cd MASTER/web && RAILS_ENV=production bundle exec rails assets:precompile"
else
  manifest = JSON.parse(File.read(MANIFEST))
  REQUIRED.each do |logical|
    entry = manifest[logical]
    failures << "manifest missing #{logical}" unless entry
    next unless entry

    digested = entry["digested_path"].to_s
    failures << "manifest #{logical} has empty digested_path" if digested.empty?
    path = File.join(ASSETS_DIR, digested)
    failures << "missing digested asset #{digested} for #{logical}" unless File.file?(path)
  end
end

if failures.any?
  warn "MASTER/web assets gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "MASTER/web assets gate passed (#{REQUIRED.size} required assets present)."