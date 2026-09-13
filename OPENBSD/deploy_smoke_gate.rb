#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require_relative "lib/utf8"

ROOT = File.expand_path("..", __dir__)
RAILS_ROOT = File.join(ROOT, "RAILS")
RELAYD = File.join(ROOT, "OPENBSD", "etc", "relayd.conf")
HTTPD = File.join(ROOT, "OPENBSD", "etc", "httpd.conf")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def assert_forward(relayd_text, failures, name, port, domain)
  # relayd uses a named table plus a forward line in the relay, not a named
  # backend block. Check both halves against the same service name.
  failures << "relayd: missing backend table <#{name}>" unless relayd_text.match?(/^table\s+<#{Regexp.escape(name)}>\s+\{/)
  failures << "relayd: missing forward port #{port} for #{name}" unless relayd_text.match?(/^\s*forward to <#{Regexp.escape(name)}> port #{port} check http "\/up"/)
  failures << "relayd: missing Host route for #{domain} in #{name}" unless relayd_text.match?(/^\s*match request header "Host" value "#{Regexp.escape(domain)}" forward to <#{Regexp.escape(name)}>/)
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
    inventory = JSON.parse(File.read(master_json))
    if (master_entry = inventory.dig("master_face"))
      master_port = master_entry.fetch("port")
      failures << "relayd: master backend missing" unless relayd.include?("forward to <master>")
      failures << "relayd: master missing http /up check" unless relayd.include?("forward to <master> port #{master_port} check http \"/up\"")
    end
  end
end

# Port 80 is httpd's, and the part of it that matters is the ACME location:
# acme-client writes HTTP-01 challenges to /var/www/acme, which is "/acme" inside
# httpd's chroot. Lose the location and renewal fails without a word until every
# certificate lapses.
def check_httpd(failures)
  unless File.file?(HTTPD)
    failures << "missing tracked httpd.conf"
    return
  end

  httpd = File.read(HTTPD)
  failures << "httpd: no listener on port 80" unless httpd.match?(/^\s*listen on \S+ port 80\b/)
  acme = httpd[%r{location "/\.well-known/acme-challenge/\*" \{(.*?)\}}m, 1]
  if acme.nil?
    failures << "httpd: no /.well-known/acme-challenge/ location"
  elsif !acme.include?('root "/acme"')
    failures << "httpd: the ACME location must serve root \"/acme\", acme-client's challengedir inside the chroot"
  end
end

MASTER_RC = File.join(ROOT, "OPENBSD", "etc", "rc.d", "master")
AUTH_TIER = File.join(ROOT, "MASTER", "web", "app", "middleware", "auth_tier.rb")

# Every path rc.d/master's post-start block asks the local Falcon for, with the
# line that asks.
def warmup_requests(rc_text)
  rc_text.each_line.filter_map do |line|
    path = line[%r{http://127\.0\.0\.1:\$\{?PORT\}?(/[^"'\s]*)}, 1]
    [path, line] if path && line.include?("curl")
  end
end

# The paths AuthTier serves before it looks for a token, read from the
# middleware so this list cannot drift from the one that decides.
def auth_tier_public_paths
  return [] unless File.file?(AUTH_TIER)

  File.read(AUTH_TIER)[/PUBLIC_PATHS\s*=\s*%w\[([^\]]+)\]/, 1].to_s.split
end

# The warmup has to be answerable by a process holding no token. It once waited
# 240s on metrics the tier gate had put behind one, and the restart logged "not
# ready" for a service that was fine. So: something to warm, at least one path
# AuthTier serves without asking, no credential on any request, and nothing under
# /chat/metrics. Which query string it sends is its own business.
def check_master_rc(failures, rc_text = (File.read(MASTER_RC) if File.file?(MASTER_RC)), public_paths = auth_tier_public_paths)
  return unless rc_text

  requests = warmup_requests(rc_text)
  failures << "rc.d/master: no warmup request to the local port" if requests.empty?
  unless requests.any? { |path, _| public_paths.include?(path.split("?").first) }
    failures << "rc.d/master: no warmup request asks a path AuthTier serves without a token (#{public_paths.join(' ')})"
  end
  requests.each do |path, line|
    failures << "rc.d/master: warmup #{path} carries a credential" if line.match?(/token=|Authorization:|X-Token/i)
    failures << "rc.d/master: warmup #{path} needs auth since the tier gate" if path.start_with?("/chat/metrics")
  end
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
    failures << "#{name}: production.rb missing /up host_authorization exclude" unless text.include?("/up")
    failures << "#{name}: production.rb missing /health host_authorization exclude" unless text.include?("/health")

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

# Definitions above, the run below, so test/test_gate_fixtures.rb can hand each
# check the shape it must flag.
return unless $PROGRAM_NAME == __FILE__

failures = []
check_relayd(failures)
check_httpd(failures)
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
puts "Deploy smoke gate passed (relayd and httpd templates + #{apps_count} production configs + MASTER/web probes)."
