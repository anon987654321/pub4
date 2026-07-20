#!/usr/bin/env ruby
# frozen_string_literal: true

# HTTP crawl + inventory sync — optional Ferrum via --browser.

require "open3"
require "optparse"
require "timeout"
require_relative "crawl_support"

MASTER_ROOT = File.join(CrawlSupport::ROOT, "MASTER")

def run_browser_crawl(public:, skip_closed:)
  browser_script = File.join(__dir__, "crawl_browser.rb")
  args = ["exec", "ruby", browser_script]
  args << "--public" if public
  args << "--strict" unless skip_closed
  env = { "BUNDLE_WITH" => "test", "BUNDLE_GEMFILE" => File.join(MASTER_ROOT, "Gemfile") }
  out, status = Timeout.timeout(60) { Open3.capture2e(env, "bundle", *args, chdir: MASTER_ROOT) }
  puts out unless out.strip.empty?
  status.success? ? [] : ["browser crawl failed"]
rescue StandardError => e
  ["browser crawl: #{e.class}: #{e.message}"]
end

options = { skip_closed: true, public: false, browser: false }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby RAILS/crawl_probe.rb [--strict] [--public] [--browser]"
  parser.on("--strict", "Fail when ports are closed (default: skip offline apps)") { options[:skip_closed] = false }
  parser.on("--public", "Crawl public HTTPS URLs from apps.yml domains") { options[:public] = true }
  parser.on("--browser", "Also run Ferrum crawl (MASTER bundle + Chrome)") { options[:browser] = true }
end.parse!

manifest = CrawlSupport.load_manifest
failures = CrawlSupport.sync_inventory_failures
skips = []
apps = CrawlSupport.load_apps_yml

targets = []
manifest.fetch("master", {}).then { |master| targets << ["master", master["port"], master.fetch("paths", [])] }
manifest.fetch("apps", {}).each { |name, spec| targets << [name, spec["port"], spec.fetch("paths", [])] }

targets.each do |name, port, paths|
  host = "127.0.0.1"
  unless CrawlSupport.port_open?(host, port)
    if options[:skip_closed]
      skips << "#{name}: port #{port} closed — skipped"
      next
    end
    failures << "#{name}: port #{port} closed"
    next
  end

  base = CrawlSupport.base_url(name, port, apps, public: options[:public])
  CrawlSupport.crawl_target(name, base, paths, failures)
end

failures.concat(run_browser_crawl(public: options[:public], skip_closed: options[:skip_closed])) if options[:browser]

skips.each { |line| puts "crawl: skip — #{line}" }
if failures.empty?
  puts "crawl: clean (#{targets.size} targets, #{skips.size} skipped)"
  exit 0
end

failures.each { |line| warn "crawl: #{line}" }
warn "crawl: #{failures.size} failure(s)"
exit 1
