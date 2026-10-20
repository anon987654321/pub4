#!/usr/bin/env ruby
# frozen_string_literal: true

# SessionStart hook: the constitution is in front of the agent before its first thought, not after its first
# mistake. MASTER boots with soul.yml and laws.yml loaded; this gives Claude Code the same start. The
# top-ranked laws are read from laws.yml as they are now, so the list cannot drift from the law, and the
# rest of the guards (read the law before a write, judge each edit, lint before finishing) are named so
# their refusals are not a surprise.
#
# Standard output becomes session context. It prints nothing outside a pub4 checkout, and anything it
# cannot read passes silently: this hook must never be the reason a session fails to start.

require "json"
require "yaml"

TOP = 12
STATEMENT_CHARS = 110

def checkout_root(start)
  dir = File.expand_path(start)
  until dir == "/"
    return dir if File.file?(File.join(dir, "MASTER", "data", "laws.yml"))

    dir = File.dirname(dir)
  end
  nil
end

def top_laws(root)
  catalog = YAML.safe_load_file(File.join(root, "MASTER", "data", "laws.yml"), aliases: true) || {}
  rows = catalog.filter_map do |id, row|
    next unless row.is_a?(Hash) && row["priority"].is_a?(Numeric) && !row["statement"].to_s.empty?

    [row["priority"], id.to_s, row["statement"].to_s.strip.gsub(/\s+/, " ")]
  end
  rows.sort.first(TOP)
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "session-law-context: unreadable hook payload (#{e.class}); using the working directory"
  {}
end

root = checkout_root(payload["cwd"] || Dir.pwd)
exit 0 unless root

laws = begin
  top_laws(root)
rescue StandardError => e
  warn "session-law-context: laws.yml unreadable (#{e.class}); listing none"
  []
end

BRIEFING = <<~TEXT
  pub4 session context. You work under MASTER's constitution; the guards below are mechanical, not advice.
  Authority: MASTER/data/soul.yml > MASTER/data/laws.yml > MASTER/law/*.rb and scan/laws/*.rb
    > CLAUDE.md > the tree contract.
  Never edit soul.yml or laws.yml. Write straight to main; commit path-scoped (git commit -- <paths>), never -a.
  Guards: the law must be read before the first write (ruby MASTER/tools/agent_context.rb --tree, then each
  Law with MASTER/bin/operator laws <ID>); every edit is judged by the laws; a turn cannot finish while a
  line you changed breaks one (MASTER/bin/operator lint --changed-lines <files> shows what the guard sees).
TEXT

puts BRIEFING
unless laws.empty?
  puts "Highest-ranked laws now:"
  laws.each { |priority, id, statement| puts "  #{id} (#{priority}): #{statement[0, STATEMENT_CHARS]}" }
end
exit 0
