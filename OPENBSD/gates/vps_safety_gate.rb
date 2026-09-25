#!/usr/bin/env ruby
# frozen_string_literal: true

# VPS_SAFETY_ROOT lets the test point this at a fixture tree holding the shapes
# it must flag; unset, it reads this checkout.
ROOT = ENV.fetch("VPS_SAFETY_ROOT", File.expand_path("../..", __dir__))
OPENBSD = File.join(ROOT, "OPENBSD")
TOOLING = File.join(ROOT, "OPENBSD", "bin")
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
    # The whole measured allowlist (etc/doas.conf): each is read by a script run
    # under doas and assigned by none, so dropping one silently breaks that
    # script — --stage-1's DNS-wipe gate, the console gate, production seeds, the
    # deploy scan skip, the mail image format.
    allowlist = dev_rule[/setenv\s*\{([^}]*)\}/, 1].to_s.split
    %w[I_UNDERSTAND_DNS_WIPE I_UNDERSTAND_CONSOLE_RISK RUN_PRODUCTION_SEEDS SKIP_MASTER_SCAN MAIL_IMG_FMT].each do |name|
      failures << "etc/doas.conf: dev rule must setenv-allowlist #{name}" unless allowlist.include?(name)
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
  failures << "missing OPENBSD/bin/validate_doas.ksh"
end

console_main = File.join(TOOLING, "vps_console.exp")
if File.file?(console_main)
  text = File.read(console_main)
  unless text.include?("proc require_console_risk_ack") && text.match?(/^require_console_risk_ack$/)
    failures << "OPENBSD/bin/vps_console.exp must define and call require_console_risk_ack"
  end
  failures << "OPENBSD/bin/vps_console.exp must target vm23 only (found vm27)" if text.include?("vm27")
else
  failures << "missing OPENBSD/bin/vps_console.exp"
end

# vps_console.exp is the one console door, and the ack inside it is the whole
# safety. Any other expect script beside it is a way to the console that
# skipped that check, so it fails here rather than being trusted to delegate.
Dir.glob(File.join(TOOLING, "*.exp")).reject { |path| path == console_main }.each do |path|
  failures << "OPENBSD/bin/#{File.basename(path)}: console automation belongs in vps_console.exp as a mode"
end

Dir.glob(File.join(OPENBSD, "etc", "rc.d", "*")).sort.each do |path|
  next unless File.file?(path)

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
