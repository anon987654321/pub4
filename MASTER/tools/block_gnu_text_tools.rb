#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Bash: refuses a command that runs anything in data/laws.yml
# `zsh.banned_commands` and names the law's replacement. This repo deploys to OpenBSD,
# where GNU idioms break, and its house law is Ruby and zsh, not GNU text tools.
# Master::Io::GnuTextTools owns the list, the lexer and the judgement; this file is the
# hook's stdin and exit code, so the harness, MASTER's own shell and the
# ZSH_NATIVE_PATTERNS Law cannot disagree about what a line runs.

# Contract (https://code.claude.com/docs/en/hooks): hook JSON on stdin carries tool_name and
# tool_input.command; exit 2 blocks the call and stderr is the reason Claude reads. An unreadable
# payload passes, because this guard must never be the reason a shell stops working — with one
# narrow exception, added with the @auto gate after the security review: when the payload the
# JSON parser refuses (or a command the lexer refuses) carries a banned-command invocation at
# command position in its raw text, it is refused anyway. The lexer paths answer for everything
# readable; this answers for the two shapes that would otherwise ride the fail-open hole past a
# guard whose whole subject is those commands. The scan is deliberately conservative — it names
# the core text-tool commands, not every law row — and only ever fires on input some parser
# already refused, so a false one costs a re-issued call, not a working shell. It is wired under
# hooks.PreToolUse in .claude/settings.json through tools/hook_ruby.rb; --test runs the built-in
# cases.

require "json"
require_relative "../lib/io/gnu_text_tools"

TOOLS = Master::Io::GnuTextTools.load(File.expand_path("../data/laws.yml", __dir__))

SELF_TEST_CASES = {
  "git status" => [], "sed -i s/a/b/ x" => %w[sed], "ls | head -5" => %w[head],
  "for f in *.rb; do wc -l $f; done" => %w[wc], "if true; then tail -n 3 x; fi" => %w[tail],
  "git ls-files | xargs sed -n 1p" => %w[sed], "timeout 5 awk '{print}' x" => %w[awk],
  "/usr/bin/sed -n 1p x" => %w[sed], "gsed -n 1p x" => %w[sed], "python3.12 -c 1" => %w[python],
  "ssh vm23 'tail -f /var/log/messages | grep relayd'" => %w[tail],
  "ssh -p 22 vm23 ruby -e 'puts 1'" => [], "zsh -c 'cut -d: -f1 /etc/passwd'" => %w[cut],
  "bash -c 'print hi'" => %w[bash], "bash -c 'tail x'" => %w[bash tail],

  'echo "use sed here"' => [], "git grep -n 'head -5' -- ." => [], "{ head -1 x; }" => %w[head],
  "! wc -l x" => %w[wc], "cat <<'EOF'\nsed is fine here\nEOF" => [],
  "ruby -e 'puts 1' && tr a b < x" => %w[tr], "nice -n 5 head x" => %w[head],
  "ls *.log(om[1])" => [], "x=$(wc -l < f)" => %w[wc], "FOO=1 awk 1 x" => %w[awk],
  'echo "$(head -1 x)"' => %w[head], "ls > head" => [], "ls 2>&1 | ruby -ne 'print if /x/'" => [],
  "diff <(sort a) <(head b)" => %w[head], "git log #then sed it" => [],
  "ruby -e 'puts `sed 1p x`'" => [], "env -i PATH=/bin awk 1" => %w[awk]
}.freeze

# The fail-closed scan: a banned command at command position, with an argument or
# flag behind it, in text whose own quotes have been flattened to spaces so it
# reads the same whether it came from a raw hook payload or a shell line. The
# quote flattening is also why prose like "we should find things" matches —
# the scan runs only on input a parser already refused, where there is no
# legitimate command left to protect. The law's list lives in laws.yml and this
# scan names the core text tools by hand: a raw-payload scan that read the law
# would also read everything else the law drags in, and the narrow subset is
# the point.
FAIL_CLOSED_INVOCATION = /
  (?:\A|[;&|(`]|\$\(|\{|\s|["'=]|\/)
  (?:[A-Za-z_]\w*=\S+\s+)*
  (?:sudo\s+|doas\s+|command\s+|exec\s+|env\s+|xargs\s+|timeout\s+\S+\s+|nice\s+(?:-\S+\s+)?)?
  (?:[\w@.%+-]+\/)?
  (?:g?(?:sed|awk|head|tail|cut|find|wc|tr)|(?:perl|python)[\d.]*)\b
  \s+\S
/x.freeze

FAIL_CLOSED_CASES = {
  '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ f"' => true,
  '{"tool_name":"Bash","tool_input":{"command":"find . -name x"}' => true,
  '{"tool_name":"Bash","tool_input":{"command":"x=$(wc -l < f)"}' => true,
  "not json at all" => false,
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}' => false,
  '{"tool_name":"Bash"}' => false,
}.freeze

def fail_closed_invocation?(text)
  FAIL_CLOSED_INVOCATION.match?(text.to_s.tr('"', "\s"))
end

def self_test
  failures = SELF_TEST_CASES.reject { |cmd, want| TOOLS.banned_in(cmd).sort == want.sort }
  failures.each { |cmd, want| puts "FAIL #{cmd.inspect}: want #{want}, got #{TOOLS.banned_in(cmd)}" }
  closed = FAIL_CLOSED_CASES.reject { |text, want| fail_closed_invocation?(text) == want }
  closed.each { |text, want| puts "FAIL fail-closed #{text.inspect}: want #{want}, got #{fail_closed_invocation?(text)}" }
  total = SELF_TEST_CASES.size + FAIL_CLOSED_CASES.size
  misses = failures.size + closed.size
  puts "#{total - misses}/#{total} pass"
  exit(misses.zero? ? 0 : 1)
end

self_test if ARGV.first == "--test"

raw = $stdin.read
payload = begin
  JSON.parse(raw)
rescue JSON::ParserError => e
  if fail_closed_invocation?(raw)
    warn "zsh law: unreadable hook payload (#{e.class}), and its text carries a banned-command " \
         "invocation (sed, awk, head, tail, wc, tr, cut, find, perl, python); refusing what it " \
         "cannot read rather than passing it. Reissue the command as readable JSON."
    exit 2
  end
  warn "zsh law: unreadable hook payload (#{e.class}); letting it through"
  exit 0
end

command = payload.dig("tool_input", "command").to_s
exit 0 unless payload["tool_name"] == "Bash" && !command.empty?

names = begin
  TOOLS.banned_in(command)
rescue StandardError => e
  if fail_closed_invocation?(command)
    warn "zsh law: could not lex the command (#{e.class}), and it names a banned command at " \
         "command position; refusing it unread. Fix the quoting and reissue, or write the Ruby " \
         "or zsh form."
    exit 2
  end
  warn "zsh law: could not lex the command (#{e.class}); letting it through"
  exit 0
end
exit 0 if names.empty?

warn TOOLS.refusal(names)
exit 2
