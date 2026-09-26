#!/usr/bin/env ruby
# frozen_string_literal: true

# OPENBSD integrity chain — production, phantom FK, frontend, relayd, domain, crawl inventory.

require "open3"
require_relative "../lib/utf8"
require_relative "../lib/gate_environment"

INTEGRITY_ROOT = File.expand_path("../..", __dir__)

# Exit 3 is how a subprocess gate says it measured nothing: crawl_probe with no
# app listening, as MASTER/gates/runner.rb's SUBPROCESS_INCONCLUSIVE reads it.
INTEGRITY_INCONCLUSIVE = 3

# The gate's own command, run from the repo root. Returns [output, verdict],
# the verdict true, false or :inconclusive.
RUN_GATE = lambda do |cmd|
  out, status = Open3.capture2e(*cmd, chdir: INTEGRITY_ROOT)
  [out, status.exitstatus == INTEGRITY_INCONCLUSIVE ? :inconclusive : status.success?]
end

# Every gate in order, sorted into failures, warnings and skips. skip_reason
# decides each skip from the needs the gate declares, so vps_health off the box
# is skipped by the same rule as any other gate and never executed.
def integrity_run(gates, root: INTEGRITY_ROOT, on_vps: Operator::Environment.on_vps?, execute: RUN_GATE, io: $stdout)
  report = { failures: [], warnings: [], skipped: [] }
  gates.each do |gate|
    label = "integrity: #{gate.name.ljust(18)}"
    script = File.join(root, gate.path)
    unless File.file?(script)
      report[:warnings] << "#{gate.name}: missing #{gate.path}"
      next
    end

    if (reason = Deploy::GateEnvironment.skip_reason(gate, on_vps:))
      report[:skipped] << "#{gate.name}: #{reason}"
      io.puts "#{label} skip — #{reason}"
      next
    end

    out, ok = execute.call([Operator::RubyRunner.gate_ruby, script, *Array(gate.args)])
    # A gate that measured nothing is neither a pass nor a failure. It is listed
    # as skipped with its own reason, and blocks only under
    # GATE_STRICT_INCONCLUSIVE=1, the same policy the RAILS runner applies.
    if ok == :inconclusive && !%w[1 true yes on].include?(ENV["GATE_STRICT_INCONCLUSIVE"].to_s.downcase)
      report[:skipped] << "#{gate.name}: measured nothing — #{out.lines.first.to_s.strip}"
      io.puts "#{label} inconclusive"
    elsif ok == true
      io.puts "#{label} ok"
    elsif gate.optional
      report[:warnings] << "#{gate.name}: #{out.lines.last(3).join.strip}"
      io.puts "#{label} warn"
    else
      report[:failures] << gate.name
      io.puts "#{label} fail"
      io.puts out unless out.strip.empty?
      # A box-side gate that cannot connect usually means a pull with no deploy.
      if Array(gate.needs).include?(:vps) && (out.include?("Could not connect") || out.include?("failed"))
        warn Deploy::GateEnvironment.post_pull_warning
      end
    end
  end
  report
end

return unless $PROGRAM_NAME == __FILE__

report = integrity_run(Deploy::GateEnvironment::INTEGRITY_GATES)
report[:skipped].each { |line| warn "integrity: skip — #{line}" }
report[:warnings].each { |line| warn "integrity: warn — #{line}" }

if report[:failures].empty?
  puts "integrity: clean"
  exit 0
end

warn "integrity: #{report[:failures].size} gate(s) failed: #{report[:failures].join(', ')}"
exit 1
