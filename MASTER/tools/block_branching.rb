#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Bash. This repository writes straight to main: no worktree,
# no branch, no pull request. The refusal covers creating a worktree, creating or
# switching to a new branch, opening or merging a PR, and pushing to any ref but main.
# Listing, deleting and cleaning up what already exists stay allowed, so an old
# worktree can still be removed.
#
# Why: a branch or worktree is a second copy of the tree that a session must
# merge back, and the merge back is where work was lost and stale copies were
# deployed. Safety lives in path-scoped commits (`git commit -- <paths>`), the
# pre-commit and pre-push hooks, and `git log origin/main..HEAD` before a push.
#
# Reads the hook JSON on stdin. Exit 2 with the reason on stderr blocks the call;
# a payload it cannot parse is let through, because this guard must never be the
# reason a shell stops working.

require "json"
require "shellwords"

GIT = /(?:\A|[;&|(`]|\$\()\s*(?:\S+=\S+\s+)*(?:command\s+)?git((?:\s+(?:-[Cc]\s+\S+|--[\w-]+(?:=\S+)?))*)\s+(\w[\w-]*)([^;&|`)\n]*)/
GH_PR = /(?:\A|[;&|(`]|\$\()\s*(?:\S+=\S+\s+)*(?:command\s+)?gh\s+pr\s+(create|merge|edit|ready|close|reopen)\b/

BRANCH_READS = %w[-a -r -v -vv --list -l --show-current --contains --merged --no-merged --points-at].freeze
BRANCH_EDITS = %w[-d -D --delete -m -M --move -c -C --copy -u --set-upstream-to --unset-upstream].freeze

# A redirect is not a ref: drop `2>&1`, `>out` and `> out` (operator plus its target).
def without_redirects(words)
  skip = false

  words.reject do |word|
    redirect = word.match?(/\A(?:\d*[<>]+|&>)/)
    drop = skip || redirect
    skip = redirect && word.match?(/\A(?:\d*[<>]+|&>)\z/)
    drop
  end
end

def refusal(command)
  command.to_s.scan(GIT).each do |_opts, sub, rest|
    words = rest.to_s.shellsplit rescue rest.to_s.split
    words = without_redirects(words)
    flags = words.select { |word| word.start_with?("-") }
    plain = words.reject { |word| word.start_with?("-") }

    case sub
    when "worktree"
      verb = plain.first.to_s
      return "git worktree #{verb}" if %w[add move lock repair].include?(verb)
    when "branch"
      next if (flags & (BRANCH_READS + BRANCH_EDITS)).any? || plain.empty?

      return "git branch #{plain.first}"
    when "checkout"
      return "git checkout #{flags.find { |f| f.match?(/\A-[bB]\z/) }}" if flags.any? { |flag| flag.match?(/\A-[bB]\z/) }
    when "switch"
      return "git switch #{flags.find { |f| f.match?(/\A(?:-[cC]|--create|--force-create)\z/) }}" if flags.any? { |flag| flag.match?(/\A(?:-[cC]|--create|--force-create)\z/) }
    when "push"
      next if (flags & %w[-d --delete]).any?

      elsewhere = plain.drop(1).reject do |ref|
        destination = (ref.include?(":") ? ref.split(":", 2).last : ref).sub(%r{\Arefs/heads/}, "")
        %w[main HEAD].include?(destination)
      end
      return "git push #{elsewhere.join(' ')}" unless elsewhere.empty?
    end
  end
  match = command.to_s.match(GH_PR)
  "gh pr #{match[1]}" if match
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  exit 0
end
exit 0 unless payload.is_a?(Hash) && payload["tool_name"].to_s == "Bash"

found = refusal(payload.dig("tool_input", "command"))
exit 0 unless found

warn <<~MSG
  #{found} blocked: this repository writes straight to main. No worktrees, no branches, no pull requests.
  Edit the checkout, commit path-scoped (`git commit -- <paths>`), run `git log origin/main..HEAD` and
  push main. Removing an existing worktree or branch (`git worktree remove`, `git branch -d`) is allowed.
MSG
exit 2
