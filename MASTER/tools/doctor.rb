#!/usr/bin/env ruby
# frozen_string_literal: true

# bin/operator doctor: the environment traps this repo has cost sessions hours,
# checked in seconds and reported one line each. Read-only; it changes nothing.
#
#   ok    the thing is fine
#   warn  works, but is about to cost you
#   FAIL  something that stops work is wrong, with the fix on the same line
#
# --remote adds the one ssh probe to vm23 (read-only).

require "open3"
require "json"
require "etc"

ROOT = File.expand_path("../..", __dir__)
MASTER = File.join(ROOT, "MASTER")
REMOTE = ARGV.include?("--remote")
@worst = :ok

def say(level, area, message)
  @worst = :FAIL if level == :FAIL
  @worst = :warn if level == :warn && @worst == :ok
  puts format("%-5s doctor0 at %-9s %s", level, area, message)
end

def run(*argv, timeout: 20)
  out, status = Open3.capture2e(*argv)
  [out.to_s, status.success?]
rescue StandardError
  ["", false]
end

# --- disk: the failure that blocked every tool in one session --------------------
def disk
  out, ok = run("df", "-kP", ROOT)
  free_gb = ok ? out.lines.last.to_s.split[3].to_f / (1024 * 1024) : nil
  return say(:warn, "disk", "cannot read free space") unless free_gb

  text = format("%.1f GiB free", free_gb)
  if free_gb < 2 then say(:FAIL, "disk", "#{text}: tools fail with ENOSPC under ~1 GiB; remove merged worktrees (bin/operator worktree finish --remove)")
  elsif free_gb < 5 then say(:warn, "disk", "#{text}: a full-suite run or a render can fill this")
  else say(:ok, "disk", text)
  end
end

# --- rubies: which one runs MASTER, and the stray json that breaks its boot ---------
def rubies
  versions = Dir[File.join(Dir.home, ".rbenv", "versions", "*")].map { |d| File.basename(d) }.sort
  chosen, ok = run(File.join(MASTER, "bin", "ruby"), "-e", "print RUBY_VERSION")
  say(ok ? :ok : :warn, "ruby", "installed #{versions.join(', ')}; MASTER runs #{ok ? chosen.lines.last.to_s.strip : 'unresolved'}")

end

# The only honest answer to whether MASTER boots is to boot it. A stray newer json
# in the gem directory once raised "already activated json" here; the entrypoint
# now pins the Gemfile's version, so this reports what actually happens.
def boot
  # "/model" starts the runtime and prints the active model without a model call;
  # "--version" is not a flag bin/master knows and exits non-zero.
  out, ok = run(File.join(MASTER, "bin", "master"), "/model")
  if ok && out.lines.any? { |l| l.start_with?("model:") }
    say(:ok, "boot", "bin/master starts")
  else
    last = out.lines.reject { |l| l =~ /^ruby0|warning:/ }.last.to_s.strip[0, 140]
    say(:FAIL, "boot", "bin/master does not start: #{last}")
  end
end

# --- worktrees: each is a full checkout; merged ones are dead weight ----------------
def worktrees
  out, = run("git", "-C", ROOT, "worktree", "list", "--porcelain")
  rows = out.split("\n\n").map { |b| b.lines.to_h { |l| k, v = l.chomp.split(" ", 2); [k, v] } }.reject { |r| r["worktree"] == ROOT }
  return say(:ok, "worktrees", "none besides the shared checkout") if rows.empty?

  merged = rows.select do |r|
    branch = r["branch"].to_s.delete_prefix("refs/heads/")
    !branch.empty? && system("git", "-C", ROOT, "merge-base", "--is-ancestor", branch, "HEAD", out: File::NULL, err: File::NULL)
  end
  mb = rows.sum { |r| File.directory?(r["worktree"]) ? run("du", "-sk", r["worktree"]).first.to_i / 1024 : 0 }
  level = rows.size > 6 ? :warn : :ok
  say(level, "worktrees", "#{rows.size} (#{mb} MB), #{merged.size} merged and removable: #{merged.map { |r| File.basename(r['worktree']) }.first(6).join(' ')}")
end

# --- git: what is only here ------------------------------------------------------------
def git_state
  branch, = run("git", "-C", ROOT, "rev-parse", "--abbrev-ref", "HEAD")
  ahead, = run("git", "-C", ROOT, "rev-list", "--count", "origin/main..HEAD")
  behind, = run("git", "-C", ROOT, "rev-list", "--count", "HEAD..origin/main")
  dirty, = run("git", "-C", ROOT, "status", "--porcelain")
  tracked = dirty.lines.grep(/\A[ MADRC]{2}/).size
  say(ahead.to_i.positive? || behind.to_i.positive? ? :warn : :ok, "git",
      "#{branch.strip}: #{ahead.to_i} ahead of origin/main, #{behind.to_i} behind (as of the last fetch); #{tracked} tracked files modified")
end

# --- model lanes: the thing /fix cannot do without -----------------------------------------
def lanes
  config = File.join(MASTER, ".master", "config.yml")
  pin = File.file?(config) ? File.read(config)[/^model:\s*(\S+)/, 1] : nil
  say(pin ? :ok : :warn, "model", pin ? "saved model #{pin}" : "no saved model in MASTER/.master/config.yml: a fresh worktree has none; copy it or set MASTER_MODEL")

  claude = File.executable?(File.join(Dir.home, ".local", "bin", "claude")) || system("which claude", out: File::NULL, err: File::NULL)
  say(claude ? :ok : :warn, "claude", claude ? "claude CLI found (the claude-cli lanes)" : "claude CLI not found: the claude-cli lanes are unreachable")

  tags, ok = run("curl", "-s", "-m", "3", "http://127.0.0.1:11434/api/tags")
  models = ok ? JSON.parse(tags)["models"].to_a.map { |m| m["name"] } : []
  say(models.empty? ? :warn : :ok, "ollama", models.empty? ? "not answering on 11434: no local lane" : "#{models.size} models: #{models.first(4).join(', ')}")
rescue StandardError => e
  say(:warn, "model", "lane check failed: #{e.class}")
end

# --- stray processes that hold CPU, RAM or a worktree ----------------------------------------
def processes
  out, = run("ps", "-axo", "pid=,etime=,command=")
  hits = out.lines.select { |l| l =~ %r{bin/(cli|master) /fix|demucs|afplay|ruby dilla\.rb|mlx_audio\.server} && l !~ /doctor/ }
  return say(:ok, "procs", "no /fix, audio or render processes running") if hits.empty?

  say(:warn, "procs", "#{hits.size} running: " + hits.first(4).map { |l| l.split(" ", 3).then { |p, e, c| "#{p}(#{e}) #{c[0, 38]}" } }.join("; "))
end

# --- vm23, read only ---------------------------------------------------------------------------
def remote
  return unless REMOTE

  key = File.join(Dir.home, ".ssh", "id_ed25519_brgen")
  out, ok = run("ssh", "-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "dev@brgen.no", "cd /home/dev/pub4 && echo $(git rev-parse --short HEAD) $(ls -d /home/dev/.pub4-vps-deploy.lock 2>/dev/null | wc -l) $(tmux ls 2>/dev/null | wc -l)")
  return say(:FAIL, "vm23", "ssh failed: key #{key}") unless ok

  sha, lock, tmux = out.lines.last.to_s.split
  head, = run("git", "-C", ROOT, "rev-parse", "--short", "origin/main")
  say(sha == head.strip ? :ok : :warn, "vm23", "checkout #{sha} (origin/main #{head.strip}); deploy lock #{lock.to_i.zero? ? 'free' : 'HELD'}; tmux sessions #{tmux.to_i}")
end

disk
rubies
boot
worktrees
git_state
lanes
processes
remote
puts "doctor0: #{@worst == :ok ? 'all clear' : "#{@worst} above; fix those first"}"
exit(@worst == :FAIL ? 1 : 0)
