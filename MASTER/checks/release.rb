#!/usr/bin/env ruby
# frozen_string_literal: true

# runner.rb sets this for itself, but it starts the three subprocess checks with
# system(), and a fresh process does not inherit Encoding.default_external. Under
# the C locale that OPENBSD/checks/integrity_check.rb deliberately uses, reading UTF-8
# source raised `invalid byte sequence in US-ASCII` from inside
# domain_alignment.rb — a crash that could not happen when the same check class
# ran in-process.
require_relative "support/utf8"

require "rbconfig"
require_relative "../../MASTER/lib/operator/ruby_runner"
require_relative "../lib/io/exec"

# From the manifest, not from four hardcoded paths.
#
# All four moved into lib/host and lib/source, checks.yml moved with them, and
# these four lines did not — so this file raised LoadError on
# lib/domain_alignment before reaching its first check. Nothing in-process
# noticed: release is one of the checks runner.rb starts with system(), so a
# subprocess that dies on require reads as a failing check rather than a missing
# file, and `constitutional_scan` was wired under release earlier tonight on the
# assumption it ran at all.
#
# checks.yml is where a check's require lives — RAILS/CLAUDE.md calls it declared
# once — so reading it here is what stops the next move breaking this file again.
# Keyed on the classes this file names, not on `covered_by: release`: it also
# runs frontend_auditor, which belongs to layout_suite, so requiring its own
# composite loaded three of the four and left the fourth undefined at line 152.
require "yaml"

RELEASE_CHECK_CLASSES = %w[
  Deploy::DomainAlignmentCheck
  Deploy::FrontendAuditorCheck
  Deploy::FrontendProductionCheck
  Deploy::SecurityHeadersSourceCheck
  Deploy::StimulusComponentsCheck
].freeze

manifest_path = File.join(__dir__, "checks.yml")
repo_root = File.expand_path("../../..", manifest_path)
YAML.safe_load_file(manifest_path, aliases: true).then { |manifest| manifest["checks"] || manifest }
    .each_value.select { |row| row.is_a?(Hash) && RELEASE_CHECK_CLASSES.include?(row["class"]) }
    .each do |row|
      require_path = row.fetch("require")

      # Paths starting with a known tree (MASTER, RAILS, OPENBSD) are repo-relative.
      # Others are RAILS-relative.
      full_path = if require_path.match?(%r{\A(?:MASTER|RAILS|OPENBSD)/})
                    File.join(repo_root, require_path)
                  else
                    File.join(__dir__, require_path)
                  end
      require full_path
    end

# RAILS/, where the apps, the shared engine and the contract tests live.
ROOT = File.expand_path("../../RAILS", __dir__)
APPS = %w[amber brgen bsdports].freeze
FAILURES = [] # scan: intentional — this script's accumulator, appended to by every step below
STEP_TIMEOUT = Integer(ENV.fetch("RELEASE_CHECK_STEP_TIMEOUT", "180"))

def command_available?(cmd)
  system("command", "-v", cmd, out: File::NULL, err: File::NULL)
end

def ruby_cmd
  return ENV["RUBY_CMD"].split if ENV["RUBY_CMD"].to_s != ""

  [Operator::RubyRunner.ruby_cmd]
end

def bundle_cmd
  return ENV["BUNDLE_CMD"].split if ENV["BUNDLE_CMD"].to_s != ""

  path = Operator::RubyRunner.bundle_cmd
  command_available?(path) ? [path] : nil
end

def run(label, command, chdir: ROOT, env: {})
  puts "release check: #{label}"
  begin
    stdout, stderr, status = Master::Io::Exec.capture3(
      env, *command, chdir:, timeout: STEP_TIMEOUT, raise_on_timeout: true
    )
  rescue Master::Io::Exec::TimeoutError
    FAILURES << "#{label}: timed out after #{STEP_TIMEOUT}s (#{command.join(" ")})"

    return
  end

  return if status.success?

  FAILURES << "#{label}: #{stderr.lines.last&.strip || stdout.lines.last&.strip || "exit #{status.exitstatus}"}"
end

RUBY = ruby_cmd
BUNDLE = bundle_cmd

# A missing Bundler used to `exit 0` on the whole check — the exact shape
# CheckResult's third state exists to prevent (the old backlog:
# rails_checks_not_wired, "release_check exits 0 when bundler is missing"). Two
# thirds of this check needs no Bundler at all: eight plain-ruby contract tests
# and four in-process check classes. Those still run; only the per-app dartsass
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
  UNCHECKED << "bundle not on PATH — #{APPS.size} app dartsass + importmap audit step(s) skipped " \
               "(set BUNDLE_CMD to the intended Bundler executable)"
end

# Every __shared/test file, globbed so a new one cannot fall out of a list.
#
# The engine has no runner of its own: shared/ has no Gemfile and no
# application, because it is mounted by path into each app, so this is the
# only place its tests run. A file that requires test_helper needs a booted
# app and runs through brgen's bundle; the rest run under bare ruby, beside the
# RAILS contract tests that guard the engine's wiring.
BOOTED_SHARED_TESTS, BARE_SHARED_TESTS =
  Dir.glob("__shared/test/**/*_test.rb", base: ROOT).sort
     .partition { |test| File.read(File.join(ROOT, test)).match?(/^require "test_helper"/) }

[
  "test/pwa_design_contract_test.rb",
  "test/design_contract_test.rb",
  "master/test/pwa_master_contract_test.rb",
  "test/shared_social_routes_test.rb",
  "test/i18n_resolution_test.rb",
  ].each do |test|
  run(test, [*RUBY, test], chdir: ROOT)
end

# The engine's bare tests load active_support, active_record and shared/*, which only a
# bundle puts on the load path (Rails comes from a git source, so no ruby has it installed).
# They run under brgen's, the app that mounts the engine.
BARE_SHARED_TESTS.each do |test|
  if BUNDLE
    run(test, [*BUNDLE, "exec", *RUBY, test], chdir: ROOT,
        env: { "BUNDLE_GEMFILE" => File.join(ROOT, "brgen", "Gemfile") })
  else
    UNCHECKED << "bundle not on PATH — #{test} skipped (it needs the bundle for active_support)"
  end
end

if BUNDLE
  run("shared booted tests", [*BUNDLE, "exec", *RUBY, "bin/rails", "test",
                              *BOOTED_SHARED_TESTS.map { |test| "../#{test}" }],
      chdir: File.join(ROOT, "brgen"))
else
  UNCHECKED << "bundle not on PATH — #{BOOTED_SHARED_TESTS.join(", ")} skipped (they need a booted app)"
end

[
  ["domain_alignment_check", Deploy::DomainAlignmentCheck],
  ["frontend_production_check", Deploy::FrontendProductionCheck],
  ["security_headers_source", Deploy::SecurityHeadersSourceCheck],
  ["frontend_auditor", Deploy::FrontendAuditorCheck],
  ["stimulus_components", Deploy::StimulusComponentsCheck],
].each do |label, check|
  puts "release check: #{label}"
  result = check.run
  next if result.ok?

  result.failures.each { |failure| FAILURES << "#{label}: #{failure}" }
end

unless UNCHECKED.empty?
  warn "Not checked:"
  UNCHECKED.each { |reason| warn "  - #{reason}" }
end

if FAILURES.any?
  warn "Release check failures:"
  FAILURES.each { |failure| warn "  - #{failure}" }
  exit 1
end

if UNCHECKED.any? && %w[1 true yes on].include?(ENV["CHECK_STRICT_INCONCLUSIVE"].to_s.strip.downcase)
  warn "Release check: CHECK_STRICT_INCONCLUSIVE is set and #{UNCHECKED.size} precondition(s) were missing."
  exit 1
end

if UNCHECKED.any?
  puts "Release check passed what it could run (#{APPS.size} apps + shared, #{UNCHECKED.size} step group(s) skipped)."
else
  puts "Release check passed (#{APPS.size} apps + shared)."
end
