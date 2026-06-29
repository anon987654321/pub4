#!/usr/bin/env ruby
# frozen_string_literal: true

# DEPLOY integrity chain — production, phantom FK, frontend, relayd, domain, crawl inventory.

require "open3"
require "rbconfig"
require_relative "utf8"

ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby

GATES = [
  { name: "deploy_identity", path: "DEPLOY/verify_deploy_identity.rb" },
  { name: "production", path: "DEPLOY/rails/check_production_gate.rb" },
  { name: "phantom_fk", path: "DEPLOY/rails/check_phantom_foreign_keys.rb" },
  { name: "frontend", path: "DEPLOY/rails/frontend_production_gate.rb" },
  { name: "relayd_smoke", path: "DEPLOY/openbsd/deploy_smoke_gate.rb" },
  { name: "domain_align", path: "DEPLOY/rails/domain_alignment_gate.rb" },
  { name: "crawl_inventory", path: "DEPLOY/rails/crawl_probe.rb", args: [] },
].freeze

failures = []
warnings = []

GATES.each do |gate|
  script = File.join(ROOT, gate[:path])
  unless File.file?(script)
    warnings << "#{gate[:name]}: missing #{gate[:path]}"
    next
  end

  cmd = [RUBY, script, *Array(gate[:args])]
  out, status = Open3.capture2e(*cmd, chdir: ROOT)
  label = gate[:name]
  if status.success?
    puts "integrity: #{label.ljust(18)} ok"
  elsif gate[:optional]
    warnings << "#{label}: #{out.lines.last(3).join.strip}"
    puts "integrity: #{label.ljust(18)} warn"
  else
    failures << label
    puts "integrity: #{label.ljust(18)} fail"
    puts out unless out.strip.empty?
  end
end

if File.file?("/etc/relayd.conf")
  health = File.join(ROOT, "DEPLOY/openbsd/health_check.rb")
  if File.file?(health)
    out, status = Open3.capture2e(RUBY, health, "--core", chdir: ROOT)
    if status.success?
      puts "integrity: #{"vps_health".ljust(18)} ok"
    else
      failures << "vps_health"
      puts "integrity: #{"vps_health".ljust(18)} fail"
      puts out unless out.strip.empty?
    end
  end
else
  puts "integrity: #{"vps_health".ljust(18)} skip — not on VPS"
end

warnings.each { |line| warn "integrity: warn — #{line}" }

if failures.empty?
  puts "integrity: clean"
  exit 0
end

warn "integrity: #{failures.size} gate(s) failed: #{failures.join(", ")}"
exit 1
