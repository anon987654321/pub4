#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPERATOR/lib/gate_result"
require_relative "../OPERATOR/lib/deploy_inventory"

ROOT = File.expand_path("..", __dir__)
RAILS_ROOT = File.join(ROOT, "RAILS")

WATCHED = [
  "app/assets/stylesheets/application.scss",
  "app/assets/stylesheets/**/*.scss",
  "app/javascript/**/*.js",
  "app/javascript/**/*.ts",
].freeze

def source_files(app_dir)
  WATCHED.flat_map do |pattern|
    Dir.glob(File.join(app_dir, pattern))
  end.uniq.select { |path| File.file?(path) }
end

def stale?(app_dir, result, app_name)
  build = File.join(app_dir, "app", "assets", "builds", "application.css")
  sources = source_files(app_dir)
  return if sources.empty?

  unless File.file?(build)
    result.fail("#{app_name}: missing compiled app/assets/builds/application.css")
    return
  end

  build_mtime = File.mtime(build)
  sources.each do |source|
    next if File.mtime(source) <= build_mtime

    rel = source.sub("#{app_dir}/", "")
    result.fail("#{app_name}: stale asset build — #{rel} newer than application.css")
  end

  sw_source = File.join(RAILS_ROOT, "shared", "pwa", "service_worker.js")
  sw_build = File.join(app_dir, "public", "service-worker.js")
  if File.file?(sw_source) && File.file?(sw_build) && File.mtime(sw_source) > File.mtime(sw_build)
    result.fail("#{app_name}: stale service-worker.js relative to shared/pwa/service_worker.js")
  end
end

inventory = Deploy::Inventory.new(root: ROOT)
result = Deploy::GateResult.new

inventory.apps.each do |app|
  app_dir = File.join(RAILS_ROOT, app.name)
  next unless File.directory?(app_dir)

  stale?(app_dir, result, app.name)
end

result.report!("Generated asset freshness gate passed for #{inventory.apps.size} Rails apps.")