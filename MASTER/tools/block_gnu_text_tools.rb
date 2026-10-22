#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Bash: refuses a command that runs sed, awk, perl, python, head, tail, tr, cut, wc or
# find, and names the Ruby or zsh form instead. This repo deploys to OpenBSD, where GNU idioms break, and
# its house law is Ruby and zsh, not GNU text tools.

# Looking only at the word after | ; & ( $( or a backtick misses `do wc`, `{ head`, `! wc`, `xargs sed`,
# `timeout 5 awk`, `FOO=1 awk`, `/usr/bin/sed`, `gsed`, `python3.12`, `zsh -c 'cut ...'` and
# `ssh vm23 'tail -f ...'`. So the hook lexes the line into simple commands, walks past assignments,
# reserved words and wrappers to the real command name, and re-checks what sh -c and ssh are handed.
# Quoted words, heredoc bodies, comments and redirect targets are data and never trip it.

# Contract (https://code.claude.com/docs/en/hooks): hook JSON on stdin carries tool_name and
# tool_input.command; exit 2 blocks the call and stderr is the reason Claude reads. An unreadable
# payload passes, because this guard must never be the reason a shell stops working. It is wired under
# hooks.PreToolUse in .claude/settings.json with matcher "Bash" and the command
# ruby "$CLAUDE_PROJECT_DIR/MASTER/tools/block_gnu_text_tools.rb"; --test runs the built-in cases.

require "json"
require_relative "shell_lexer"

SCRIPTING = "Ruby (ruby -e, ruby -ne); perl and python are banned in agent shell calls"

BANNED = {
  "sed" => "Edit tool; or ruby -i -pe 'sub(/a/, \"b\")' FILE; ruby -ne 'print if (10..20) === $.' FILE",
  "awk" => "ruby -ane 'puts $F[1]' FILE (-F: for a separator); " \
           "sums: ruby -ane 's = s.to_i + $F[2].to_i; END { p s }'",
  "head" => "Read tool with limit; ruby -e 'puts File.foreach(ARGV[0]).first(20)' FILE; " \
            "zsh: print -l ${${(f)\"$(<FILE)\"}[1,20]}",
  "tail" => "Read tool with offset; ruby -e 'puts File.readlines(ARGV[0]).last(20)' FILE",

  "wc" => "ruby -e 'p File.foreach(ARGV[0]).count' FILE; zsh: print ${#${(f)\"$(<FILE)\"}}; " \
          "files: print ${#$(print -l *.rb)}",
  "tr" => "ruby -pe '$_.tr!(\"a-z\", \"A-Z\")'; zsh: ${(U)var}, ${var//,/ }",
  "cut" => "ruby -F: -ane 'puts $F[0]' FILE; zsh: ${${(s.:.)line}[1]}",
  "find" => "zsh globs: **/*.rb(.mh-24), *(.om[1]), **/*(.Lm+10); git ls-files for tracked files",
  "perl" => SCRIPTING,
  "python" => SCRIPTING,
}.freeze

RESERVED = %w[if then else elif fi do done while until for in case esac select function time ! { } [[ ]]].freeze
SHELLS = %w[sh bash zsh ksh dash].freeze
ASSIGNMENT = /\A[A-Za-z_]\w*(\[[^\]]*\])?=/

# Wrappers run the command that follows them. Each entry lists the flags that take a value.
WRAPPERS = {
  "env" => %w[-u -C -S], "exec" => %w[-a], "command" => [], "builtin" => [], "noglob" => [],
  "nohup" => [], "sudo" => %w[-u -g -C -D -h -p -U], "doas" => %w[-u -C], "nice" => %w[-n],
  "timeout" => %w[-s -k --signal --kill-after], "xargs" => %w[-n -I -J -L -P -d -E -s -R -S],
  "caffeinate" => %w[-t -w], "stdbuf" => %w[-i -o -e]
}.freeze

# The bare operand a wrapper takes before its command: timeout's duration, nice's old-style increment.
WRAPPER_OPERANDS = { "timeout" => /\A[\d.]+[smhd]?\z/, "nice" => /\A-?\d+\z/ }.freeze
SSH_VALUE_FLAGS = %w[-b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w].freeze

# GNU names (gsed, gawk) and versioned interpreters (python3.12, perl5.36) reduce to the base name.
def canonical(word)
  name = File.basename(word).sub(/\Apython[\d.]*\z/, "python").sub(/\Aperl[\d.]*\z/, "perl")
  bare = name.delete_prefix("g")
  name.start_with?("g") && BANNED.key?(bare) ? bare : name
end

def split_simple_commands(tokens)
  groups = tokens.slice_when { |left, right| left.first == :op || right.first == :op }
  groups.reject { |group| group.first.first == :op }.map { |group| group.map(&:last) }
end

# Walks past assignments, reserved words and wrappers to the command a simple command actually runs.
def command_words(words)
  words = words.dup
  loop do
    words.shift while words.first&.match?(ASSIGNMENT) || RESERVED.include?(words.first)
    head = words.first
    return words unless head && WRAPPERS.key?(File.basename(head))

    skip_wrapper(words, head)
  end
end

def skip_wrapper(words, head)
  name = File.basename(head)
  value_flags = WRAPPERS.fetch(name)
  words.shift
  while (width = flag_width(words.first, value_flags, env: head == "env")).positive?
    words.shift(width)
  end

  operand = WRAPPER_OPERANDS[name]
  words.shift if operand && words.first&.match?(operand)
end

# How many words a wrapper's leading flag occupies: two for a flag with a value, none past the flags.
def flag_width(flag, value_flags, env:)
  return 0 unless flag
  return 2 if value_flags.include?(flag)

  flag.start_with?("-") || (env && flag.include?("=")) ? 1 : 0
end

# The remote command of `ssh [opts] host cmd...`, joined the way ssh joins it.
def ssh_remote(args)
  args = args.dup
  while (flag = args.first)&.start_with?("-")
    args.shift
    args.shift if SSH_VALUE_FLAGS.include?(flag)
  end

  args.shift
  args.join(" ")
end

# The command string a shell runs with -c, or ssh runs remotely; nil for any other command.
def inner_command(name, argv)
  return ssh_remote(argv.drop(1)) if name == "ssh"
  return unless SHELLS.include?(name)

  flag = argv.index { |word| word.match?(/\A-\w*c\w*\z/) }
  argv[flag + 1].to_s if flag
end

def banned_in(src, depth = 0)
  return [] if depth > 4

  lexer = ShellLexer.new(src)
  found = lexer.nested.flat_map { |inner| banned_in(inner, depth + 1) }
  split_simple_commands(lexer.tokens).each { |words| found.concat(banned_in_argv(command_words(words), depth)) }
  found.uniq
end

def banned_in_argv(argv, depth)
  return [] if argv.empty?

  name = canonical(argv.first)
  found = BANNED.key?(name) ? [name] : []
  inner = inner_command(name, argv)
  found.concat(banned_in(inner, depth + 1)) if inner
  found
end

def refusal(names)
  lines = ["coreutils: #{names.join(", ")} refused here. This repo deploys to OpenBSD; write Ruby or zsh."]
  names.each { |name| lines << "  #{name}: #{BANNED.fetch(name)}" }
  lines << "  Search with git grep; read files with the Read tool; one meaningful operation per line."
  lines.join("\n")
end

SELF_TEST_CASES = {
  "git status" => [], "sed -i s/a/b/ x" => %w[sed], "ls | head -5" => %w[head],
  "for f in *.rb; do wc -l $f; done" => %w[wc], "if true; then tail -n 3 x; fi" => %w[tail],
  "git ls-files | xargs sed -n 1p" => %w[sed], "timeout 5 awk '{print}' x" => %w[awk],
  "/usr/bin/sed -n 1p x" => %w[sed], "gsed -n 1p x" => %w[sed], "python3.12 -c 1" => %w[python],
  "ssh vm23 'tail -f /var/log/messages | grep relayd'" => %w[tail],
  "ssh -p 22 vm23 ruby -e 'puts 1'" => [], "zsh -c 'cut -d: -f1 /etc/passwd'" => %w[cut],

  'echo "use sed here"' => [], "git grep -n 'head -5' -- ." => [], "{ head -1 x; }" => %w[head],
  "! wc -l x" => %w[wc], "cat <<'EOF'\nsed is fine here\nEOF" => [],
  "ruby -e 'puts 1' && tr a b < x" => %w[tr], "nice -n 5 head x" => %w[head],
  "ls *.log(om[1])" => [], "x=$(wc -l < f)" => %w[wc], "FOO=1 awk 1 x" => %w[awk],
  'echo "$(head -1 x)"' => %w[head], "ls > head" => [], "ls 2>&1 | ruby -ne 'print if /x/'" => [],
  "diff <(sort a) <(head b)" => %w[head], "git log #then sed it" => [],
  "ruby -e 'puts `sed 1p x`'" => [], "env -i PATH=/bin awk 1" => %w[awk]
}.freeze

def self_test
  failures = SELF_TEST_CASES.reject { |cmd, want| banned_in(cmd).sort == want.sort }
  failures.each { |cmd, want| puts "FAIL #{cmd.inspect}: want #{want}, got #{banned_in(cmd)}" }
  puts "#{SELF_TEST_CASES.size - failures.size}/#{SELF_TEST_CASES.size} pass"
  exit(failures.empty? ? 0 : 1)
end

self_test if ARGV.first == "--test"

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "coreutils: unreadable hook payload (#{e.class}); letting it through"
  exit 0
end

command = payload.dig("tool_input", "command").to_s
exit 0 unless payload["tool_name"] == "Bash" && !command.empty?

names = begin
  banned_in(command)
rescue StandardError => e
  warn "coreutils: could not lex the command (#{e.class}); letting it through"
  exit 0
end
exit 0 if names.empty?

warn refusal(names)
exit 2
