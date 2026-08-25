#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
OPENBSD = File.join(ROOT, "OPENBSD")
TOOLING = File.join(ROOT, "OPENBSD")
failures = []

doas_conf = File.join(OPENBSD, "etc", "doas.conf")
if File.file?(doas_conf)
  text = File.read(doas_conf)
  failures << "doas.conf must end with newline (OpenBSD parser rejects EOF without one)" unless text.end_with?("\n")

  rules = text.lines.reject { |line| line.strip.empty? || line.strip.start_with?("#") }
  dev_rule = rules.find { |line| line.match?(/\bdev\s+as\s+root\b/) }

  # keepenv on the dev rule is a root RCE by construction: it carries RUBYOPT,
  # RUBYLIB, GEM_HOME and BUNDLE_* across the boundary, so `RUBYOPT=-r/tmp/x.rb doas
  # <anything>` runs as root with no shell involved. Removed 2026-08-02 for a measured
  # setenv allowlist; this is what stops it coming back with the next edit that finds
  # a variable missing. The root->root rule keeps keepenv on purpose — see the file.
  if dev_rule.nil?
    failures << "etc/doas.conf has no `dev as root` rule"
  else
    failures << "etc/doas.conf: dev rule must not use keepenv (root RCE via RUBYOPT)" if dev_rule.include?("keepenv")
    unless dev_rule.match?(/setenv\s*\{[^}]*\bI_UNDERSTAND_DNS_WIPE\b[^}]*\}/)
      failures << "etc/doas.conf: dev rule must setenv-allowlist I_UNDERSTAND_DNS_WIPE " \
                  "(OPERATOR.sh --stage-1's documented gate cannot cross without it)"
    end
  end
else
  failures << "missing tracked etc/doas.conf"
end

validate_doas = File.join(TOOLING, "validate_doas.ksh")
if File.file?(validate_doas)
  # install_doas_conf_from_repo rolls /etc/doas.conf back when validation fails, so
  # validation has to test the thing that changed. `doas id` alone passes with a wrong
  # or empty allowlist — the rollback net covered lockout and not the actual risk.
  guard = File.read(validate_doas)
  unless guard.include?("validate_doas_passes_env")
    failures << "validate_doas.ksh must check that an allowlisted variable still crosses, " \
                "not only that dev can reach root"
  end
else
  failures << "missing OPENBSD/validate_doas.ksh"
end

console_common = File.join(TOOLING, "vps_console_common.exp")
failures << "missing OPENBSD/vps_console_common.exp" unless File.file?(console_common)

console_main = File.join(TOOLING, "vps_console.exp")
if File.file?(console_main)
  text = File.read(console_main)
  unless text.include?("vps_console_common.exp") && text.include?("require_console_risk_ack")
    failures << "OPENBSD/vps_console.exp must source vps_console_common.exp and call require_console_risk_ack"
  end
  failures << "OPENBSD/vps_console.exp must target vm23 only (found vm27)" if text.include?("vm27")
else
  failures << "missing OPENBSD/vps_console.exp"
end

%w[vps_console_short vps_console_status vps_console_probe vps_console_fix_key
   vps_console_start_install vps_console_poll_install vps_console_install
   vps_console_sync_and_install vps_drop_install].each do |name|
  path = File.join(TOOLING, "#{name}.exp")
  failures << "missing OPENBSD/#{name}.exp" unless File.file?(path)
  next unless File.file?(path)

  text = File.read(path)
  unless text.include?("vps_console.exp")
    failures << "OPENBSD/#{name}.exp must delegate to vps_console.exp"
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
