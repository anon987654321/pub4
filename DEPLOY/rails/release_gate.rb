#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path(__dir__)
APPS = %w[amber baibl blognet brgen bsdports hjerterom].freeze
FAILURES = []

RUBY_PREFIX = if ENV["RBENV_VERSION"]
                "RBENV_VERSION=#{ENV["RBENV_VERSION"]} "
              elsif system("which bundle34", out: File::NULL, err: File::NULL)
                ""
              else
                "RBENV_VERSION=3.4.9 "
              end

def run(label, command, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(command, chdir: chdir)
  return if status.success?

  FAILURES << "#{label}: #{stderr.lines.last&.strip || stdout.lines.last&.strip || "exit #{status.exitstatus}"}"
end

APPS.each do |app|
  dir = File.join(ROOT, app)
  run("#{app} dartsass", "#{RUBY_PREFIX}bundle exec rails dartsass:build", chdir: dir)
  importmap_audit = "#{RUBY_PREFIX}bundle exec ruby -e " \
    '"require \"./config/environment\"; require \"importmap/commands\"; Importmap::Commands.start(%w[audit])"'
  run("#{app} importmap", importmap_audit, chdir: dir)
end

%w[
  test/pwa_design_contract_test.rb
  test/shared_social_routes_test.rb
  shared/test/services/frontend_auditor_test.rb
  shared/test/lib/pub4/deploy_paths_test.rb
  shared/test/lib/pub4/ci_guard_test.rb
].each do |test|
  run(test, "#{RUBY_PREFIX}ruby #{test}", chdir: ROOT)
end

run("domain_alignment_gate", "ruby domain_alignment_gate.rb", chdir: ROOT)

run("frontend_production_gate", "ruby frontend_production_gate.rb", chdir: ROOT)

run("frontend_auditor", "#{RUBY_PREFIX}ruby frontend_auditor_gate.rb", chdir: ROOT)

if FAILURES.any?
  warn "Release gate failures:"
  FAILURES.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Release gate passed (#{APPS.size} apps + shared)."