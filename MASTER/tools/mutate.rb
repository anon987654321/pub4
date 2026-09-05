# frozen_string_literal: true

# Mutate a Ruby source, run its test, restore. A green test that stays green
# after the comparison it claims to cover is inverted is a test of nothing.

require "fileutils"
require "tmpdir"

src = File.expand_path(ARGV[0].to_s)
test = File.expand_path(ARGV[1].to_s)
abort("usage: ruby tools/mutate.rb <source.rb> <test.rb>") unless File.file?(src) && File.file?(test)

root = File.expand_path("..", __dir__)
original = File.read(src)
mutations = []

original.scan(/\s(==|!=|<=|>=|<|>)\s/).flatten.uniq.each do |op|
  flip = { "==" => "!=", "!=" => "==", "<=" => ">", ">=" => "<", "<" => ">=", ">" => "<=" }[op]
  next unless flip && original.include?(" #{op} ")

  mutations << ["flip #{op}", original.sub(" #{op} ", " #{flip} ")]
end
original.scan(/\b(\d+)\b/).flatten.uniq.first(8).each do |n|
  next if n.to_i.zero?

  mutations << ["#{n}+1", original.sub(/\b#{n}\b/, (n.to_i + 1).to_s)]
end
mutations << ["reject→select", original.sub(".reject", ".select")] if original.match?(/\.reject\b/)
mutations << ["select→reject", original.sub(".select", ".reject")] if original.match?(/\.select\b/)

survivors = []
mutations.each do |label, mutated|
  next if mutated == original

  begin
    File.write(src, mutated)
    ok = system(RbConfig.ruby, "-Ilib", "-Itest", test,
                chdir: root, out: File::NULL, err: File::NULL)
    survivors << label if ok
  ensure
    File.write(src, original)
  end
end
if survivors.empty?
  puts "mutate: #{mutations.size} mutation(s), 0 survivors"
  exit 0
end

survivors.each { |label| puts "  survived: #{label}" }
abort "mutate: #{survivors.size}/#{mutations.size} mutation(s) survived — the test does not catch them"
