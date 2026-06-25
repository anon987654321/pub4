#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "yaml"

RUBY_BIN = RbConfig.ruby

ROOT = File.expand_path("../..", __dir__)
RAILS_ROOT = File.join(ROOT, "DEPLOY", "rails")
APPS_YML = File.join(RAILS_ROOT, "apps.yml")

def fail!(failures, message)
  failures << message
end

def active_lines(path)
  File.readlines(path, chomp: true).reject { |line| line.strip.start_with?("#") }
end

def git_ls_files(pattern)
  stdout, status = Open3.capture2("git", "-C", ROOT, "ls-files", pattern)
  status.success? ? stdout.lines.map(&:chomp).reject(&:empty?) : []
end

def load_yaml(path)
  YAML.safe_load(File.read(path))
end

failures = []
warnings = []
apps = load_yaml(APPS_YML).fetch("apps")
env_sample = File.join(RAILS_ROOT, "env.sample")

tracked_master_keys = git_ls_files("DEPLOY/rails/*/config/master.key")
fail!(failures, "tracked Rails master keys: #{tracked_master_keys.join(', ')}") if tracked_master_keys.any?
fail!(failures, "missing shared DEPLOY/rails/env.sample") unless File.file?(env_sample)

apps.each do |name, metadata|
  app_dir = File.join(RAILS_ROOT, name)
  next unless File.directory?(app_dir)

  production = File.join(app_dir, "config", "environments", "production.rb")
  gemfile = File.join(app_dir, "Gemfile")
  ci_bin = File.join(app_dir, "bin", "ci")
  deploy_script = File.join(ROOT, metadata.fetch("deploy_script"))
  domain = metadata.fetch("domain")
  app_failures = []

  unless File.file?(production)
    fail!(failures, "#{name}: missing config/environments/production.rb")
    next
  end

  baseline = File.join(RAILS_ROOT, "shared", "config", "environments", "production_baseline.rb")
  prod_active = active_lines(production)
  prod_active += active_lines(baseline) if File.read(production).include?("production_baseline")
  fail!(app_failures, "production config still has active example.com placeholder") if prod_active.any? { |line| line.include?("example.com") }
  fail!(app_failures, "production config must trust relayd with config.assume_ssl = true") unless prod_active.any? { |line| line.match?(/\bconfig\.assume_ssl\s*=\s*true\b/) }
  fail!(app_failures, "TLS terminates at relayd; do not enable config.force_ssl in Rails") if prod_active.any? { |line| line.match?(/\bconfig\.force_ssl\s*=\s*true\b/) }
  mailer_ok = prod_active.any? { |line| line.include?(domain) && (line.include?("action_mailer.default_url_options") || line.include?("mailer_host:")) }
  fail!(app_failures, "production mailer host must use #{domain}") unless mailer_ok
  hosts_ok = prod_active.any? { |line| line.include?(domain) && (line.include?("config.hosts") || line.include?("hosts:")) }
  fail!(app_failures, "production config.hosts must include #{domain}") unless hosts_ok
  fail!(app_failures, "production host_authorization must keep /up available") unless prod_active.any? { |line| line.include?("config.host_authorization") && line.include?('"/up"') }
  fail!(app_failures, "Solid Cache must be enabled") unless prod_active.any? { |line| line.match?(/\bconfig\.cache_store\s*=\s*:solid_cache_store\b/) }
  fail!(app_failures, "Solid Queue must be enabled") unless prod_active.any? { |line| line.match?(/\bconfig\.active_job\.queue_adapter\s*=\s*:solid_queue\b/) }

  if File.file?(gemfile)
    gemfile_text = File.read(gemfile)
    warnings << "#{name}: Gemfile has no explicit ruby version" unless gemfile_text.match?(/^ruby\s+/)
    fail!(app_failures, "Gemfile must target Rails 8.1") unless gemfile_text.match?(/^gem ['"]rails['"], ['"]~> 8\.1/)
  else
    fail!(app_failures, "missing Gemfile")
  end

  ci_config = File.join(app_dir, "config", "ci.rb")
  shared_ci = File.join(RAILS_ROOT, "shared", "config", "ci.rb")
  if File.file?(ci_bin)
    ci_parts = [File.read(ci_bin)]
    ci_parts << File.read(ci_config) if File.file?(ci_config)
    ci_parts << File.read(shared_ci) if File.file?(shared_ci) && ci_parts.join.include?("shared/config/ci")
    ci_text = ci_parts.join("\n")
    fail!(app_failures, "bin/ci must be executable") unless File.executable?(ci_bin)
    fail!(app_failures, "bin/ci must run RuboCop") unless ci_text.include?("rubocop")
    fail!(app_failures, "bin/ci must run bundler-audit") unless ci_text.include?("bundler-audit")
    fail!(app_failures, "bin/ci must run Brakeman") unless ci_text.include?("brakeman")
    fail!(app_failures, "bin/ci must run Rails tests") unless ci_text.include?("rails") && ci_text.include?("test")
  else
    fail!(app_failures, "missing bin/ci")
  end

  if File.file?(deploy_script)
    deploy_text = File.read(deploy_script)
    fail!(app_failures, "deploy script must require ruby34") unless deploy_text.include?("need_cmd ruby34")
    fail!(app_failures, "deploy script must configure relayd for #{domain}") unless deploy_text.include?("relayd_add_relay")
  else
    fail!(app_failures, "missing deploy script #{metadata.fetch('deploy_script')}")
  end

  failures.concat(app_failures.map { |failure| "#{name}: #{failure}" })
end

if warnings.any?
  warn "Production gate warnings:"
  warnings.each { |warning| warn "  - #{warning}" }
end

master_assets_gate = File.join(RAILS_ROOT, "master_web_assets_gate.rb")
if File.file?(master_assets_gate)
  stdout, status = Open3.capture2(RUBY_BIN, master_assets_gate, chdir: ROOT)
  print stdout
  fail!(failures, "MASTER/web assets gate failed") unless status.success?
else
  fail!(failures, "missing DEPLOY/rails/master_web_assets_gate.rb")
end

if failures.any?
  warn "Production gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Production gate passed for #{apps.size} Rails apps."
