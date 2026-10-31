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
# through — this guard must never be the reason a shell stops working — with
# one narrow exception, added with the @auto gate after the security review:
# when the unreadable payload's raw text carries a writing `git stash` call at
# command position, it is refused anyway. The cwd is unreadable too, so the
# shared-list check cannot run; a wrong `stash pop` costs the same whichever
# checkout it lands on, and there is no legitimate command left to protect
# once the payload is unreadable.

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

# For a payload broken past command extraction: `git`, a short gap free of
# shell separators, then `stash` and its optional subcommand, anywhere in the
# raw text. Loose by design — it runs only on input the JSON parser already
# refused, where there is no legitimate command left to protect.
RAW_STASH = /\bgit\b[^;|&()]{0,80}?\s+stash(?:\s+([\w-]+))?/.freeze

def raw_stash_calls(text)
  text.to_s.scan(RAW_STASH).map { |(sub)| sub.to_s }
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

raw = $stdin.read
payload = begin
  JSON.parse(raw)
rescue JSON::ParserError
  # The command value is pulled out of the raw text even though the JSON is
  # broken, and held to the same STASH standard as a readable payload — so
  # `echo git stash push` still passes on the unreadable path too. Only a
  # payload broken past that point falls to the looser raw scan, which runs
  # on input the parser already refused, where no legitimate command is left
  # to protect.
  candidate = raw[/"command"\s*:\s*"(.*?)"/m, 1]
  calls = candidate ? stash_calls(candidate) : raw_stash_calls(raw)
  if calls.any? { |sub| writing?(sub) }
    warn <<~MSG
      git stash blocked: the hook payload was unreadable, but its text carries a writing
      `git stash` call. This repository shares ONE stash list across worktrees and an unreadable
      payload cannot prove the call is safe to run. Reissue the command so the hook can read it;
      `git stash list` and `git stash show` stay allowed.
    MSG
    exit 2
  end
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
