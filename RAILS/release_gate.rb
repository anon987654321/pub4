#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"
require_relative "gates/lib/domain_alignment_gate_logic"
require_relative "gates/lib/frontend_production_gate_logic"
require_relative "gates/lib/frontend_auditor_gate_logic"
require_relative "gates/lib/stimulus_components_gate"

ROOT = File.expand_path(__dir__)
APPS = %w[amber brgen bsdports].freeze
FAILURES = []
STEP_TIMEOUT = Integer(ENV.fetch("RELEASE_GATE_STEP_TIMEOUT", "180"))

def command_available?(cmd)
  system("command", "-v", cmd, out: File::NULL, err: File::NULL)
end

def rbenv_version_available?(version)
  return false unless command_available?("rbenv")

  versions, status = Open3.capture2("rbenv", "versions", "--bare")
  status.success? && versions.lines.map(&:strip).include?(version)
end

def ruby_cmd
  return ENV["RUBY_CMD"].split if ENV["RUBY_CMD"].to_s != ""
  return ["ruby34"] if command_available?("ruby34")
  return ["env", "RBENV_VERSION=3.4.9", "rbenv", "exec", "ruby"] if rbenv_version_available?("3.4.9")

  warn "release gate: no ruby34/rbenv 3.4.9 — set RUBY_CMD=ruby34 (using #{RbConfig.ruby})"
  [RbConfig.ruby]
end

def bundle_cmd
  return ENV["BUNDLE_CMD"].split if ENV["BUNDLE_CMD"].to_s != ""
  return ["bundle34"] if command_available?("bundle34")
  return ["env", "RBENV_VERSION=3.4.9", "rbenv", "exec", "bundle"] if rbenv_version_available?("3.4.9")
  return ["bundle"] if command_available?("bundle")

  nil
end

def run(label, command, chdir: ROOT)
  puts "release gate: #{label}"
  stdout = +""
  stderr = +""
  status = nil

  Open3.popen3(*command, chdir: chdir) do |stdin, out, err, wait_thread|
    stdin.close
    stdout_reader = Thread.new { out.read }
    stderr_reader = Thread.new { err.read }

    begin
      Timeout.timeout(STEP_TIMEOUT) do
        status = wait_thread.value
        stdout = stdout_reader.value
        stderr = stderr_reader.value
      end
    rescue Timeout::Error
      begin
        Process.kill("TERM", wait_thread.pid)
      rescue Errno::ESRCH
        # Child exited exactly as the timeout fired.
      end

      sleep 1

      begin
        Process.kill("KILL", wait_thread.pid) if wait_thread.alive?
      rescue Errno::ESRCH
        # Already gone after TERM.
      end

      FAILURES << "#{label}: timed out after #{STEP_TIMEOUT}s (#{command.join(" ")})"
      return
    end
  end

  return if status.success?

  FAILURES << "#{label}: #{stderr.lines.last&.strip || stdout.lines.last&.strip || "exit #{status.exitstatus}"}"
end

RUBY = ruby_cmd
BUNDLE = bundle_cmd

unless BUNDLE
  warn "Release gate skipped: bundle/bundle34 not available. Set BUNDLE_CMD to the intended Bundler executable."
  exit 0
end

APPS.each do |app|
  dir = File.join(ROOT, app)
  run("#{app} dartsass", [*BUNDLE, "exec", *RUBY, "bin/rails", "dartsass:build"], chdir: dir)
  importmap_audit = [
    *BUNDLE, "exec", *RUBY, "-e",
    'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])'
  ]
  run("#{app} importmap", importmap_audit, chdir: dir)
end

%w[
  test/pwa_design_contract_test.rb
  ../MASTER/web/test/pwa_master_contract_test.rb
  test/shared_social_routes_test.rb
  shared/test/services/frontend_auditor_test.rb
  shared/test/lib/pub4/deploy_paths_test.rb
  shared/test/lib/pub4/ci_guard_test.rb
].each do |test|
  run(test, [*RUBY, test], chdir: ROOT)
end

[
  ["domain_alignment_gate", Deploy::DomainAlignmentGate.run],
  ["frontend_production_gate", Deploy::FrontendProductionGate.run],
  ["frontend_auditor", Deploy::FrontendAuditorGate.run],
  ["stimulus_components", Deploy::StimulusComponentsGate.run]
].each do |label, runner|
  puts "release gate: #{label}"
  result = runner.call
  next if result.ok?

  result.failures.each { |failure| FAILURES << "#{label}: #{failure}" }
end

if FAILURES.any?
  warn "Release gate failures:"
  FAILURES.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "Release gate passed (#{APPS.size} apps + shared)."
