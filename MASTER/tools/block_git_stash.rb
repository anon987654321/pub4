#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Bash. Refuses `git stash push|pop|apply|drop` (and the bare
# `git stash`, save, clear, branch) while this repository has more than one
# worktree, or the command runs inside a linked worktree.
#
# The stash list lives in the common git directory, so every worktree sees the
# same one. An agent that pops "its" stash applies whichever entry is on top,
# often another session's, and a push sweeps in the half-finished work of the
# shared checkout. Read-only subcommands (list, show) stay allowed.
#
# Reads the hook JSON on stdin. Exit 2 with the reason on stderr blocks the
# call; any other exit lets it through. A payload it cannot parse is let
# through: this guard must never be the reason a shell stops working.

require "json"
require "open3"

WRITING = %w[push pop apply drop save clear branch create store].freeze
READING = %w[list show].freeze
# `git`, optional global options (-C dir, -c k=v, --flag), then `stash`, then the
# subcommand word if one follows. Anchored to a command position so `echo git
# stash` and a commit message that mentions it do not match.
STASH = /
  (?:\A|[;&|(`]|\$\()\s*(?:\S+=\S+\s+)*(?:command\s+)?
  git((?:\s+(?:-[Cc]\s+\S+|--[\w-]+(?:=\S+)?))*)\s+stash(?:\s+([\w-]+))?
/x

def stash_calls(command)
  command.to_s.scan(STASH).map { |_opts, sub| sub.to_s }
end

def writing?(sub)
  return true if sub.empty? || sub.start_with?("-")

  WRITING.include?(sub) || !READING.include?(sub)
end

def git(dir, *args)
  out, status = Open3.capture2e("git", "-C", dir, *args)
  status.success? ? out.strip : nil
end

def shared_stash?(dir)
  return false unless dir && File.directory?(dir)

  git_dir = git(dir, "rev-parse", "--path-format=absolute", "--git-dir")
  common = git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
  return false unless git_dir && common
  return true if git_dir != common

  git(dir, "worktree", "list", "--porcelain").to_s.lines.count { |line| line.start_with?("worktree ") } > 1
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  exit 0
end
exit 0 unless payload.is_a?(Hash) && payload["tool_name"].to_s == "Bash"

command = payload.dig("tool_input", "command").to_s
exit 0 unless stash_calls(command).any? { |sub| writing?(sub) }
exit 0 unless shared_stash?(payload["cwd"].to_s)

warn <<~MSG
  git stash blocked: this repository has several worktrees and they share ONE stash list.
  `stash pop` or `apply` takes whichever entry is on top, usually another session's, and
  `stash push` also hides work another agent is editing. Commit path-scoped instead
  (`git commit -- <paths>`), or copy the file aside, or use your own worktree and a
  WIP commit you can reset. `git stash list` and `git stash show` are still allowed.
MSG
exit 2
