#!/usr/bin/env ruby
# frozen_string_literal: true

# runner.rb sets this for itself, but it starts the three subprocess gates with
# system(), and a fresh process does not inherit Encoding.default_external. Under
# the C locale that OPENBSD/integrity_gate.rb deliberately uses, reading UTF-8
# source raised `invalid byte sequence in US-ASCII` from inside
# domain_alignment.rb — a crash that could not happen when the same gate class
# ran in-process.
require_relative "../../OPENBSD/lib/utf8"
require "open3"
require "rbconfig"
require "timeout"
# From the manifest, not from four hardcoded paths.
#
# All four moved into lib/host and lib/source, gates.yml moved with them, and
# these four lines did not — so this file raised LoadError on
# lib/domain_alignment before reaching its first gate. Nothing in-process
# noticed: release is one of the gates runner.rb starts with system(), so a
# subprocess that dies on require reads as a failing gate rather than a missing
# file, and `constitutional_scan` was wired under release earlier tonight on the
# assumption it ran at all.
#
# gates.yml is where a gate's require lives — RAILS/CLAUDE.md calls it declared
# once — so reading it here is what stops the next move breaking this file again.
# Keyed on the classes this file names, not on `covered_by: release`: it also
# runs frontend_auditor, which belongs to layout_suite, so requiring its own
# composite loaded three of the four and left the fourth undefined at line 152.
require "yaml"
RELEASE_GATE_CLASSES = %w[
  Deploy::DomainAlignmentGate
  Deploy::FrontendAuditorGate
  Deploy::FrontendProductionGate
  Deploy::StimulusComponentsGate
].freeze

YAML.load_file(File.join(__dir__, "gates.yml")).then { |manifest| manifest["gates"] || manifest }
    .each_value.select { |row| row.is_a?(Hash) && RELEASE_GATE_CLASSES.include?(row["class"]) }
    .each { |row| require_relative row.fetch("require") }

ROOT = File.expand_path("..", __dir__)
APPS = %w[amber brgen bsdports].freeze
FAILURES = [] # scan: intentional — this script's accumulator, appended to by every step below
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

# A missing Bundler used to `exit 0` on the whole gate — the exact shape
# GateResult's third state exists to prevent (OPENBSD/data/debt.yml:
# rails_gates_not_wired, "release_gate exits 0 when bundler is missing"). Two
# thirds of this gate needs no Bundler at all: eight plain-ruby contract tests
# and four in-process gate classes. Those still run; only the per-app dartsass
# and importmap steps are recorded as unchecked.
UNCHECKED = [] # scan: intentional — accumulator, as FAILURES above

if BUNDLE
  APPS.each do |app|
    dir = File.join(ROOT, app)
    run("#{app} dartsass", [*BUNDLE, "exec", *RUBY, "bin/rails", "dartsass:build"], chdir: dir)
    importmap_audit = [
      *BUNDLE, "exec", *RUBY, "-e",
      'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])'
    ]
    run("#{app} importmap", importmap_audit, chdir: dir)
  end
else
  UNCHECKED << "bundle/bundle34 not on PATH — #{APPS.size} app dartsass + importmap audit step(s) skipped " \
               "(set BUNDLE_CMD to the intended Bundler executable)"
end

%w[
  test/pwa_design_contract_test.rb
  test/design_contract_test.rb
  ../MASTER/web/test/pwa_master_contract_test.rb
  test/shared_social_routes_test.rb
  test/i18n_resolution_test.rb
  shared/test/services/frontend_auditor_test.rb
  shared/test/services/sitemap_builder_test.rb
  shared/test/services/account_exporter_test.rb
  shared/test/lib/design_tokens_test.rb
  shared/test/lib/pub4/deploy_paths_test.rb
  shared/test/lib/pub4/ci_guard_test.rb
].each do |test|
  run(test, [*RUBY, test], chdir: ROOT)
end

[
  ["domain_alignment_gate", Deploy::DomainAlignmentGate],
  ["frontend_production_gate", Deploy::FrontendProductionGate],
  ["frontend_auditor", Deploy::FrontendAuditorGate],
  ["stimulus_components", Deploy::StimulusComponentsGate],
].each do |label, gate|
  puts "release gate: #{label}"
  result = gate.run
  next if result.ok?

  result.failures.each { |failure| FAILURES << "#{label}: #{failure}" }
end

unless UNCHECKED.empty?
  warn "Not checked:"
  UNCHECKED.each { |reason| warn "  - #{reason}" }
end

if FAILURES.any?
  warn "Release gate failures:"
  FAILURES.each { |failure| warn "  - #{failure}" }
  exit 1
end

if UNCHECKED.any? && %w[1 true yes on].include?(ENV["GATE_STRICT_INCONCLUSIVE"].to_s.strip.downcase)
  warn "Release gate: GATE_STRICT_INCONCLUSIVE is set and #{UNCHECKED.size} precondition(s) were missing."
  exit 1
end

if UNCHECKED.any?
  puts "Release gate passed what it could run (#{APPS.size} apps + shared, #{UNCHECKED.size} step group(s) skipped)."
else
  puts "Release gate passed (#{APPS.size} apps + shared)."
end
