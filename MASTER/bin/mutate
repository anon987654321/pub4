# frozen_string_literal: true

# Mutate a Ruby source, run its test, restore. A green test that stays green
# after the comparison it claims to cover is inverted is a test of nothing.
#
# Candidates come from Prism's token stream, not from a regex over the text.
# A regex reads a numbered list in a comment ("# 1. Workspace Project") and the
# 8 in "UTF-8" as integers, and `sub` then rewrites the first one in the file
# rather than the one in the code — so a well-documented file reported survivors
# for mutations that changed nothing a test could see. A gate whose failure is
# always noise is a gate people learn to skip.

require "fileutils"
require "prism"
require "tmpdir"

src = File.expand_path(ARGV[0].to_s)
test = File.expand_path(ARGV[1].to_s)
abort("usage: ruby tools/mutate.rb <source.rb> <test.rb>") unless File.file?(src) && File.file?(test)

root = File.expand_path("..", __dir__)
original = File.read(src)
tokens = Prism.lex(original).value.map(&:first)

FLIP = { "==" => "!=", "!=" => "==", "<=" => ">", ">=" => "<", "<" => ">=", ">" => "<=" }.freeze
INTEGER_BUDGET = 8

def rewrite(source, token, text)
  source.dup.tap { |s| s[token.location.start_offset...token.location.end_offset] = text }
end

def label(token, text)
  "#{text} at line #{token.location.start_line}"
end

mutations = []

seen_operators = {}
tokens.each do |token|
  flip = FLIP[token.value]
  next unless flip && !seen_operators[token.value]

  seen_operators[token.value] = true
  mutations << [label(token, "flip #{token.value}"), rewrite(original, token, flip)]
end

tokens.select { |token| token.type == :INTEGER && token.value.to_i.positive? }
      .first(INTEGER_BUDGET)
      .each { |token| mutations << [label(token, "#{token.value}+1"), rewrite(original, token, (token.value.to_i + 1).to_s)] }

# A receiver's `.reject` and `.select`, never a local of that name.
tokens.each_cons(2) do |dot, call|
  next unless dot.type == :DOT && call.type == :IDENTIFIER

  swap = { "reject" => "select", "select" => "reject" }[call.value]
  next unless swap

  mutations << [label(call, "#{call.value}→#{swap}"), rewrite(original, call, swap)]
end

survivors = []
mutations.each do |name, mutated|
  next if mutated == original

  begin
    File.write(src, mutated)
    ok = system(RbConfig.ruby, "-Ilib", "-Itest", test,
                chdir: root, out: File::NULL, err: File::NULL)
    survivors << name if ok
  ensure
    File.write(src, original)
  end
end
if survivors.empty?
  puts "mutate: #{mutations.size} mutation(s), 0 survivors"
  exit 0
end

survivors.each { |name| puts "  survived: #{name}" }
abort "mutate: #{survivors.size}/#{mutations.size} mutation(s) survived — the test does not catch them"
