#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "open3"
require "optparse"
require "socket"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
MANIFEST = File.join(__dir__, "crawl_manifest.yml")
APPS_YML = File.join(__dir__, "apps.yml")
MASTER_JSON = File.join(ROOT, "DEPLOY", "master.json")

MASTER_ROOT = File.join(ROOT, "MASTER")

options = { skip_closed: true, public: false, browser: false }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby DEPLOY/rails/crawl_probe.rb [--strict] [--public] [--browser]"
  parser.on("--strict", "Fail when ports are closed (default: skip offline apps)") { options[:skip_closed] = false }
  parser.on("--public", "Crawl public HTTPS URLs from apps.yml domains") { options[:public] = true }
  parser.on("--browser", "Also run Ferrum crawl (MASTER bundle + Chrome)") { options[:browser] = true }
end.parse!

def load_manifest
  YAML.safe_load(File.read(MANIFEST)) || {}
end

def load_apps_yml
  YAML.safe_load(File.read(APPS_YML)).fetch("apps")
end

def load_master_json
  require "json"
  JSON.parse(File.read(MASTER_JSON))
end

def port_open?(host, port, timeout: 0.4)
  Socket.tcp(host, port, connect_timeout: timeout).close
  true
rescue StandardError
  false
end

def fetch(url, timeout: 15)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port,
                  use_ssl: uri.scheme == "https",
                  open_timeout: 8,
                  read_timeout: timeout) do |http|
    http.request(Net::HTTP::Get.new(uri.request_uri))
  end
end

def status_ok?(code, expected)
  allowed = Array(expected).map(&:to_i)
  allowed.include?(code.to_i)
end

def body_ok?(body, expected)
  return true if expected.nil? || expected.to_s.empty?

  text = body.to_s
  if expected.start_with?("regex:")
    Regexp.new(expected.delete_prefix("regex:")).match?(text)
  else
    text.include?(expected)
  end
end

def crawl_target(name, base_url, paths, failures, skips)
  paths.each do |spec|
    path = spec.fetch("path")
    url = "#{base_url}#{path}"
    begin
      res = fetch(url)
      code = res.code.to_i
      unless status_ok?(code, spec.fetch("expect_status", 200))
        failures << "#{name} #{path}: HTTP #{code} (want #{spec.fetch("expect_status", 200)})"
        next
      end
      unless body_ok?(res.body, spec["expect_body"])
        failures << "#{name} #{path}: body missing #{spec["expect_body"].inspect}"
      end
    rescue StandardError => e
      failures << "#{name} #{path}: #{e.class}: #{e.message}"
    end
  end
end

def sync_inventory_failures
  out = []
  yml = load_apps_yml
  json_apps = load_master_json.fetch("apps", [])
  json_by_name = json_apps.to_h { |row| [row["name"].to_s, row] }

  json_by_name.each do |name, row|
    meta = yml[name]
    unless meta
      out << "inventory: #{name} in master.json but missing from apps.yml"
      next
    end
    out << "inventory: #{name} port mismatch json=#{row["port"]} yml=#{meta["port"]}" if row["port"].to_i != meta["port"].to_i
    out << "inventory: #{name} domain mismatch json=#{row["domain"]} yml=#{meta["domain"]}" if row["domain"].to_s != meta["domain"].to_s
  end

  yml.each_key do |name|
    next if json_by_name.key?(name)
    next if %w[privcam pub_attorney mytoonz aight_production_ai multimedia_tts blognet_ai_content].include?(name)
    out << "inventory: #{name} in apps.yml but missing from master.json"
  end
  out
end

def run_browser_crawl(public:)
  browser_script = File.join(__dir__, "crawl_browser.rb")
  args = ["exec", "ruby", browser_script]
  args << "--public" if public
  args << "--strict" unless options[:skip_closed]
  env = { "BUNDLE_WITH" => "test", "BUNDLE_GEMFILE" => File.join(MASTER_ROOT, "Gemfile") }
  out, status = Open3.capture2e(env, "bundle", *args, chdir: MASTER_ROOT)
  puts out unless out.strip.empty?
  status.success? ? [] : ["browser crawl failed"]
rescue StandardError => e
  ["browser crawl: #{e.class}: #{e.message}"]
end

manifest = load_manifest
failures = sync_inventory_failures
skips = []

targets = []
manifest.fetch("master", {}).then do |master|
  targets << ["master", master["port"], master.fetch("paths", [])]
end
manifest.fetch("apps", {}).each do |name, spec|
  targets << [name, spec["port"], spec.fetch("paths", [])]
end

targets.each do |name, port, paths|
  host = "127.0.0.1"
  unless port_open?(host, port)
    if options[:skip_closed]
      skips << "#{name}: port #{port} closed — skipped"
      next
    end
    failures << "#{name}: port #{port} closed"
    next
  end

  base = options[:public] && load_apps_yml[name] ? "https://#{load_apps_yml[name]["domain"]}" : "http://#{host}:#{port}"
  crawl_target(name, base, paths, failures, skips)
end

if options[:browser]
  failures.concat(run_browser_crawl(public: options[:public]))
end

skips.each { |line| puts "crawl: skip — #{line}" }
if failures.empty?
  puts "crawl: clean (#{targets.size} targets, #{skips.size} skipped)"
  exit 0
end

failures.each { |line| warn "crawl: #{line}" }
warn "crawl: #{failures.size} failure(s)"
exit 1