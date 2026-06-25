#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path(__dir__)
APPS = %w[amber baibl blognet brgen bsdports hjerterom].freeze
FAILURES = []

def run(label, command, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(command, chdir: chdir)
  return if status.success?

  FAILURES << "#{label}: #{stderr.lines.last&.strip || stdout.lines.last&.strip || "exit #{status.exitstatus}"}"
end

APPS.each do |app|
  dir = File.join(ROOT, app)
  run("#{app} dartsass", "RBENV_VERSION=3.4.9 bundle exec rails dartsass:build", chdir: dir)
  importmap_audit = 'RBENV_VERSION=3.4.9 bundle exec ruby -e ' \
    '"require \"./config/environment\"; require \"importmap/commands\"; Importmap::Commands.start(%w[audit])"'
  run("#{app} importmap", importmap_audit, chdir: dir)
end

%w[
  test/pwa_design_contract_test.rb
  test/shared_social_routes_test.rb
  shared/test/services/frontend_auditor_test.rb
].each do |test|
  run(test, "RBENV_VERSION=3.4.9 ruby #{test}", chdir: ROOT)
end

run("frontend_production_gate", "ruby frontend_production_gate.rb", chdir: ROOT)

run("frontend_auditor", "RBENV_VERSION=3.4.9 ruby frontend_auditor_gate.rb", chdir: ROOT)

if FAILURES.any?
  warn "Release gate failures:"
  FAILURES.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Release gate passed (#{APPS.size} apps + shared)."