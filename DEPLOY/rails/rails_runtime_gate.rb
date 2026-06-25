#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def bundle_cmd
  return ENV["BUNDLE_CMD"] if ENV["BUNDLE_CMD"].to_s != ""
  return "bundle34" if RUBY_PLATFORM.include?("openbsd")
  "bundle"
end

def rails_cmd
  return ENV["RAILS_CMD"] if ENV["RAILS_CMD"].to_s != ""
  return "ruby34" if RUBY_PLATFORM.include?("openbsd") && File.executable?("/usr/local/bin/ruby34")
  "ruby"
end

def run!(cmd, chdir: ROOT, env: nil)
  env_vars = env ? ENV.to_h.merge(env) : ENV.to_h
  stdout, stderr, status = Open3.capture3(env_vars, *cmd, chdir: chdir)
  [status.success?, [stdout, stderr].join.strip]
end

def static_gate!
  ok, out = run!(["ruby", File.join(RAILS_ROOT, "check_production_gate.rb")])
  puts out
  ok
end

def runtime_ready?
  ok, = run!([bundle_cmd, "version"])
  ok
end

def runtime_gate!(apps)
  return true if ENV["SKIP_RUNTIME_GATE"] == "1"

  unless runtime_ready?
    warn "runtime gate skipped: #{bundle_cmd} not available (set SKIP_RUNTIME_GATE=1 to silence)"
    return true
  end

  failures = []
  apps.each do |name, _metadata|
    app_dir = File.join(RAILS_ROOT, name)
    next unless File.directory?(app_dir)

    ok, out = run!([bundle_cmd, "check"], chdir: app_dir)
    failures << "#{name}: bundle check failed — #{out}" unless ok

    ok, out = run!([rails_cmd, "-S", bundle_cmd, "exec", "rails", "db:prepare"],
      chdir: app_dir, env: { "RAILS_ENV" => "test" })
    failures << "#{name}: db:prepare failed — #{out}" unless ok

    ci = File.join(app_dir, "bin", "ci")
    next unless File.executable?(ci)

    ok, out = run!([ci], chdir: app_dir, env: { "PUB4_CI_GUARD" => "1" })
    failures << "#{name}: bin/ci failed — #{out.lines.first(8).join}" unless ok
  end

  if failures.any?
    warn "Rails runtime gate failures:"
    failures.each { |failure| warn "  - #{failure}" }
    return false
  end

  puts "Rails runtime gate passed for #{apps.size} apps."
  true
end

apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")
runtime = ARGV.include?("--runtime")

exit 1 unless static_gate!
exit(runtime && !runtime_gate!(apps) ? 1 : 0)