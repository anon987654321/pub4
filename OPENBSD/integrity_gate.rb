#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

# OPENBSD integrity chain — production, phantom FK, frontend, relayd, domain, crawl inventory.

require "open3"
require_relative "lib/utf8"
require_relative "lib/gate_environment"

ROOT = File.expand_path("..", __dir__)

failures = []
warnings = []
skipped = []

Deploy::GateEnvironment::INTEGRITY_GATES.each do |gate|
  next if gate.name == "vps_health"

  script = File.join(ROOT, gate.path)
  unless File.file?(script)
    warnings << "#{gate.name}: missing #{gate.path}"
    next
  end

  if (reason = Deploy::GateEnvironment.skip_reason(gate))
    skipped << "#{gate.name}: #{reason}"
    puts "integrity: #{gate.name.ljust(18)} skip — #{reason}"
    next
  end

  cmd = [Pub4::RubyRunner.gate_ruby, script, *Array(gate.args)]
  out, status = Open3.capture2e(*cmd, chdir: ROOT)
  if status.success?
    puts "integrity: #{gate.name.ljust(18)} ok"
  elsif gate.optional
    warnings << "#{gate.name}: #{out.lines.last(3).join.strip}"
    puts "integrity: #{gate.name.ljust(18)} warn"
  else
    failures << gate.name
    puts "integrity: #{gate.name.ljust(18)} fail"
    puts out unless out.strip.empty?
  end
end

vps_gate = Deploy::GateEnvironment::INTEGRITY_GATES.find { |g| g.name == "vps_health" }
if Pub4::Environment.on_vps?
  if (reason = Deploy::GateEnvironment.skip_reason(vps_gate))
    puts "integrity: #{"vps_health".ljust(18)} skip — #{reason}"
  else
    script = File.join(ROOT, vps_gate.path)
    cmd = [Pub4::RubyRunner.gate_ruby, script, *vps_gate.args]
    out, status = Open3.capture2e(*cmd, chdir: ROOT)
    if status.success?
      puts "integrity: #{"vps_health".ljust(18)} ok"
    else
      failures << "vps_health"
      puts "integrity: #{"vps_health".ljust(18)} fail"
      puts out unless out.strip.empty?
      warn Deploy::GateEnvironment.post_pull_warning if out.include?("Could not connect") || out.include?("failed")
    end
  end
else
  puts "integrity: #{"vps_health".ljust(18)} skip — not on VPS"
end

skipped.each { |line| warn "integrity: skip — #{line}" }
warnings.each { |line| warn "integrity: warn — #{line}" }

if failures.empty?
  puts "integrity: clean"
  exit 0
end

warn "integrity: #{failures.size} gate(s) failed: #{failures.join(', ')}"
exit 1
