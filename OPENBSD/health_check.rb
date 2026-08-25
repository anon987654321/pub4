#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

# encoding: utf-8

require "json"
require "open3"
require "optparse"
require "yaml"
require_relative "lib/utf8"
require_relative "lib/guard_state"

ROOT = File.expand_path("..", __dir__)
APPS_YML = File.join(ROOT, "RAILS", "apps.yml")

options = {
  all_ready_apps: false,
  public: false,
  public_only: false,
  core: false,
  json: false,
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby34 OPENBSD/health_check.rb [--core|--all-ready-apps] [--public|--public-only] [--json]"
  parser.on("--core", "Check only core infrastructure plus brgen/master") { options[:core] = true }
  parser.on("--all-ready-apps", "Require every app listed in RAILS/apps.yml") { options[:all_ready_apps] = true }
  parser.on("--public", "Check public HTTPS endpoints, cert files, and externally-routed names") { options[:public] = true }
  # Everything else in this file needs rcctl, pfctl, /etc/relayd.conf and localhost
  # ports -- i.e. vm23. --public-only is the subset an external checker can actually
  # answer, and it exists so OPENBSD/bin/uptime-check.sh can be a wrapper over this
  # file instead of a second, hardcoded list of hosts: that copy named four domains
  # and would have gone on naming four after a fifth app shipped.
  parser.on("--public-only", "Only public HTTPS endpoints (runs anywhere, no vm23 tools)") do
    options[:public_only] = true
    options[:public] = true
  end
  parser.on("--json", "Emit machine-readable JSON on success") { options[:json] = true }
end.parse!

options[:all_ready_apps] = false if options[:core]

failures = []

# A missing binary is a named failure, not a backtrace. This raised Errno::ENOENT
# out of Open3 and killed the whole run at the first check: off the box that is
# every invocation (no /usr/sbin/rcctl), and on the box it would take the weekly
# integrity run down with a stack trace the moment a tool moved -- reporting
# nothing about the twenty checks after it. The point of this script is the list of
# failures, so an absent tool belongs in that list.
def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip]
rescue Errno::ENOENT, Errno::EACCES => e
  [false, "#{cmd.first}: #{e.class.name.split("::").last} (this check needs vm23)"]
end

def privileged(*cmd)
  return cmd if Process.uid.zero?
  return ["doas", "-n", *cmd] if File.executable?("/usr/bin/doas") || File.executable?("/bin/doas")
  cmd
end

def load_apps
  body = YAML.safe_load(File.read(APPS_YML)) || {}
  apps = body.fetch("apps")
  merged = apps.to_h do |name, metadata|
    [
      name.to_s,
      {
        "domain" => metadata.fetch("domain").to_s,
        "port" => Integer(metadata.fetch("port")),
        "standalone" => false,
      },
    ]
  end
  load_standalone_apps.each { |name, metadata| merged[name] = metadata }
  merged
rescue StandardError => e
  warn "apps.yml unreadable: #{e.class}: #{e.message}"
  load_standalone_apps
end

def load_standalone_apps
  path = File.join(ROOT, "OPENBSD", "deploy_inventory.json")
  return {} unless File.file?(path)

  data = JSON.parse(File.read(path))
  Array(data["standalone_apps"]).to_h do |entry|
    name = entry.fetch("name").to_s
    [
      name,
      {
        "domain" => entry.fetch("domain").to_s,
        "port" => Integer(entry.fetch("port")),
        "standalone" => true
      }
    ]
  end
rescue StandardError => e
  warn "deploy_inventory.json standalone_apps unreadable: #{e.class}: #{e.message}"
  {}
end

def service_running?(service)
  ok, out = run(*privileged("/usr/sbin/rcctl", "check", service))
  [ok && out.include?("(ok)"), out]
end

# OpenBSD packages curl into /usr/local/bin; every other host puts it in
# /usr/bin. Hardcoding the first meant a laptop run failed every HTTP check with
# "not found" and said nothing about whether the site was up.
# CURL= is honoured because the wrapper that documents it (bin/uptime-check.sh)
# is now a wrapper over this file.
CURL = [ENV["CURL"], "/usr/local/bin/curl", "/usr/bin/curl"]
       .compact.find { |path| File.executable?(path) } || "curl"
HTTP_TIMEOUT = Integer(ENV.fetch("HEALTH_CHECK_TIMEOUT", "25"))

def curl_ok?(url, timeout: HTTP_TIMEOUT)
  run(CURL, "-fsS", "--max-time", timeout.to_s, url)
end

apps = load_apps
app_ports = apps.transform_values { |metadata| metadata.fetch("port") }
app_domains = apps.transform_values { |metadata| metadata.fetch("domain") }

core_apps = %w[brgen]
ready_apps = options[:all_ready_apps] ? app_ports.keys.sort : core_apps

# Every check below this line except the HTTPS block needs a tool or a file that
# only exists on vm23. Under --public-only they are not skipped silently: the
# collections are empty and the guarded blocks say so in the scope line at the end,
# so a run cannot look like it checked the box when it checked the internet.
on_box = !options[:public_only]

core_services = %w[nsd httpd relayd smtpd master] + core_apps
required_services = on_box ? (core_services + ready_apps).uniq : []

required_services.each do |service|
  running, out = service_running?(service)
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless running
end

if on_box
  pfctl = File.executable?("/sbin/pfctl") ? "/sbin/pfctl" : "/usr/sbin/pfctl"
  ok, out = run(*privileged(pfctl, "-s", "rules"))
  pf_ok = ok && out.include?("block") && out.include?("log all")
  failures << "pfctl: #{out.empty? ? "no rules output" : out}" unless pf_ok

  dns_ok = false
  if File.executable?("/usr/bin/dig")
    dns_ok, dns_out = run("/usr/bin/dig", "@127.0.0.1", "brgen.no", "SOA", "+short", "+time=2", "+tries=1")
    dns_ok &&= !dns_out.empty? && dns_out.include?("brgen.no")
  elsif (dns_cmd = %w[/usr/sbin/drill /usr/bin/drill].find { |c| File.executable?(c) })
    dns_ok, dns_out = run(dns_cmd, "@127.0.0.1", "brgen.no", "SOA")
    dns_ok &&= dns_out.include?("brgen.no.")
  end
  unless dns_ok
    nsd_ok, nsd_out = run(*privileged("/usr/sbin/rcctl", "check", "nsd"))
    nsd_note = nsd_ok && nsd_out.include?("(ok)") ? "nsd reports ok" : nsd_out.to_s.strip
    failures << "dns: no local SOA (#{nsd_note.empty? ? 'nsd check failed' : nsd_note})"
  end

  # DNSSEC signature freshness, which nothing else can see.
  #
  # RRSIGs expire. nsd-resign re-signs anything with under 14 days left and runs
  # from /etc/daily.local, and for as long as that line read `ruby` rather than
  # an absolute path it had never once executed — cron's PATH does not include
  # /usr/local/bin. The zones stayed valid the whole time and every check passed,
  # because unexpired signatures on an unpublished DS look exactly like healthy
  # ones. The day a DS is published at the registrar, that stops being true and
  # the whole zone SERVFAILs on the expiry date.
  #
  # So this asks the question that distinguishes the two states: how long is
  # left. Under 7 days means the nightly re-sign has missed at least one window.
  # Root-only files, so it degrades to silence rather than a false pass off the
  # box or without doas.
  zone_dir = "/var/nsd/zones/master"
  signed = Dir.glob("#{zone_dir}/*.zone.signed")
  if signed.any?
    soon = signed.filter_map do |path|
      expiry = begin
        File.read(path, encoding: "BINARY").scan(/RRSIG\s+\S+\s+\d+\s+\d+\s+\d+\s+(\d{14})/).flatten.min
      rescue StandardError
        nil
      end
      next unless expiry

      days = (Time.new(expiry[0, 4].to_i, expiry[4, 2].to_i, expiry[6, 2].to_i) - Time.now) / 86_400
      [File.basename(path, ".zone.signed"), days.round] if days < 7
    end

    unless soon.empty?
      failures << "dnssec: #{soon.size} zone(s) expire within a week — nsd-resign is not running " \
                  "(#{soon.first(5).map { |z, d| "#{z} #{d}d" }.join(', ')})"
    end

    # More than one KSK and one ZSK means keys are accumulating again, which is
    # what OPERATOR.sh's stage_1 used to do on every run: 700 key files for 60
    # zones, every one of them published, and a DNSKEY response within reach of
    # the 1232-byte UDP ceiling. It also makes a published DS unstable, because
    # nsd-resign signs with the newest key it finds.
    overkeyed = signed.filter_map do |path|
      count = File.read(path, encoding: "BINARY").scan(/IN\s+DNSKEY\s+25[67]\s/).size
      [File.basename(path, ".zone.signed"), count] if count > 2
    end
    unless overkeyed.empty?
      failures << "dnssec: #{overkeyed.size} zone(s) publish more than one KSK+ZSK pair " \
                  "(#{overkeyed.first(5).map { |z, c| "#{z} #{c}" }.join(', ')})"
    end
  end
end

# How far behind each app's last successful deploy is.
#
# A deploy that fails at a CI gate leaves the previous stamp saying "ok" and the
# old build serving, so from outside nothing has happened — and nothing reports
# it. amber sat at 2026-08-12T08:49 for a day and a half through three failed
# attempts, still preloading two CDNs that had been vendored three weeks earlier,
# and the only way to find out was to read a rendered page and compare it against
# the repo. Measured 2026-08-13: brgen 21 commits behind, bsdports 93.
#
# A count, not a clock. Time behind says nothing on a quiet week; commits behind
# is the thing that grows while a gate is red. Warned, not failed, because being
# behind is normal between deploys — the point is that the number is visible.
DEPLOY_DRIFT_LIMIT = Integer(ENV.fetch("DEPLOY_DRIFT_LIMIT", "40"))

if on_box
  repo = "/home/dev/pub4"
  apps.each_key do |name|
    stamp = "/var/db/pub4/last_deploy_#{name}.json"
    next unless File.readable?(stamp)

    sha = begin
      JSON.parse(File.read(stamp))["sha"].to_s
    rescue StandardError
      nil
    end
    next if sha.nil? || sha.empty?

    ok, out = run("git", "-C", repo, "rev-list", "--count", "#{sha}..HEAD")
    next unless ok

    behind = out.strip.to_i
    next if behind <= DEPLOY_DRIFT_LIMIT

    failures << "#{name} deploy: #{behind} commits behind HEAD (last ok #{sha}) — " \
                "a failed CI gate leaves the old stamp saying ok"
  end
end

# A queue with work in it and nobody registered to do it.
#
# brgen's rc.d exported SOLID_QUEUE_IN_PUMA=true while running under Falcon,
# which has no Puma plugin to read it, so no worker had ever started. Measured
# 2026-08-12: 1670 jobs enqueued, 0 finished, 0 processes, 0 recurring tasks.
# Every check on this box passed throughout — the web app was healthy and the
# jobs simply piled up in a SQLite file nobody queried. Disappearing messages
# had never disappeared and 141,753 guest rows had never been pruned.
#
# Read-only and per app, from the queue database directly rather than by booting
# Rails, so it costs nothing on a 1 vCPU box.
if on_box
  apps.each do |name, metadata|
    next if metadata["standalone"]

    queue_db = "/home/#{name}/app/storage/production_queue.sqlite3"
    next unless File.readable?(queue_db)

    counts = [
      "SELECT COUNT(*) FROM solid_queue_jobs WHERE finished_at IS NULL " \
      "AND (scheduled_at IS NULL OR scheduled_at <= datetime('now'))",
      "SELECT COUNT(*) FROM solid_queue_processes",
    ].map do |sql|
      ok, out = run("/usr/local/bin/sqlite3", "-readonly", queue_db, sql)
      ok ? out.strip.to_i : nil
    end
    pending, workers = counts
    next if pending.nil? || workers.nil?

    # Zero workers is only a fault when there is work waiting, and "waiting"
    # means due. MessageExpirationJob is enqueued with wait_until set to the
    # moment the message should vanish, so a healthy brgen always has a pile of
    # jobs scheduled into the future — 57 of them right after a drain that left
    # nothing overdue. Counting those made this fire permanently on a queue with
    # nothing wrong with it, which is how a check becomes a line people skip.
    if pending.positive? && workers.zero?
      failures << "#{name} queue: #{pending} job(s) due and no registered Solid Queue process " \
                  "— see OPENBSD/etc/rc.d/#{name}_jobs"
    end
  end
end

# Anything resource_guard.sh shed that is still down. Why it matters, and why
# an earlier version of this check could not see it, is in lib/guard_state.rb.
if on_box && File.readable?(Deploy::GuardState::SHED_STATE)
  shed_list = File.read(Deploy::GuardState::SHED_STATE)
  running = ->(svc) { service_running?(svc).first }
  down = Deploy::GuardState.shed_and_down(shed: shed_list, running:)
  failures << down if down
end

up_checks = on_box ? { "master" => 53_187 } : {}
ready_apps.each do |name|
  port = app_ports[name]
  failures << "#{name}: missing port in apps.yml" unless port
  up_checks[name] = port if port && on_box
end

up_checks.each do |name, port|
  ok, out = curl_ok?("http://127.0.0.1:#{port}/up", timeout: 20)
  failures << "#{name} up: #{out.empty? ? "no response on :#{port}" : out}" unless ok

  next unless ready_apps.include?(name)
  next if apps.dig(name, "standalone")

  health_ok, health_out = curl_ok?("http://127.0.0.1:#{port}/health", timeout: 20)
  unless health_ok
    failures << "#{name} health: #{health_out.empty? ? "no response on :#{port}" : health_out}"
    next
  end

  begin
    payload = JSON.parse(health_out)
    failures << "#{name} health: status=#{payload['status']}" if payload["status"] == "unavailable"
    if name == "master"
      deploy = payload["deploy"] || {}
      failures << "master health: deploy.tts_socket false" if deploy["tts_socket"] == false
      failures << "master health: missing deploy.face_runtime_digest" if deploy["face_runtime_digest"].to_s.empty?
      voice = deploy.dig("voice_policy", "single_voice").to_s
      expected_voice = begin
        require "yaml"
        YAML.safe_load_file(File.join(__dir__, "..", "MASTER", "data", "voice.yml"), aliases: true)
            .dig("tts", "single_voice").to_s
      rescue StandardError
        ""
      end
      if expected_voice.empty?
        failures << "master health: could not read MASTER/data/voice.yml tts.single_voice"
      elsif voice != expected_voice
        failures << "master health: voice_policy.single_voice=#{voice.inspect} (expected #{expected_voice})"
      end
      failures << "master health: checks.tts false" if payload.dig("checks", "tts") == false
    end
  rescue JSON::ParserError
    failures << "#{name} health: invalid JSON"
  end
end

if !on_box
  # /etc/relayd.conf is on vm23; the repo copy is deliberately not a substitute
  # (OPENBSD/DECISIONS.md and the relayd entries in RUNBOOK.md).
elsif File.file?("/etc/relayd.conf")
  relayd_conf = File.read("/etc/relayd.conf")
  unless relayd_conf.include?("forward to <master>") && relayd_conf.include?('check http "/up"')
    failures << "relayd: master backend missing http /up check"
  end
  ready_apps.each do |name|
    domain = app_domains[name]
    port = app_ports[name]
    failures << "relayd: missing domain route for #{domain}" if domain && !relayd_conf.include?(domain)
    failures << "relayd: missing backend port for #{name}:#{port}" if port && !relayd_conf.include?("port #{port}")
  end
else
  failures << "relayd: /etc/relayd.conf missing"
end

if options[:public] && on_box
  domains = ["brgen.no"] + ready_apps.filter_map { |name| app_domains[name] }
  domains.uniq.each do |domain|
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    crt = "/etc/ssl/#{domain}.crt"
    failures << "cert missing: #{fullchain} or #{crt}" unless File.exist?(fullchain) || File.exist?(crt)
  end
end

if options[:public]
  https_checks = {
    "ai.brgen.no" => "https://ai.brgen.no/up",
    "brgen.no" => "https://brgen.no/up"
  }
  ready_apps.each do |name|
    domain = app_domains[name]
    https_checks[domain] = "https://#{domain}/up" if domain && domain != "brgen.no"
  end

  https_checks.each do |name, url|
    ok, out = curl_ok?(url)
    failures << "#{name} https: #{out.empty? ? "no response" : out}" unless ok
  end
end

if failures.any?
  if options[:json]
    puts JSON.generate(ok: false, failures: failures)
  else
    warn failures.join("\n")
  end
  exit 1
end

mode = options[:all_ready_apps] ? "all-ready-apps" : "core"
scope = if options[:public_only]
          "public-only (#{ready_apps.size} app(s); nothing on vm23 was checked)"
        elsif options[:public]
          "#{mode}+public"
        else
          mode
        end
if options[:json]
  puts JSON.generate(ok: true, scope: scope, services_checked: required_services, apps_checked: ready_apps)
else
  puts "health check ok (#{scope})"
end
