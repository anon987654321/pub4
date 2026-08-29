#!/usr/bin/env ruby
# frozen_string_literal: true

# Subprocess gates are started with system() and do not inherit runner.rb's
# Encoding.default_external; see the same require in release.rb.
require_relative "../../OPENBSD/lib/utf8"
require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "MASTER", "lib"))
require "pub4/ruby_runner"
require "pub4/environment"
# lib/host/production, not lib/production: the file moved when the gates were
# sorted into host/live/meta/rendered/research/source, and this was the one
# caller the move missed. A subprocess gate that cannot load is a gate that
# measures nothing, and it fails at require time rather than at a check, so
# the composite reported a failure that named no finding.
require_relative "lib/host/production"

RAILS_ROOT = File.join(ROOT, "RAILS")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def bundle_cmd
  Pub4::RubyRunner.bundle_cmd
end

def rails_cmd
  Pub4::RubyRunner.ruby_cmd
end

# Asks the booted app, not routes.rb: a resource declared without only: routes seven actions
# whether or not the controller has them, and Rails answers 404 for the ones it does not.
DEAD_ROUTE_PROBE = <<~RUBY
  skip = %w[rails/ turbo/ action_mailbox/ active_storage/ solid_queue/ mission_control/]
  dead = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller].to_s
    action = route.defaults[:action].to_s
    next if controller.empty? || action.empty? || skip.any? { |prefix| controller.start_with?(prefix) }
    klass = "\#{controller}_controller".camelize.safe_constantize
    next "\#{controller}#\#{action} (no controller)" if klass.nil?
    next if klass.action_methods.include?(action)
    "\#{controller}#\#{action}"
  end.uniq
  abort("dead routes: \#{dead.join(", ")}") if dead.any?
RUBY

def run!(cmd, chdir: ROOT, env: nil)
  env_vars = env ? ENV.to_h.merge(env) : ENV.to_h
  stdout, stderr, status = Open3.capture3(env_vars, *cmd, chdir: chdir)
  [status.success?, [stdout, stderr].join.strip]
end

def static_gate!
  result = Deploy::ProductionGate.run(skip_nested: true)
  unless result.ok?
    warn "Production gate failures:"
    result.failures.each { |failure| warn "  - #{failure}" }
    return false
  end

  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")
  puts "Production gate passed for #{apps.size} Rails apps."
  true
end

def runtime_ready?
  ok, = run!([bundle_cmd, "version"])
  ok
end

def runtime_gate!(apps)
  if Pub4::RubyRunner.runtime_gate_skipped?
    warn "runtime gate skipped: #{Pub4::RubyRunner.runtime_skip_reason || 'SKIP_RUNTIME_GATE=1'}"
    return true
  end

  unless runtime_ready?
    warn "runtime gate skipped: #{bundle_cmd} not available"
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

    ok, out = run!([rails_cmd, "-S", bundle_cmd, "exec", "rails", "runner", DEAD_ROUTE_PROBE],
      chdir: app_dir, env: { "RAILS_ENV" => "test" })
    failures << "#{name}: #{out.lines.grep(/dead routes/).first&.strip || out}" unless ok

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
