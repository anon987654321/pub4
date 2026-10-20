#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Bash: the house rule, enforced. CLAUDE.md says Ruby and zsh, not GNU text tools: BSD
# variants break GNU idioms, this repo deploys to OpenBSD, and `ruby -e`, zsh globs and the dedicated file
# tools do the same work without a second dialect.

# The rule was written down and broken all the same, so a command that runs one of them is refused with the
# replacement. Only a command position counts (the start, or after | ; & ( or $( or a backtick), so a word
# inside a quoted string, a heredoc body, a path or an argument never trips it.

# Reads the hook JSON on stdin. Exit 2 with the reason on stderr blocks the call. A payload it cannot read
# passes: this guard must never be the reason a shell stops working.

require "json"

SCRIPTING = "Ruby; perl and python are banned in agent shell calls and committed scripts"

BANNED = {
  "sed" => "the Edit tool, or Ruby: File.read, sub, File.write",
  "awk" => "Ruby: `ruby -e` with split and map",
  "find" => "zsh globs (**/*.rb) or Dir.glob; `git ls-files` for tracked files",

  "head" => "Ruby: lines.first(n); or the Read tool with a limit",
  "tail" => "Ruby: lines.last(n); or the Read tool with an offset",
  "wc" => "Ruby: lines.size, or File.foreach(...).count",

  "cut" => "Ruby: line[a, b] or split",
  "tr" => "Ruby: String#tr or gsub",
  "perl" => SCRIPTING,

  "python" => SCRIPTING,
  "python3" => SCRIPTING,
}.freeze

PREFIXES = "(?:env\\s+|exec\\s+|sudo\\s+|command\\s+)?"
COMMAND_POSITION = /(?:\A|[|;&(`\n]|\$\()\s*#{PREFIXES}(#{BANNED.keys.join("|")})(?=\s|\z)/

HEREDOC = /<<[-~]?\s*(?:'(\w+)'|"(\w+)"|(\w+))/

# A heredoc body is data (a script being written), not a command line: blank it, keeping the line count.
def without_heredocs(command)
  terminator = nil

  blanked = command.lines.map do |line|
    if terminator
      terminator = nil if line.strip == terminator
      "\n"
    else
      terminator = line[HEREDOC, 1] || line[HEREDOC, 2] || line[HEREDOC, 3]
      line
    end
  end

  blanked.join
end

# Blank out the inside of quotes, so `echo "use sed here"` is not a use of sed.
def unquoted(command)
  out = +""
  quote = nil

  without_heredocs(command).each_char do |char|
    if quote
      quote = nil if char == quote

      out << (char == "\n" ? "\n" : " ")
    elsif ["'", '"'].include?(char)
      quote = char

      out << " "
    else
      out << char
    end
  end

  out
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "gnu-text-tools: unreadable hook payload (#{e.class}); letting it through"
  exit 0
end

command = payload.dig("tool_input", "command").to_s
exit 0 unless payload["tool_name"] == "Bash" && !command.empty?

used = unquoted(command).scan(COMMAND_POSITION).flatten.uniq
exit 0 if used.empty?

warn "gnu-text-tools: #{used.join(", ")} is banned here (CLAUDE.md: Ruby and zsh, not GNU text tools)."
used.each { |name| warn "  #{name}: use #{BANNED.fetch(name)}" }
exit 2
