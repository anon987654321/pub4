# frozen_string_literal: true

require_relative "test_helper"
require "fix/scanner"

# Scan::FindingCache replays a law's findings while the file it read is unchanged, which is only true
# of a law that reads nothing else. A law whose code globs, spawns or asks git reads beyond the file it
# is handed, and replaying it would keep a verdict about a tree that has moved on. This catches those
# spellings; a law that reaches further through a helper elsewhere must still declare itself.
class TestLawReadsBeyondFile < Minitest::Test
  BEYOND_FILE = /Dir\.(?:glob|children|entries|\[)|Open3\.|IO\.popen|CommitGuard|Exec\.capture|\bsystem\(/
  OPENER = /LawDSL\.law|^\s*class \w+ < Law\b/

  def test_every_law_that_reads_beyond_its_file_says_so
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    undeclared = scanner.laws.reject { |law| law.class.reads_beyond_file? }
                        .select { |law| law_source(law).match?(BEYOND_FILE) }

    assert_empty undeclared.map(&:id), "these read more than their file; declare reads_beyond_file?"
  end

  private

  # The DSL block for a LawDSL law, whose class is anonymous; the class body otherwise.
  def law_source(law)
    klass = law.class
    block = klass.name.nil? && klass.dsl_block
    file, line = block ? block.source_location : law.method(:check).source_location
    return "" unless file && File.file?(file)

    lines = File.readlines(file)
    start = opener_index(lines, line - 1)
    lines[start..closing_index(lines, start)].join
  end

  def opener_index(lines, index)
    index -= 1 until index.zero? || lines[index].match?(OPENER)
    index
  end

  def closing_index(lines, start)
    indent = lines[start][/\A\s*/].size
    (start + 1...lines.size).find { |i| lines[i].match?(/^\s*end\b/) && lines[i][/\A\s*/].size == indent } || -1
  end
end
