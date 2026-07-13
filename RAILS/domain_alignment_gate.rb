#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify OPERATOR.sh DNS, domain_registry.rb, and subdomain constants agree on city subdomains.

require "pathname"
require "json"
require_relative "../OPERATOR/lib/utf8"
begin
  require_relative "../RAILS/shared/lib/pub4/deploy_paths"
rescue LoadError
  # ok for minimal ruby env
end

ROOT = Pathname.new(__dir__).join("..").expand_path
OPENBSD = ROOT.join("OPERATOR", "openbsd", "OPERATOR.sh")
REGISTRY = ROOT.join("RAILS", "brgen", "lib", "brgen", "domain_registry.rb")
MASTER_JSON = ROOT.join("OPERATOR", "master.json")
RELAYD = ROOT.join("OPENBSD", "etc", "relayd.conf")
COMMON_SUBAPPS = %w[playlist dating tv takeaway maps messenger].freeze
MASTER_ONLY_SUBAPPS = %w[ai].freeze
NORWEGIAN_PLAYLIST_ALIAS = "spilleliste"

def fail!(failures, message)
  failures << message
end

def parse_openbsd_domains
  text = OPENBSD.read
  block = text[/ALL_DOMAINS=\(\n(.*?)\n\)/m, 1]
  raise "ALL_DOMAINS block not found in #{OPENBSD}" unless block

  block.lines.filter_map do |line|
    line = line.strip
    next if line.empty?

    domain, subs = line.split(":", 2)
    subdomains = subs ? subs.split(",").map(&:strip) : []
    [domain, subdomains]
  end.to_h
end

def parse_registry_entries
  text = REGISTRY.read
  text.scan(/Entry\.new\("([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*:[^,]+,\s*"[^"]+",\s*"([^"]+)"\)/).to_h
end

def parse_registry_subdomains
  text = REGISTRY.read
  {
    tv: extract_constant(text, "TV_SUBDOMAINS"),
    dating: extract_constant(text, "DATING_SUBDOMAINS"),
    playlist: extract_constant(text, "PLAYLIST_SUBDOMAINS"),
    takeaway: extract_constant(text, "TAKEAWAY_SUBDOMAINS"),
    maps: extract_constant(text, "MAPS_SUBDOMAINS"),
    messenger: extract_constant(text, "MESSENGER_SUBDOMAINS")
  }
end

def extract_constant(text, name)
  match = text.match(/#{name}\s*=\s*%w\[([^\]]+)\]/)
  raise "missing #{name} in domain_registry.rb" unless match

  match[1].split(/\s+/)
end

def expected_subdomains_for(domain, marketplace_subdomain)
  subs = [marketplace_subdomain, *COMMON_SUBAPPS]
  subs << NORWEGIAN_PLAYLIST_ALIAS if domain.end_with?(".no")
  subs << "ai" if domain == "brgen.no"
  subs.uniq
end

failures = []
openbsd = parse_openbsd_domains
registry = parse_registry_entries
routes = parse_registry_subdomains

if defined?(Pub4::DeployPaths) && Pub4::DeployPaths.respond_to?(:validate_layout!)
  Pub4::DeployPaths.validate_layout! rescue nil
end

missing_dns = registry.keys - openbsd.keys
fail!(failures, "domain set mismatch: missing DNS #{missing_dns.sort.join(', ')}") if missing_dns.any?

registry.each do |domain, marketplace_subdomain|
  expected = expected_subdomains_for(domain, marketplace_subdomain)
  actual = openbsd.fetch(domain, [])
  missing = expected - actual
  extra = actual - expected
  fail!(failures, "#{domain}: DNS missing #{missing.join(', ')}") if missing.any?
  fail!(failures, "#{domain}: DNS extra #{extra.join(', ')}") if extra.any?
end

%w[tv dating takeaway maps messenger].each do |subapp|
  routes.fetch(subapp.to_sym).each do |label|
    next if COMMON_SUBAPPS.include?(label) || MASTER_ONLY_SUBAPPS.include?(label)

    fail!(failures, "routes #{subapp} lists unknown label #{label}")
  end
end

routes.fetch(:playlist).each do |label|
  next if %w[playlist spilleliste].include?(label)

  fail!(failures, "routes playlist lists unknown label #{label}")
end

# Additional drift checks: master.json (generated from apps.yml but source of truth for deploy)
# and relayd.conf keypairs/forwards.
def parse_master_json
  return {} unless MASTER_JSON.exist?

  data = JSON.parse(MASTER_JSON.read)
  apps = (data["apps"] || []).each_with_object({}) { |a, h| h[a["name"]] = a }
  master = data["master_face"] || {}
  { apps: apps, master: master }
end

def parse_relayd_keypairs
  return [] unless RELAYD.exist?

  text = RELAYD.read
  text.scan(/tls keypair "([^"]+)"/).flatten
end

master = parse_master_json
relayd_keys = parse_relayd_keypairs

# Check main deploy apps from master.json match expected domains/ports from registry + known
if master[:apps] && !master[:apps].empty?
  expected_apps = {
    "amber" => { domain: "amber.brgen.no", port: 61352 },
    "brgen" => { domain: "brgen.no", port: 38182 },
    "bsdports" => { domain: "bsdports.org", port: 47312 }
  }
  expected_apps.each do |name, exp|
    entry = master[:apps][name]
    unless entry
      fail!(failures, "master.json missing #{name}")
      next
    end
    if entry["domain"] != exp[:domain]
      fail!(failures, "master.json domain mismatch for #{name}: #{entry['domain']} != #{exp[:domain]}")
    end
    if entry["port"].to_i != exp[:port]
      fail!(failures, "master.json port mismatch for #{name}: #{entry['port']} != #{exp[:port]}")
    end
  end
  m = master[:master] || {}
  if m["domain"] != "ai.brgen.no" || m["port"].to_i != 53187
    fail!(failures, "master.json master_face mismatch: #{m['domain']}:#{m['port']}")
  end
end

# At least the main domains should have keypairs in relayd
%w[brgen.no ai.brgen.no amber.brgen.no bsdports.org].each do |dom|
  unless relayd_keys.include?(dom)
    fail!(failures, "relayd.conf missing tls keypair for #{dom}")
  end
end

if failures.any?
  warn "Domain alignment failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Domain alignment gate passed (#{registry.size} city domains + master.json/relayd checks)."
