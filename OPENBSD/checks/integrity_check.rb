#!/usr/bin/env ruby
# frozen_string_literal: true

# OPENBSD integrity chain — production, phantom FK, frontend, relayd, domain, crawl inventory.

require "open3"
require_relative "../lib/utf8"
require_relative "../lib/check_environment"

INTEGRITY_ROOT = File.expand_path("../..", __dir__)

# Exit 3 is how a subprocess check says it measured nothing: crawl_probe with no
# app listening, as MASTER/checks/runner.rb's SUBPROCESS_INCONCLUSIVE reads it.
INTEGRITY_INCONCLUSIVE = 3

# The check's own command, run from the repo root. Returns [output, verdict],
# the verdict true, false or :inconclusive.
RUN_CHECK = lambda do |cmd|
  out, status = Open3.capture2e(*cmd, chdir: INTEGRITY_ROOT)
  [out, status.exitstatus == INTEGRITY_INCONCLUSIVE ? :inconclusive : status.success?]
end

# Every check in order, sorted into failures, warnings and skips. skip_reason
# decides each skip from the needs the check declares, so vps_health off the box
# is skipped by the same rule as any other check and never executed.
def integrity_run(checks, root: INTEGRITY_ROOT, on_vps: Deploy::Environment.on_vps?, execute: RUN_CHECK, io: $stdout)
  report = { failures: [], warnings: [], skipped: [] }
  checks.each do |check|
    label = "integrity: #{check.name.ljust(18)}"

    script = File.join(root, check.path)
    unless File.file?(script)
      report[:warnings] << "#{check.name}: missing #{check.path}"
      next
    end

    if (reason = Deploy::CheckEnvironment.skip_reason(check, on_vps:))
      report[:skipped] << "#{check.name}: #{reason}"
      io.puts "#{label} skip — #{reason}"
      next
    end

    out, ok = execute.call([Deploy::RubyRunner.check_ruby, script, *Array(check.args)])
    # A check that measured nothing is neither a pass nor a failure. It is listed
    # as skipped with its own reason, and blocks only under
    # CHECK_STRICT_INCONCLUSIVE=1, the same policy the RAILS runner applies.
    if ok == :inconclusive && !%w[1 true yes on].include?(ENV["CHECK_STRICT_INCONCLUSIVE"].to_s.downcase)
      report[:skipped] << "#{check.name}: measured nothing — #{out.lines.first.to_s.strip}"

      io.puts "#{label} inconclusive"
    elsif ok == true
      io.puts "#{label} ok"
    elsif check.optional
      report[:warnings] << "#{check.name}: #{out.lines.last(3).join.strip}"
      io.puts "#{label} warn"
    else
      report[:failures] << check.name

      io.puts "#{label} fail"
      io.puts out unless out.strip.empty?
      # A box-side check that cannot connect usually means a pull with no deploy.
      if Array(check.needs).include?(:vps) && (out.include?("Could not connect") || out.include?("failed"))
        warn Deploy::CheckEnvironment.post_pull_warning
      end
    end
  end

  report
end

return unless $PROGRAM_NAME == __FILE__

report = integrity_run(Deploy::CheckEnvironment::INTEGRITY_CHECKS)
report[:skipped].each { |line| warn "integrity: skip — #{line}" }
report[:warnings].each { |line| warn "integrity: warn — #{line}" }

if report[:failures].empty?
  puts "integrity: clean"
  exit 0
end

warn "integrity: #{report[:failures].size} check(s) failed: #{report[:failures].join(', ')}"
exit 1
