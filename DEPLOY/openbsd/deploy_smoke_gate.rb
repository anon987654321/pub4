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

auth_tier = File.join(ROOT, "MASTER", "web", "app", "middleware", "auth_tier.rb")
if File.file?(auth_tier)
  text = File.read(auth_tier)
  failures << "MASTER/web: forbidden author URL auth bypass" if text.match?(/\bauthor_url\b|\bAUTHOR_NAME\b|\bmaster_author\b/)
  failures << "MASTER/web: weak fixed token length" if text.match?(/\bTOKEN_LENGTH\s*=\s*1[0-9]\b/)
  failures << "MASTER/web: missing high-entropy token generation" unless text.include?("SecureRandom.urlsafe_base64")
else
  failures << "MASTER/web: missing AuthTier middleware"
end

openbsd = File.join(ROOT, "DEPLOY", "openbsd", "openbsd.sh")
if File.file?(openbsd)
  text = File.read(openbsd)
  failures << "openbsd.sh: production db:seed is not explicitly gated" unless text.include?("RUN_PRODUCTION_SEEDS")
  failures << "openbsd.sh: no-argument deploy not blocked" unless text.include?("refusing no-argument deploy")
end

master_web_root = File.join(ROOT, "MASTER", "web")
[
  File.join(master_web_root, "public/face.runtime.js"),
  File.join(master_web_root, "lib/tasks/face_runtime.rake"),
  File.join(master_web_root, "script/ci_web_probe"),
  File.join(master_web_root, "app/views/shared/_face_boot.html.erb")
].each do |path|
  failures << "MASTER/web: missing #{path.delete_prefix(ROOT + '/')}" unless File.file?(path)
end

relayd_text = File.file?(RELAYD) ? File.read(RELAYD) : ""
if (relayd_timeout = relayd_text.match(/timeout\s+(\d+)/))
  failures << "relayd: timeout should allow slow document boot (>= 15000)" if relayd_timeout[1].to_i < 15_000
end

runtime_cfg = File.join(ROOT, "MASTER", "data/runtime/runtime.yml")
if File.file?(runtime_cfg)
  cfg = YAML.safe_load_file(runtime_cfg) || {}
  enhancements = Array(cfg["enhancements"])
  failures << "MASTER/runtime: actioncable_fallback enhancement missing" unless enhancements.include?("actioncable_fallback")
end

if failures.any?
  warn "Deploy smoke gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Deploy smoke gate passed (relayd template + #{apps.size} production configs + MASTER/web probes)."