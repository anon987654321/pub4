#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

# encoding: utf-8

# Fails when a security-critical config on vm23 does not match its tracked
# OPENBSD/etc mirror byte-for-byte.
#
# The doas keepenv root-RCE stayed live in production for days while the repo and
# DEBT.md both called it fixed, because nothing ever compared the mirror against
# the running /etc. This is the check that would have caught it: the repo IS the
# live config, and when it is not, that is either an undeployed fix or a hand-edit
# nobody copied back, and both are the bug this gate names.
#
# Only VERBATIM-installed files are byte-compared. Templated installs and
# generated files are listed as excluded rather than diffed, because a difference
# there is expected, not drift.
#
# Run on vm23:              ruby34 OPENBSD/config_drift_gate.rb
# Run from a laptop:        SSH_HOST=dev@brgen.no ruby OPENBSD/config_drift_gate.rb --remote
# Off-VPS without --remote: skips cleanly.

require "open3"
require "digest"
require_relative "lib/utf8"

# The repo is found, not assumed to be one level up.
#
# daily.local runs the INSTALLED copy at /usr/local/bin — root must not execute a
# file the dev user can rewrite — and from there `..` is /usr/local, so ETC was
# /usr/local/etc and every one of the eleven comparisons found no repo mirror.
# The gate warned eleven times, `next`ed past each without recording anything,
# and exited 0 reporting "clean (0 verbatim configs)". It had been reporting
# clean while comparing nothing.
#
# Reading the checkout is safe in a way that executing it is not: root compares
# bytes it never runs, so the escalation the installed copy exists to close stays
# closed. PUB4_ROOT first so a worktree or a test can point it somewhere else.
ROOT = [ENV["PUB4_ROOT"], File.expand_path("..", __dir__), "/home/dev/pub4"]
       .compact
       .find { |dir| File.file?(File.join(dir, "OPENBSD", "etc", "doas.conf")) } ||
       File.expand_path("..", __dir__)
ETC = File.join(ROOT, "OPENBSD", "etc")

VERBATIM = {
  "doas.conf" => "/etc/doas.conf",
  "pf.conf" => "/etc/pf.conf",
  "httpd.conf" => "/etc/httpd.conf",
  "rc.conf.local" => "/etc/rc.conf.local",
  "login.conf" => "/etc/login.conf",
  "newsyslog.conf" => "/etc/newsyslog.conf",
  "ssh/sshd_config" => "/etc/ssh/sshd_config",
  "rc.d/master" => "/etc/rc.d/master",
  "rc.d/brgen" => "/etc/rc.d/brgen",
  "rc.d/amber" => "/etc/rc.d/amber",
  "rc.d/bsdports" => "/etc/rc.d/bsdports",
}.freeze

EXCLUDED = %w[relayd.conf mail/smtpd.conf litestream.yml acme-client.conf].freeze

REMOTE = ARGV.include?("--remote")
SSH_HOST = ENV.fetch("SSH_HOST", "dev@brgen.no")
SSH_KEY = File.expand_path(ENV.fetch("SSH_KEY", "~/.ssh/id_ed25519_brgen"))
MARKER = "@@PUB4_CONFIG_DRIFT@@"

def on_vps?
  File.file?("/etc/relayd.conf") || ENV["DEPLOY_ASSUME_VPS"] == "1"
end

def doas_cat(path)
  out, status = Open3.capture2e("doas", "-n", "cat", path)
  status.success? ? out : nil
end

# One SSH round-trip for all files. Reading them one at a time is 11 rapid
# reconnects, which is what pf bruteforce blocks (RUNBOOK: one session at a time).
# Each file emits `<marker><path>` on its own line then its contents; echo, not
# printf, because printf backslash escaping is fragile across ruby -> ssh -> shell.
def live_files(paths)
  return paths.to_h { |path| [path, File.readable?(path) ? File.read(path) : doas_cat(path)] } unless REMOTE

  script = paths.map do |path|
    "echo #{(MARKER + path).dump}; doas cat #{path} 2>/dev/null || cat #{path} 2>/dev/null"
  end.join("; ")
  out, status = Open3.capture2e(
    "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-i", SSH_KEY, SSH_HOST, script
  )
  return paths.to_h { |path| [path, nil] } unless status.success?

  split_stream(out, paths)
end

def split_stream(out, paths)
  result = paths.to_h { |path| [path, nil] }
  out.split(MARKER)[1..].to_a.each do |chunk|
    header, body = chunk.split("\n", 2)
    path = header.to_s.strip
    result[path] = body if paths.include?(path)
  end
  result
end

def report(drift, missing, compared, unfound)
  EXCLUDED.each { |name| puts "config-drift: #{name.ljust(22)} skip - templated or generated (not verbatim)" }
  compared.each { |name| puts "config-drift: #{name.ljust(22)} ok" }

  # The denominator, always. "clean" without it is the shape of every gate in
  # this tree that has ever passed having measured nothing: it reads identically
  # whether eleven files matched or the gate could not find a single one.
  if drift.empty? && missing.empty? && unfound.empty?
    puts "config-drift: clean (#{compared.size}/#{VERBATIM.size} verbatim configs match live /etc)"
    return
  end

  unfound.each { |name| warn "config-drift: #{name}: no repo mirror under #{ETC}" }
  warn "config-drift: compared #{compared.size}/#{VERBATIM.size} — a gate that compares nothing is not a passing gate" if compared.empty?
  missing.each { |name| warn "config-drift: #{name}: live file missing or unreadable on vm23" }
  drift.each do |name, detail|
    warn "config-drift: #{name}: DRIFT - live /etc differs from OPENBSD/etc"
    warn "  #{detail}"
  end
  warn "config-drift: sync (doas zsh OPENBSD/OPERATOR.sh) or copy the live edit back into OPENBSD/etc/"
end

unless REMOTE || on_vps?
  warn "config-drift: skip - not on vm23 (run on the box, or pass --remote with SSH_HOST set)"
  exit 0
end

drift = {}
missing = []
compared = []
unfound = []
live_map = live_files(VERBATIM.values)

VERBATIM.each do |repo_rel, live_path|
  repo_path = File.join(ETC, repo_rel)
  unless File.file?(repo_path)
    # Recorded, not merely warned. `next` alone left this out of every tally, so
    # a gate that could not find the repo at all still exited 0.
    unfound << repo_rel
    next
  end

  live = live_map[live_path]
  if live.nil? || live.empty?
    missing << repo_rel
    next
  end

  repo = File.read(repo_path)
  if repo == live
    compared << repo_rel
  else
    repo_sha = Digest::SHA256.hexdigest(repo)[0, 12]
    live_sha = Digest::SHA256.hexdigest(live)[0, 12]
    drift[repo_rel] = "repo sha=#{repo_sha} (#{repo.bytesize}B) vs live sha=#{live_sha} (#{live.bytesize}B)"
  end
end

report(drift, missing, compared, unfound)
exit(drift.empty? && missing.empty? && unfound.empty? ? 0 : 1)
