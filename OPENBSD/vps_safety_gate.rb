#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("../..", __dir__)
OPENBSD = File.join(ROOT, "DEPLOY", "openbsd")
failures = []

doas_conf = File.join(OPENBSD, "etc", "doas.conf")
if File.file?(doas_conf)
  text = File.read(doas_conf)
  failures << "doas.conf must end with newline (OpenBSD parser rejects EOF without one)" unless text.end_with?("\n")
else
  failures << "missing tracked etc/doas.conf"
end

validate_doas = File.join(OPENBSD, "sh", "validate_doas.ksh")
failures << "missing DEPLOY/openbsd/sh/validate_doas.ksh" unless File.file?(validate_doas)

console_common = File.join(OPENBSD, "sh", "vps_console_common.exp")
failures << "missing DEPLOY/openbsd/sh/vps_console_common.exp" unless File.file?(console_common)

Dir.glob(File.join(OPENBSD, "sh", "vps_console*.exp")).sort.each do |path|
  rel = path.delete_prefix("#{ROOT}/")
  text = File.read(path)
  unless text.include?("vps_console_common.exp") && text.include?("require_console_risk_ack")
    failures << "#{rel} must source vps_console_common.exp and call require_console_risk_ack"
  end
  if text.include?("vm27")
    failures << "#{rel} must target vm23 only (found vm27)"
  end
end

drop_install = File.join(OPENBSD, "sh", "vps_drop_install.exp")
if File.file?(drop_install)
  text = File.read(drop_install)
  unless text.include?("vps_console_common.exp") && text.include?("require_console_risk_ack")
    failures << "DEPLOY/openbsd/sh/vps_drop_install.exp must source vps_console_common.exp"
  end
end

Dir.glob(File.join(OPENBSD, "etc", "rc.d", "*")).sort.each do |path|
  next unless File.file?(path)
  next if File.basename(path) == "litestream"

  text = File.read(path)
  rel = path.delete_prefix("#{ROOT}/")
  if text.include?("falcon serve") && !text.include?("bundle34 exec falcon")
    failures << "#{rel} must invoke falcon via bundle34 exec (gem binstub, not PATH)"
  end
end

if failures.any?
  warn "VPS safety gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "VPS safety gate passed (doas.conf, console guards, validate_doas.ksh, rc.d falcon)."