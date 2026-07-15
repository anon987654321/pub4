#!/usr/bin/env ruby
# frozen_string_literal: true

# encoding: utf-8

require "json"
require "open3"
require "optparse"
require "yaml"
require_relative "lib/utf8"

ROOT = File.expand_path("..", __dir__)
APPS_YML = File.join(ROOT, "RAILS", "apps.yml")

options = {
  all_ready_apps: false,
  public: false,
  core: false,
  json: false,
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby34 OPENBSD/health_check.rb [--core|--all-ready-apps] [--public] [--json]"
  parser.on("--core", "Check only core infrastructure plus brgen/master") { options[:core] = true }
  parser.on("--all-ready-apps", "Require every app listed in RAILS/apps.yml") { options[:all_ready_apps] = true }
  parser.on("--public", "Check public HTTPS endpoints, cert files, and externally-routed names") { options[:public] = true }
  parser.on("--json", "Emit machine-readable JSON on success") { options[:json] = true }
end.parse!

options[:all_ready_apps] = false if options[:core]

failures = []

def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip]
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
        "standalone" => false
      }
    ]
  end
  load_standalone_apps.each { |name, metadata| merged[name] = metadata }
  merged
rescue StandardError => e
  warn "apps.yml unreadable: #{e.class}: #{e.message}"
  load_standalone_apps
end

def load_standalone_apps
  path = File.join(ROOT, "OPENBSD", "master.json")
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
  warn "master.json standalone_apps unreadable: #{e.class}: #{e.message}"
  {}
end

def service_running?(service)
  ok, out = run(*privileged("/usr/sbin/rcctl", "check", service))
  [ok && out.include?("(ok)"), out]
end

def curl_ok?(url, timeout: 25)
  run("/usr/local/bin/curl", "-fsS", "--max-time", timeout.to_s, url)
end

apps = load_apps
app_ports = apps.transform_values { |metadata| metadata.fetch("port") }
app_domains = apps.transform_values { |metadata| metadata.fetch("domain") }

core_apps = %w[brgen]
ready_apps = options[:all_ready_apps] ? app_ports.keys.sort : core_apps

core_services = %w[nsd httpd relayd smtpd master] + core_apps
required_services = (core_services + ready_apps).uniq

required_services.each do |service|
  running, out = service_running?(service)
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless running
end

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
  failures << "dns: no local SOA (nsd #{nsd_out.strip})" unless nsd_ok && nsd_out.include?("(ok)")
end

up_checks = { "master" => 53_187 }
ready_apps.each do |name|
  port = app_ports[name]
  failures << "#{name}: missing port in apps.yml" unless port
  up_checks[name] = port if port
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
      failures << "master health: voice_policy.single_voice=#{voice.inspect} (expected pernille)" if voice != "pernille"
      failures << "master health: checks.tts false" if payload.dig("checks", "tts") == false
    end
  rescue JSON::ParserError
    failures << "#{name} health: invalid JSON"
  end
end

if File.file?("/etc/relayd.conf")
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

if options[:public]
  domains = ["brgen.no"] + ready_apps.filter_map { |name| app_domains[name] }
  domains.uniq.each do |domain|
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    crt = "/etc/ssl/#{domain}.crt"
    failures << "cert missing: #{fullchain} or #{crt}" unless File.exist?(fullchain) || File.exist?(crt)
  end
end

if options[:public]
  https_checks = {
    "ai.brgen.no" => "https://ai.brgen.no/",
    "brgen.no" => "https://brgen.no/up"
  }
  ready_apps.each do |name|
    domain = app_domains[name]
    https_checks[domain] = "https://#{domain}/up" if domain && domain != "brgen.no"
  end

  https_checks.each do |name, url|
    ok, out = curl_ok?(url, timeout: 25)
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
scope = options[:public] ? "#{mode}+public" : mode
if options[:json]
  puts JSON.generate(ok: true, scope: scope, services_checked: required_services, apps_checked: ready_apps)
else
  puts "health check ok (#{scope})"
end
