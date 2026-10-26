#!/usr/bin/env ruby
# frozen_string_literal: true

require "rbconfig"
require_relative "../lib/trace/dmesg"

ROOT = File.expand_path("../..", __dir__)
MASTER = File.join(ROOT, "MASTER").freeze
CLI = File.join(MASTER, "bin", "cli").freeze

ENV["PUB4_ROOT"] ||= ROOT
# The terminal runtime is a quiet, local instruction surface. Repository-wide scanning is opt-in.
# MASTER_BACKGROUND_SCAN=1 opts in; an explicit skip always wins.
ENV["MASTER_WEB"] ||= "0"
ENV["MASTER_BACKGROUND_SCAN"] ||= "0"
ENV["MASTER_SKIP_BOOT_SCAN"] ||= (ENV["MASTER_BACKGROUND_SCAN"] == "1" ? "0" : "1")
ENV["MASTER_CLI_QUIET"] ||= "1"

if ARGV.first == "replay"
  require_relative "../lib/fix/kernel"
  exit Master::Fix::Kernel.replay_cli(root: ROOT, seq: ARGV[1])
end

if ARGV.first == "--fix-context"
  target = ARGV[1] && !ARGV[1].start_with?("-") ? ARGV[1] : ROOT
  full = ARGV.include?("--full")

  exec(
    RbConfig.ruby,
    File.join(MASTER, "tools", "agent_context.rb"),
    "--fix-context",
    target,
    *(["--full"] if full),
  )
end

if ARGV.first == "--help" || ARGV.first == "-h"

  Master::Trace::Dmesg::Report.print("/help", <<~HELP)
    master — instruct the MASTER runtime with the whole repo in scope

    Usage:
      bin/master
      bin/master "<instruction>"
      bin/master --fold "<goal>"
      bin/master -p "<goal>" --output-format json [--model ID] [--permission-mode plan] [--allowedTools "Read Edit"]
      bin/master --fix-context [target] [--full]
      bin/master replay [sequence]
      bin/master replay <sequence>
      bin/master --daemon
      bin/master --fast
      echo '/status' | bin/master

    MASTER/bin/master is the public instruction surface.
    MASTER/bin/ruby selects the best supported Ruby before this file boots.
    MASTER/bin/cli owns slash commands and interactive routing.
    PreToolUse hooks for the Fold are read from ~/.master/hooks.yml (MASTER_HOOKS overrides); see lib/cli/tool_hooks.rb.
  HELP
  exit 0
end

# An interactive session says something at once, from live state, before the boot below. In its own
# process: it reads JSON and git before the bundle pins json, date and psych, and loading them here first
# made Bundler refuse to activate.
if ARGV.empty? && $stdout.tty? && ENV["MASTER_INTERNAL_CHILD"] != "1"
  system(RbConfig.ruby, "--disable-gems", File.join(MASTER, "lib", "cli", "welcome.rb"), MASTER)
end

require_relative "../lib/boot/entrypoint"
Master::Boot::Entrypoint.prepare!(root: MASTER)

unless File.file?(CLI)
  Master::Trace::Dmesg.status("master0", "#{CLI} missing, full pub4 checkout required", io: $stderr)
  exit 1
end

daemon = ARGV.delete("--daemon")
if daemon
  ENV["MASTER_CONTROL_PLANE"] = "1"
elsif ENV["MASTER_INTERNAL_CHILD"] == "1"
  ENV.delete("MASTER_CONTROL_PLANE")
  ENV.delete("MASTER_PROCESS_LOCK_FD")
end

require_relative "../lib/master"
require_relative "../lib/ops"

$MASTER_PROCESS_LOCK = if ENV["MASTER_INTERNAL_CHILD"] == "1"
                         nil
                       else
                         Master::Ops::ProcessLock.acquire!(
                           root: MASTER,
                           mode: daemon ? "control_plane" : "interactive",
                           inherit_fd: true,
                         )
                       end

unless ENV["MASTER_INTERNAL_CHILD"] == "1" || $MASTER_PROCESS_LOCK
  owner = Master::Ops::ProcessLock.owner(path: File.join(MASTER, ".master", "process.lock"))
  detail = owner.empty? ? "" : " pid=#{owner["pid"]} host=#{owner["host"]} mode=#{owner["mode"]}"

  Master::Trace::Dmesg.status(
    "master0",
    "another process owns the control plane#{detail}",
    io: $stderr,
  )
  exit 75
end

ENV["MASTER_PROCESS_LOCK_FD"] = $MASTER_PROCESS_LOCK.fileno.to_s if $MASTER_PROCESS_LOCK

args = ARGV.dup
args = ["-m", args.first] if args.length == 1 && !args.first.start_with?("-")

Dir.chdir(MASTER)
exec(RbConfig.ruby, CLI, *args)
