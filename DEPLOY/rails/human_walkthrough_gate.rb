#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require_relative "../lib/deploy_inventory"
require_relative "../lib/gate_result"
require_relative "crawl_support"
require_relative "../lib/utf8"

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")

APP_FILES = {
  "amber" => {
    layout: "app/views/layouts/application.html.erb",
    home: "app/views/home/index.html.erb",
    nav: %w[Sign\ in Sign\ up],
  },
  "brgen" => {
    layout: "app/views/layouts/application.html.erb",
    home: "app/views/home/index.html.erb",
    nav: %w[Home Explore Search Sign\ in],
  },
  "bsdports" => {
    layout: "app/views/layouts/application.html.erb",
    home: "app/views/ports/index.html.erb",
    nav: %w[Ports Categories Maintainers Sign\ in],
  },
  "hjerterom" => {
    layout: "app/views/layouts/application.html.erb",
    home: "app/views/home/index.html.erb",
    nav: %w[Mat Ressurser Fellesskap Drift Logg\ inn],
  },
}.freeze

def read_app_file(app, relative)
  File.read(File.join(RAILS_ROOT, app, relative))
end

def source_checks(result, app)
  files = APP_FILES.fetch(app.name)
  layout = read_app_file(app.name, files.fetch(:layout))
  home = read_app_file(app.name, files.fetch(:home))

  result.fail("#{app.name}: layout needs skip link to main content") unless layout.include?('href="#main-content"')
  result.fail("#{app.name}: layout needs main-content landmark") unless layout.include?('id="main-content"')
  result.fail("#{app.name}: home needs data-visitor-orientation marker") unless home.include?("data-visitor-orientation")

  files.fetch(:nav).each do |label|
    result.fail("#{app.name}: primary visitor nav missing #{label}") unless layout.include?(label) || home.include?(label)
  end

  if app.name == "brgen"
    result.fail("brgen: sidebar search must submit to global_search_path") unless layout.include?("form_with url: global_search_path")
    %w[Home Explore\ communities Posts Messages Nearby].each do |label|
      result.fail("brgen: mobile tab missing aria label #{label}") unless layout.include?("aria: { label: \"#{label.tr('\\', '')}\" }")
    end
  end
end

def nokogiri_available?
  return @nokogiri_available if defined?(@nokogiri_available)

  require "nokogiri"
  @nokogiri_available = true
rescue LoadError
  @nokogiri_available = false
end

def live_checks(result, app)
  return result.warn("#{app.name}: live walkthrough skipped; port #{app.port} closed") unless CrawlSupport.port_open?("127.0.0.1", app.port)

  response = CrawlSupport.fetch("http://127.0.0.1:#{app.port}/")
  unless response.code.to_i.between?(200, 399)
    result.fail("#{app.name}: visitor reached HTTP #{response.code} at /")
    return
  end

  html = response.body.to_s
  %w[Exception Routing\ Error].each do |bad|
    result.fail("#{app.name}: visitor saw #{bad.tr('\\', '')}") if html.include?(bad.tr("\\", ""))
  end

  unless nokogiri_available?
    result.warn("#{app.name}: live HTML structure checks skipped (nokogiri unavailable; source checks still ran)")
    return
  end

  doc = Nokogiri::HTML5(html)
  result.fail("#{app.name}: rendered page missing title") if doc.at("title").to_s.strip.empty?
  result.fail("#{app.name}: rendered page missing main landmark") unless doc.at("main")
  result.fail("#{app.name}: rendered page missing primary navigation") unless doc.at('nav[aria-label*="navigation" i], nav[aria-label*="Primary" i], nav')
  result.fail("#{app.name}: rendered page missing visible heading") unless doc.at("h1, h2")
  result.fail("#{app.name}: rendered page has too few navigable links") if doc.css("a[href]").size < 3

  doc.css('input[type="search"]').each do |input|
    next if input.ancestors("form").any?

    label = input["aria-label"] || input["placeholder"] || "unlabelled search"
    result.fail("#{app.name}: search input is not inside a form (#{label})")
  end
end

inventory = Deploy::Inventory.new(root: ROOT)
result = Deploy::GateResult.new

inventory.apps.each do |app|
  source_checks(result, app)
  live_checks(result, app)
end

result.report!("Human walkthrough gate passed for #{inventory.apps.size} Rails apps.")
