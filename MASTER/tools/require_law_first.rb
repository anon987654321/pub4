#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Code hook that holds an agent to the rule CLAUDE.md states and nothing
# enforced: read the law before the first edit. One script, both events.
#
# PostToolUse on Bash records that the session read the law, by a command that
# prints it: agent_context.rb --tree, or bin/operator laws <ID>. PreToolUse on
# Edit and Write refuses a write inside a pub4 checkout until that record
# exists, and says which command to run. Writes outside a checkout, such as
# memory files, pass untouched.
#
# Reads the hook JSON on stdin. Exit 2 with the reason on stderr blocks the
# call. A payload it cannot parse is let through: this guard must never be the
# reason a session stops working.

require "json"
require "open3"
require "tmpdir"

READ_LAW = %r{agent_context\.rb\s+--tree|bin/operator\s+laws\s+\S+}

def marker(session) = File.join(Dir.tmpdir, "pub4-law-first-#{session.to_s.gsub(/\W/, "_")}")

# A checkout is any git work tree holding MASTER/data/laws.yml, so linked
# worktrees count and the path of the shared checkout is not assumed.
def pub4_checkout?(path)
  dir = File.dirname(File.expand_path(path))
  dir = File.dirname(dir) until Dir.exist?(dir) || dir == "/"
  top, status = Open3.capture2("git", "-C", dir, "rev-parse", "--show-toplevel", err: File::NULL)
  status.success? && File.file?(File.join(top.strip, "MASTER", "data", "laws.yml"))
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  exit 0
end

session = payload["session_id"]
case payload["hook_event_name"]
when "PostToolUse"
  command = payload.dig("tool_input", "command").to_s
  File.write(marker(session), Time.now.to_s) if command.match?(READ_LAW)
when "PreToolUse"
  path = payload.dig("tool_input", "file_path").to_s
  exit 0 if path.empty? || File.exist?(marker(session)) || !pub4_checkout?(path)

  warn "Read the law before the first edit (CLAUDE.md): run `ruby MASTER/tools/agent_context.rb --tree`, " \
       "or `MASTER/bin/operator laws <ID>` for the Law you are about to touch, then retry."
  exit 2
end
