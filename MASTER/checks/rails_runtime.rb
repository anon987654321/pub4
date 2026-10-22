#!/usr/bin/env ruby
# frozen_string_literal: true

# Subprocess checks are started with system() and do not inherit runner.rb's
# Encoding.default_external; see the same require in release.rb.
require_relative "support/utf8"
require_relative "../lib/io/exec"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "MASTER", "lib"))
require "operator/ruby_runner"
require "operator/environment"

# lib/production: the composite that folds every host check into one verdict
# sorted into host/live/meta/rendered/research/source, and this was the one
# caller the move missed. A subprocess check that cannot load is a check that
# measures nothing, and it fails at require time rather than at a check, so
# the composite reported a failure that named no finding.
require_relative "lib/production"

RAILS_ROOT = File.join(ROOT, "RAILS")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def bundle_cmd
  Operator::RubyRunner.bundle_cmd
end

def rails_cmd
  Operator::RubyRunner.ruby_cmd
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
  stdout, stderr, status = Master::Io::Exec.capture3(env_vars, *cmd, chdir:)
  [status.success?, [stdout, stderr].join.strip]
end

def static_check!
  result = Deploy::ProductionCheck.run(skip_nested: true)
  unless result.ok?
    warn "Production check failures:"
    result.failures.each { |failure| warn "  - #{failure}" }
    return false
  end

  apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")
  puts "Production check passed for #{apps.size} Rails apps."
  true
end

def runtime_ready?
  ok, = run!([bundle_cmd, "version"])
  ok
end

def runtime_check!(apps)
  if Operator::RubyRunner.runtime_check_skipped?
    warn "runtime check skipped: #{Operator::RubyRunner.runtime_skip_reason || 'SKIP_RUNTIME_CHECK=1'}"
    return true
  end

  unless runtime_ready?
    warn "runtime check skipped: #{bundle_cmd} not available"
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
    warn "Rails runtime check failures:"
    failures.each { |failure| warn "  - #{failure}" }
    return false
  end

  puts "Rails runtime check passed for #{apps.size} apps."
  true
end

apps = YAML.safe_load(File.read(APPS_YML)).fetch("apps")
runtime = ARGV.include?("--runtime")

# checks.yml invokes this check with no arguments, so under the runner the runtime
# half never runs and "rails_runtime" is the static production check under a second
# name. Say which half ran. A clean exit here otherwise reads as three apps booted,
# their bundles checked, their routes proved against real controllers and their
# bin/ci green — none of which this run touched.
unless runtime
  warn "rails_runtime: static half only — pass --runtime to boot each app " \
       "(bundle check, db:prepare, dead routes, bin/ci)"
end

exit 1 unless static_check!
exit(runtime && !runtime_check!(apps) ? 1 : 0)
