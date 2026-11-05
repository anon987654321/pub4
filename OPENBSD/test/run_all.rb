#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs OPENBSD/test/test_*.rb, one process per file.
#
#   ruby OPENBSD/test/run_all.rb            # all of them
#   ruby OPENBSD/test/run_all.rb health     # only files matching /health/
#
# One process per file for the reasons RAILS/test/run_all.rb gives: files that
# share a process share every top-level constant, one `exit` anywhere ends the
# run early with Minitest reporting whatever it had, and a red result names no
# file. Exit status is the number of files that failed or could not prove that
# a non-empty Minitest suite actually ran, capped at 255.

require "open3"
require "rbconfig"

module OpenBSDTestRunner
  SUMMARY_RE = /\A\s*(\d+) runs?, (\d+) assertions?, (\d+) failures?, (\d+) errors?(?:, (\d+) skips?)?\s*\z/

  module_function

  def parse_summary(output)
    output.to_s.lines.filter_map do |line|
      match = SUMMARY_RE.match(line.chomp)
      next unless match

      runs, assertions, failures, errors, skips = match.captures
      {
        runs: runs.to_i,
        assertions: assertions.to_i,
        failures: failures.to_i,
        errors: errors.to_i,
        skips: skips.to_s.to_i
      }
    end.last
  end

  # A successful process is not proof that a test ran. Some test files can
  # exit early or accidentally stop registering tests; require a real summary
  # with at least one run before accepting the file as green.
  def classify(output, status)
    summary = parse_summary(output)
    return [:blocked, "no valid Minitest summary", summary] unless summary
    return [:blocked, "Minitest reported zero runs", summary] if summary.fetch(:runs).zero?

    failures = summary.fetch(:failures)
    errors = summary.fetch(:errors)
    if failures.positive? || errors.positive?
      return [:fail, "Minitest reported #{failures} failures and #{errors} errors", summary]
    end

    unless status.success?
      return [:fail, "test process exited #{status.exitstatus || "unsuccessfully"}", summary]
    end

    [:pass, nil, summary]
  end

  def summary_line(summary)
    "#{summary.fetch(:runs)} runs, #{summary.fetch(:assertions)} assertions, " \
      "#{summary.fetch(:failures)} failures, #{summary.fetch(:errors)} errors, " \
      "#{summary.fetch(:skips)} skips"
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("../..", __dir__)
  filter = ARGV.first
  files = Dir.glob(File.join(root, "OPENBSD/test/**/test_*.rb")).sort
  files = files.select { |path| path.include?(filter) } if filter
  abort "openbsd contracts: no test files#{filter ? " matching #{filter.inspect}" : ""}" if files.empty?

  results = files.map do |path|
    output, status = Open3.capture2e(
      { "MT_NO_PLUGINS" => "1" }, RbConfig.ruby, path, chdir: root
    )
    state, reason, summary = OpenBSDTestRunner.classify(output, status)
    label = { pass: "ok  ", fail: "FAIL", blocked: "BLOCKED" }.fetch(state)
    tally = summary ? OpenBSDTestRunner.summary_line(summary) : "no valid Minitest summary"
    puts format("openbsd contracts: %s %-40s %s", label, File.basename(path), tally)
    unless state == :pass
      puts "        #{reason}"
      output.to_s.lines.last(4).each { |line| puts "        #{line.rstrip}" }
    end
    [path, state]
  end

  red = results.reject { |_, state| state == :pass }
  puts "openbsd contracts: #{files.size} file(s), #{red.size} red" \
       "#{red.empty? ? "" : ": #{red.map { |path, _| File.basename(path) }.join(", ")}"}"
  exit red.size.clamp(0, 255)
end
