#!/usr/bin/env ruby
# frozen_string_literal: true

# SessionStart adapter: Claude Code hands its payload here and gets MASTER's briefing back as session
# context. The briefing itself is Master::Ground::AgentBrief, the same text `bin/operator brief` prints for
# any other agent, so this file only finds the checkout and calls it.
#
# Prints nothing outside a pub4 checkout. Anything it cannot read passes with a warning: this hook must never
# be the reason a session fails to start.

require "json"
require_relative "../lib/ground/agent_brief"

def checkout_root(start)
  dir = File.expand_path(start)
  until dir == "/"
    return dir if File.file?(File.join(dir, "MASTER", "data", "laws.yml"))

    dir = File.dirname(dir)
  end
  nil
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "session-law-context: unreadable hook payload (#{e.class}); using the working directory"
  {}
end

root = checkout_root(payload["cwd"] || Dir.pwd)
begin
  puts Master::Ground::AgentBrief.render(root:) if root
rescue StandardError => e
  warn "session-law-context: no briefing (#{e.class}: #{e.message})"
end
exit 0
