#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require_relative "lib/utf8"

ROOT = File.expand_path("..", __dir__)
RAILS_ROOT = File.join(ROOT, "RAILS")
RELAYD = File.join(ROOT, "OPENBSD", "etc", "relayd.conf")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def assert_forward(relayd_text, failures, name, port, domain)
  # Bind to the specific backend block for this app to avoid substring false positives
  # Look for a block starting with 'backend "name"' and ending with '}'
  block = relayd_text.match(/backend\s+"#{name}".*?^}/m)
  if block.nil?
    failures << "relayd: missing backend block for #{name}"
    return
  end

  content = block[0]
  failures << "relayd: missing forward port #{port} for #{name}" unless content.match?(/\bport\s+#{port}\b/)
  failures << "relayd: missing Host route for #{domain} in #{name}" unless content.match?(/\b#{Regexp.escape(domain)}\b/)
end

def check_relayd(failures)
  unless File.file?(RELAYD)
    failures << "missing tracked relayd.conf template"
    return
  end

  relayd = File.read(RELAYD)
  failures << "relayd: missing X-Forwarded-Proto" unless relayd.include?("X-Forwarded-Proto")
  failures << "relayd: missing /up health check" unless relayd.include?('check http "/up"')

  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {})
  apps.each do |name, metadata|
    assert_forward(relayd, failures, name, metadata.fetch("port"), metadata.fetch("domain"))
  end

  master_json = File.join(ROOT, "OPENBSD", "deploy_inventory.json")
  if File.file?(master_json)
    standalone = JSON.parse(File.read(master_json)).fetch("standalone_apps", [])
    standalone.each do |entry|
      assert_forward(relayd, failures, entry.fetch("name"), entry.fetch("port"), entry.fetch("domain"))
    end
  end

  failures << "relayd: master backend missing" unless relayd.include?("forward to <master>")

  # Source master port from inventory instead of magic number
  master_port = 53_187 # default fallback
  if File.file?(master_json)
    master_entry = standalone.find { |e| e["name"] == "master" }
    master_port = master_entry["port"] if master_entry
  end

  failures << "relayd: master missing http /up check" unless relayd.match?(/\bforward to <master>\b.*?\bport\s+#{master_port}\b.*?check http "/up"/)
end

def check_master_rc(failures)
  master_rc = File.join(ROOT, "OPENBSD", "etc", "rc.d", "master")
  return unless File.file?(master_rc)

  rc_text = File.read(master_rc)
  failures << "rc.d/master: container warmup must use smoke ping" unless rc_text.include?("chat/message?message=ping")
  failures << "rc.d/master: container warmup must not require authed metrics" if rc_text.include?('chat/metrics"') && rc_text.include?('"model"')
end

def check_apps_production(failures)
  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {})
  apps.each do |name, metadata|
    production = File.join(RAILS_ROOT, name, "config", "environments", "production.rb")
    next unless File.file?(production)

    text = File.read(production)
    baseline = File.join(RAILS_ROOT, "shared", "config", "environments", "production_baseline.rb")
    text += "\n#{File.read(baseline)}" if text.include?("production_baseline") && File.file?(baseline)
    domain = metadata.fetch("domain")
    failures << "#{name}: production.rb missing assume_ssl" unless text.match?(/\bconfig\.assume_ssl\s*=\s*true\b/)
    failures << "#{name}: production.rb has force_ssl" if text.match?(/\bconfig\.force_ssl\s*=\s*true\b/)
    failures << "#{name}: production.rb missing host #{domain}" unless text.match?(/\b#{Regexp.escape(domain)}\b/)
    # Fix: /up check was performance theater (matching /upload)
    failures << "#{name}: production.rb missing /up host_authorization exclude" unless text.match?(/\b\/up\b/)
    failures << "#{name}: production.rb missing /health host_authorization exclude" unless text.match?(/\b\/health\b/)

    routes = File.join(RAILS_ROOT, name, "config", "routes.rb")
    failures << "#{name}: routes must load shared fleet health endpoint" if File.file?(routes) && !File.read(routes).include?("fleet.rb")
  end
end

def check_master_web(failures)
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

  master_web_root = File.join(ROOT, "MASTER", "web")
  [
    File.join(master_web_root, "public/face.runtime.js"),
    File.join(master_web_root, "lib/tasks/face_runtime.rake"),
    File.join(master_web_root, "lib/tasks/face_modules_bundle.rake"),
    File.join(master_web_root, "script/build_face_modules.sh"),
    File.join(master_web_root, "script/probe_http"),
    File.join(master_web_root, "script/ci_web_probe"),
  ].each do |path|
    failures << "MASTER/web: missing #{path.delete_prefix(ROOT + '/')}" unless File.file?(path)
  end

  chat_index = File.join(master_web_root, "app/views/chat/index.html.erb")
  if File.file?(chat_index)
    chat_body = File.read(chat_index)
    failures << "MASTER/web: chat index missing inline lazy face boot" unless chat_body.include?("function loadFace") && chat_body.include?('asset_path("face.js")')
  else
    failures << "MASTER/web: missing MASTER/web/app/views/chat/index.html.erb"
  end
end

def check_operator(failures)
  openbsd = File.join(ROOT, "OPENBSD", "OPERATOR.sh")
  if File.file?(openbsd)
    text = File.read(openbsd)
    failures << "OPERATOR.sh: production db:seed is not explicitly gated" unless text.include?("RUN_PRODUCTION_SEEDS")
    failures << "OPERATOR.sh: default deploy must run sync/apply path" unless text.match?(/""\)\s*\n\s*deploy_live/m)
  else
    failures << "missing canonical OpenBSD deploy script"
  end
end

def check_system_configs(failures)
  # Relayd timeout
  relayd_text = File.file?(RELAYD) ? File.read(RELAYD) : ""
  if (relayd_timeout = relayd_text.match(/timeout\s+(\d+)/))
    failures << "relayd: timeout should allow slow document boot (>= 15000)" if relayd_timeout[1].to_i < 15_000
  end

  # Runtime config
  runtime_cfg = File.join(ROOT, "MASTER", "data/runtime.yml")
  if File.file?(runtime_cfg)
    cfg = YAML.safe_load_file(runtime_cfg) || {}
    enhancements = Array(cfg.dig("runtime", "enhancements"))
    failures << "MASTER/runtime: actioncable_fallback enhancement missing" unless enhancements.include?("actioncable_fallback")
  end
end

failures = []
check_relayd(failures)
check_master_rc(failures)
check_apps_production(failures)
check_master_web(failures)
check_operator(failures)
check_system_configs(failures)

if failures.any?
  warn "Deploy smoke gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

apps_count = YAML.safe_load(File.read(APPS_YML)).fetch("apps", {}).size
puts "Deploy smoke gate passed (relayd template + #{apps_count} production configs + MASTER/web probes)."
