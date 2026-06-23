#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
RELAYD = File.join(ROOT, "DEPLOY", "openbsd", "etc", "relayd.conf")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")
failures = []

unless File.file?(RELAYD)
  failures << "missing tracked relayd.conf template"
else
  relayd = File.read(RELAYD)
  failures << "relayd: missing X-Forwarded-Proto" unless relayd.include?("X-Forwarded-Proto")
  failures << "relayd: missing /up health check" unless relayd.include?('check http "/up"')

  apps.each do |name, metadata|
    port = metadata.fetch("port")
    domain = metadata.fetch("domain")
    failures << "relayd: missing forward for #{name}:#{port}" unless relayd.include?("port #{port}")
    failures << "relayd: missing Host route for #{domain}" unless relayd.include?(domain)
  end

  failures << "relayd: master backend missing" unless relayd.include?("forward to <master>")
  failures << "relayd: master missing http /up check" unless relayd.include?('forward to <master> port 53187 check http "/up"')
end

apps.each do |name, metadata|
  production = File.join(RAILS_ROOT, name, "config", "environments", "production.rb")
  next unless File.file?(production)

  text = File.read(production)
  baseline = File.join(RAILS_ROOT, "shared", "config", "environments", "production_baseline.rb")
  text += "\n#{File.read(baseline)}" if text.include?("production_baseline") && File.file?(baseline)
  domain = metadata.fetch("domain")
  failures << "#{name}: production.rb missing assume_ssl" unless text.match?(/\bconfig\.assume_ssl\s*=\s*true\b/)
  failures << "#{name}: production.rb has force_ssl" if text.match?(/\bconfig\.force_ssl\s*=\s*true\b/)
  failures << "#{name}: production.rb missing host #{domain}" unless text.include?(domain)
  failures << "#{name}: production.rb missing /up host_authorization exclude" unless text.include?('"/up"')
end

master_web = File.join(ROOT, "MASTER", "web", "config", "environments", "production.rb")
if File.file?(master_web)
  text = File.read(master_web)
  failures << "MASTER/web: missing assume_ssl" unless text.match?(/\bconfig\.assume_ssl\s*=\s*true\b/)
end

if failures.any?
  warn "Deploy smoke gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Deploy smoke gate passed (relayd template + #{apps.size} production configs)."