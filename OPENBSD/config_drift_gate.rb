#!/usr/bin/env ruby
# frozen_string_literal: true

# encoding: utf-8

# Fails when a security-critical config or scheduled script on vm23 does not
# match its tracked OPENBSD/ mirror byte-for-byte.
#
# The doas keepenv root-RCE stayed live in production for days while the repo and
# TODO.md both called it fixed, because nothing ever compared the mirror against
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
# file the dev user can rewrite — and from there `..` is /usr/local, so a mirror
# resolved relative to this file lands on /usr/local/etc and every comparison
# finds no repo mirror. That is a gate reporting "clean" while comparing
# nothing, so the checkout is searched for rather than inferred.
#
# Reading the checkout is safe in a way that executing it is not: root compares
# bytes it never runs, so the escalation the installed copy exists to close stays
# closed. PUB4_ROOT first so a worktree or a test can point it somewhere else.
DRIFT_ROOT = [ENV["PUB4_ROOT"], File.expand_path("..", __dir__), "/home/dev/pub4"]
       .compact
       .find { |dir| File.file?(File.join(dir, "OPENBSD", "etc", "doas.conf")) } ||
       File.expand_path("..", __dir__)
MIRROR = File.join(DRIFT_ROOT, "OPENBSD")

# Repo mirror => live path, for every file installed byte-for-byte.
#
# /etc is half of it. The other half is /usr/local/bin, where every root cron
# job on this box lives: the load guard, the drift check, the certificate
# renewal, the uptime check, the two jobs that keep the working set resident.
# A hand-edit there changes what vm23 does on a schedule, and the same argument
# that makes /etc worth comparing makes those worth comparing.
#
# The key is a repo path rather than the live path with its slash stripped
# because four of these ship from the tree root: OPERATOR.sh installs them with
# `install` while the rest arrive as a `cp -R usr/. /usr/`.
VERBATIM = {
  "etc/doas.conf" => "/etc/doas.conf",
  "etc/pf.conf" => "/etc/pf.conf",
  "etc/httpd.conf" => "/etc/httpd.conf",
  "etc/rc.conf.local" => "/etc/rc.conf.local",
  "etc/login.conf" => "/etc/login.conf",
  "etc/newsyslog.conf" => "/etc/newsyslog.conf",
  "etc/ssh/sshd_config" => "/etc/ssh/sshd_config",
  "etc/rc.d/master" => "/etc/rc.d/master",
  "etc/rc.d/brgen" => "/etc/rc.d/brgen",
  "etc/rc.d/amber" => "/etc/rc.d/amber",
  "etc/rc.d/bsdports" => "/etc/rc.d/bsdports",
  "usr/local/bin/config-drift-check" => "/usr/local/bin/config-drift-check",
  "usr/local/bin/core-reclaim.sh" => "/usr/local/bin/core-reclaim.sh",
  "usr/local/bin/drain-jobs.sh" => "/usr/local/bin/drain-jobs.sh",
  "usr/local/bin/keep-warm.sh" => "/usr/local/bin/keep-warm.sh",
  "usr/local/bin/nsd-resign" => "/usr/local/bin/nsd-resign",
  "usr/local/bin/prune-guests.sh" => "/usr/local/bin/prune-guests.sh",
  "usr/local/bin/prune_guests.rb" => "/usr/local/bin/prune_guests.rb",
  "usr/local/bin/relayd-watchdog" => "/usr/local/bin/relayd-watchdog",
  "usr/local/bin/renew-certs.sh" => "/usr/local/bin/renew-certs.sh",
  "usr/local/bin/uptime-check.sh" => "/usr/local/bin/uptime-check.sh",
  "resource_guard.sh" => "/usr/local/bin/resource_guard.sh",
  "emergency_cpu.sh" => "/usr/local/bin/emergency_cpu.sh",
  "config_drift_gate.rb" => "/usr/local/bin/config_drift_gate.rb",
  "lib/utf8.rb" => "/usr/local/bin/lib/utf8.rb",
  "vps_weekly_integrity.sh" => "/usr/local/bin/vps_weekly_integrity.sh",
}.freeze

EXCLUDED = %w[etc/relayd.conf etc/mail/smtpd.conf etc/litestream.yml etc/acme-client.conf].freeze

# Root's crontab cannot join VERBATIM: OPERATOR.sh merges the tracked lines into
# whatever is already there rather than overwriting the file, so a byte compare
# would fail on every box that has ever been touched by hand. What is comparable
# is the set of commands, and that is the half worth comparing — a schedule the
# repo declares and the box does not run is a capability that exists only in this
# directory.
#
# It is the gap this check was written for. `etc/crontab.vm23:97` has scheduled
# `/usr/local/bin/vps_weekly_integrity.sh` for weeks; the box has no such line, no
# such file and no /var/log/pub4 to write into, and the weekly integrity pass has
# therefore never run once. Every /etc file matched, so the gate said clean.
CRONTAB_MIRROR = "etc/crontab.vm23"
CRONTAB_KEY = "@root-crontab"

REMOTE = ARGV.include?("--remote")
SSH_HOST = ENV.fetch("SSH_HOST", "dev@brgen.no")
SSH_KEY = File.expand_path(ENV.fetch("SSH_KEY", "~/.ssh/id_ed25519_brgen"))
MARKER = "@@PUB4_CONFIG_DRIFT@@"

def on_vps?
  File.file?("/etc/relayd.conf") || ENV["DEPLOY_ASSUME_VPS"] == "1"
end

# A machine with no doas is a machine that cannot answer, not a crash.
# `DEPLOY_ASSUME_VPS=1` is documented in bin/check-rails as the way to exercise
# the on-VPS path from a laptop, and on a laptop `doas` does not exist — so
# without the rescue this gate raises Errno::ENOENT where it means to report
# nothing found.
def doas_run(*command)
  out, status = Open3.capture2e("doas", "-n", *command)
  status.success? ? out : nil
rescue Errno::ENOENT
  nil
end

def doas_cat(path) = doas_run("cat", path)
def doas_root_crontab = doas_run("crontab", "-l", "-u", "root")

# One SSH round-trip for all files, the crontab included. Reading them one at a
# time is 11 rapid reconnects, which is what pf bruteforce blocks (RUNBOOK: one
# session at a time), and a separate connection for the crontab would be the
# twelfth. Each file emits `<marker><path>` on its own line then its contents;
# echo, not printf, because printf backslash escaping is fragile across ruby ->
# ssh -> shell.
def live_files(paths)
  keys = paths + [CRONTAB_KEY]

  unless REMOTE
    map = paths.to_h { |path| [path, File.readable?(path) ? File.read(path) : doas_cat(path)] }
    map[CRONTAB_KEY] = doas_root_crontab
    return map
  end

  script = paths.map do |path|
    "echo #{(MARKER + path).dump}; doas cat #{path} 2>/dev/null || cat #{path} 2>/dev/null"
  end.join("; ")
  script += "; echo #{(MARKER + CRONTAB_KEY).dump}; doas crontab -l -u root 2>/dev/null"
  out, status = Open3.capture2e(
    "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-i", SSH_KEY, SSH_HOST, script
  )
  return keys.to_h { |key| [key, nil] } unless status.success?

  split_stream(out, keys)
end

# The command a crontab line schedules, as an absolute path.
#
# Five time fields (or an `@reboot`-style shorthand) then the command, and the
# first absolute path inside the command is the program: an environment prefix
# sits before it without a slash and a `>> /var/log/...` redirect comes after it.
# A bare `PATH=...` assignment has no five fields in front of it and so matches
# nothing, which is what should happen to it.
def scheduled_commands(text)
  text.to_s.lines.filter_map do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    next unless line =~ %r{\A(?:@\w+|\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.+)\z}

    Regexp.last_match(1)[%r{/\S+}]
  end.uniq
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

def report(drift, missing, compared, unfound, cron)
  EXCLUDED.each { |name| puts "config-drift: #{name.ljust(34)} skip - templated or generated (not verbatim)" }
  compared.each { |name| puts "config-drift: #{name.ljust(34)} ok" }
  puts "config-drift: #{CRONTAB_MIRROR.ljust(34)} #{cron[:summary]}"

  # The denominator, always. "clean" without it is the shape of every gate in
  # this tree that has ever passed having measured nothing: it reads identically
  # whether eleven files matched or the gate could not find a single one.
  if drift.empty? && missing.empty? && unfound.empty? && cron[:ok]
    puts "config-drift: clean (#{compared.size}/#{VERBATIM.size} verbatim files and " \
         "#{cron[:declared]} crontab command(s) match the live copy)"
    return
  end

  unfound.each { |name| warn "config-drift: #{name}: no repo mirror under #{MIRROR}" }
  warn "config-drift: compared #{compared.size}/#{VERBATIM.size} — a gate that compares nothing is not a passing gate" if compared.empty?
  missing.each { |name| warn "config-drift: #{name}: live file missing or unreadable on vm23" }
  drift.each do |name, detail|
    warn "config-drift: #{name}: DRIFT - the live copy differs from OPENBSD/#{name}"
    warn "  #{detail}"
  end
  cron[:absent].each do |command|
    warn "config-drift: #{CRONTAB_MIRROR}: DRIFT - root's crontab does not schedule #{command}"
  end
  cron[:extra].each do |command|
    warn "config-drift: #{CRONTAB_MIRROR}: DRIFT - root's crontab schedules #{command}, which the repo does not"
  end
  warn "config-drift: sync (doas zsh OPENBSD/OPERATOR.sh) or copy the live edit back into OPENBSD/"
end

# Nothing found and nothing missing are different answers. An unreadable crontab
# would otherwise report every declared job as absent, which is ten false alarms
# and the fastest way to teach a reader to skip this section.
def crontab_report(repo_text, live_text)
  declared = scheduled_commands(repo_text)
  return { ok: true, declared: declared.size, absent: [], extra: [], summary: "skip - no repo mirror" } if repo_text.nil?

  if live_text.nil? || live_text.strip.empty?
    return { ok: true, declared: declared.size, absent: [], extra: [],
             summary: "skip - root's crontab was not readable here" }
  end

  # Extras are scoped to /usr/local, because the repo owns only half of this file.
  # OpenBSD ships root a crontab of its own — `/usr/bin/newsyslog` and the three
  # `/bin/sh /etc/{daily,weekly,monthly}` lines — and OPERATOR.sh merges the pub4
  # lines onto it rather than replacing it. Every command this repo installs lives
  # under /usr/local/bin, so anything outside it is the base system's and reporting
  # it would be four permanent false alarms.
  live = scheduled_commands(live_text)
  absent = declared - live
  extra = (live - declared).select { |command| command.start_with?("/usr/local/") }
  {
    ok: absent.empty? && extra.empty?,
    declared: declared.size,
    absent: absent,
    extra: extra,
    summary: absent.empty? && extra.empty? ? "ok" : "DRIFT - #{absent.size} unscheduled, #{extra.size} unexpected",
  }
end

# Everything above is definitions; everything below runs. The split is what lets
# test/test_config_drift_gate.rb require this file and hand `crontab_report` the
# shape it must flag and the shape it must not — without the guard, requiring the
# gate off-VPS exits the test process at the skip line below.
return unless $PROGRAM_NAME == __FILE__

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
  repo_path = File.join(MIRROR, repo_rel)
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

crontab_mirror_path = File.join(MIRROR, CRONTAB_MIRROR)
cron = crontab_report(
  File.file?(crontab_mirror_path) ? File.read(crontab_mirror_path) : nil,
  live_map[CRONTAB_KEY]
)

report(drift, missing, compared, unfound, cron)
exit(drift.empty? && missing.empty? && unfound.empty? && cron[:ok] ? 0 : 1)
