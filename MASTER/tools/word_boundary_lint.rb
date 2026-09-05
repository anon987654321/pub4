# frozen_string_literal: true

# \b next to punctuation has now cost this repo three incidents: TODO.md read
# as a work marker, and OPEN_CLOSED's is_a? clause which could never match.
# A word boundary needs a word character beside it.

root = File.expand_path("..", __dir__)
# Only the shape that cannot fire: \b glued to escaped punctuation, so the
# boundary demands a word character next to something that is not one.
# `\bis_a\?\b` is the worked example. `\bTODO\b` is a real boundary.
bad = /\\[.?()\[\]{}|*+^$\/]\\b|\\b\\[.?()\[\]{}|*+^$\/]/
hits = []

scan = lambda do |path, text|
  text.each_line.with_index(1) do |line, number|
    next unless line.include?("\\b")
    next if line.strip.start_with?("#")
    next unless line.match?(bad)

    hits << "#{path.sub("#{root}/", "")}:#{number}: #{line.strip}"
  end
end

rules = File.join(root, "data", "rules.yml")
scan.call(rules, File.read(rules)) if File.file?(rules)

Dir.glob(File.join(root, "law", "*.rb")).each { |path| scan.call(path, File.read(path)) }
Dir.glob(File.join(root, "lib", "review", "scan", "rules", "*.rb")).each { |path| scan.call(path, File.read(path)) }

if hits.empty?
  puts "word_boundary: clean"
  exit 0
end

hits.each { |hit| puts hit }
abort "word_boundary: #{hits.size} \\b adjacent to punctuation"
