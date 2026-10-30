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
# payload passes, because this guard must never be the reason a shell stops working. It is wired under
# hooks.PreToolUse in .claude/settings.json through tools/hook_ruby.rb; --test runs the built-in cases.

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

def self_test
  failures = SELF_TEST_CASES.reject { |cmd, want| TOOLS.banned_in(cmd).sort == want.sort }
  failures.each { |cmd, want| puts "FAIL #{cmd.inspect}: want #{want}, got #{TOOLS.banned_in(cmd)}" }
  puts "#{SELF_TEST_CASES.size - failures.size}/#{SELF_TEST_CASES.size} pass"
  exit(failures.empty? ? 0 : 1)
end

self_test if ARGV.first == "--test"

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "zsh law: unreadable hook payload (#{e.class}); letting it through"
  exit 0
end

command = payload.dig("tool_input", "command").to_s
exit 0 unless payload["tool_name"] == "Bash" && !command.empty?

names = begin
  TOOLS.banned_in(command)
rescue StandardError => e
  warn "zsh law: could not lex the command (#{e.class}); letting it through"
  exit 0
end
exit 0 if names.empty?

warn TOOLS.refusal(names)
exit 2
