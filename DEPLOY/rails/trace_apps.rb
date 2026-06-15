#!/usr/bin/env ruby
# frozen_string_literal: true

# Deep boot trace per app. Exit 0 only if every app passes every step.
# Prereqs: Ruby 3.4, bundle config path vendor/bundle, libvips on host (brgen/amber).

require "json"
require "open3"
require "yaml"

ROOT = File.expand_path(__dir__)
META = YAML.safe_load_file(File.join(ROOT, "apps.yml")).fetch("apps")
APPS = META.keys
SECRET = "0" * 64

def run(app, *cmd, env: {})
  dir = File.join(ROOT, app)
  full_env = ENV.to_h.merge("BUNDLE_GEMFILE" => File.join(dir, "Gemfile"), "SECRET_KEY_BASE" => SECRET).merge(env)
  out, status = Open3.capture2e(full_env, *cmd, chdir: dir)
  { ok: status.success?, out: out.strip }
end

def step(app, name, *cmd, env: {})
  r = run(app, *cmd, env: env)
  lines = r[:out].lines.map(&:strip).reject(&:empty?)
  err = lines.find { |l| l =~ /(Error|error:|aborted|NoMethod|LoadError|NameError|undefined|Couldn't|FAILED)/ }
  detail = err || lines.last(6).join("\n")
  { step: name, ok: r[:ok], detail: detail }
end

def trace_app(app)
  steps = []
  steps << step(app, "bundle_install", "sh", "-c", "bundle config set --local path vendor/bundle 2>/dev/null; bundle install --quiet")
  steps << step(app, "bundle_check", "bundle", "check")
  db_steps = %w[db:drop db:create db:migrate]
  steps << step(app, "db_prepare_test", "bin/rails", *db_steps,
                env: { "RAILS_ENV" => "test", "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1" })
  steps << step(app, "zeitwerk_test", "bin/rails", "zeitwerk:check", env: { "RAILS_ENV" => "test" })
  steps << step(app, "zeitwerk_production", "bin/rails", "zeitwerk:check", env: { "RAILS_ENV" => "production" })
  steps << step(app, "runner_boot", "bin/rails", "runner",
                "puts([Rails.env, Rails.application.class.name, defined?(::User), defined?(::Session), ApplicationController.included_modules.any?{|m| m.name.include?('Authentication')}, defined?(Shared::Vapid)].join('|'))",
                env: { "RAILS_ENV" => "test" })
  steps << step(app, "routes_up", "bin/rails", "routes", "-g", "up", env: { "RAILS_ENV" => "test" })
  steps << step(app, "rack_up", "bin/rails", "runner",
                "require 'rack/test'; include Rack::Test::Methods; def app; Rails.application; end; get '/up'; puts([last_response.status, last_response.body].join('|'))",
                env: { "RAILS_ENV" => "test" })
  steps << step(app, "test_suite", "bin/rails", "test", env: { "RAILS_ENV" => "test" })
  { app: app, port: META.dig(app, "port"), steps: steps, pass: steps.all? { |s| s[:ok] } }
end

vips = system("which vips >/dev/null 2>&1")
warn "WARN: libvips not in PATH — brgen/amber boot may fail on this host" unless vips

results = APPS.map { |app| trace_app(app) }
puts JSON.pretty_generate(results)
exit(results.all? { |r| r[:pass] } ? 0 : 1)