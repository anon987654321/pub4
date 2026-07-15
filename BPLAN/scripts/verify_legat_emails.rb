#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare manifest `to` addresses with funding.yml funder records and contact_url hints.
# Usage: ruby scripts/verify_legat_emails.rb [--strict]
require "yaml"

ROOT = File.expand_path("..", __dir__)
manifest = YAML.load_file(File.join(ROOT, "legats/manifest.yml"))
funding = YAML.load_file(File.join(ROOT, "funding.yml"))
strict = ARGV.include?("--strict")

funders_by_id = funding.fetch("funders", []).to_h { |f| [f["id"], f] }
issues = []

manifest.fetch("applications", []).each do |app|
  id = app["id"]
  to = app["to"].to_s.strip.downcase
  next if to.empty?

  if to == "bergen@pub.attorney"
    issues << { id: id, level: :info, msg: "self-to / internal" }
    next
  end

  funder_id = app["funder_id"]
  if funder_id && funders_by_id[funder_id]
    f = funders_by_id[funder_id]
    portal = f["portal_url"] || f["soknadsportal"]
    if portal && !app["contact_url"].to_s.include?(portal.to_s)
      issues << { id: id, level: :warn, msg: "contact_url may not match funder portal #{portal}" }
    end
  end

  if app["verify_to"] && app["contact_url"].to_s.strip.empty?
    issues << { id: id, level: :error, msg: "verify_to without contact_url" }
  end

  if to.include?("example.com") || to.include?("placeholder")
    issues << { id: id, level: :error, msg: "suspicious to: #{to}" }
  end
end

issues.group_by { |i| i[:level] }.each do |level, rows|
  puts "\n#{level.to_s.upcase} (#{rows.size})"
  rows.each { |r| puts "  #{r[:id]}: #{r[:msg]}" }
end

exit 1 if strict && issues.any? { |i| i[:level] == :error }
puts "\nChecked #{manifest.fetch('applications', []).size} applications."