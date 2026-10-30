# frozen_string_literal: true

require_relative "test_helper"
require "fix/scanner"

# Scan::FindingCache replays a law's findings while the file it read is unchanged, which is only true
# of a law that reads nothing else. A law whose code globs, spawns or asks git reads beyond the file it
# is handed, and replaying it would keep a verdict about a tree that has moved on. This catches those
# spellings; a law that reaches further through a helper elsewhere must still declare itself.
class TestLawReadsBeyondFile < Minitest::Test
  BEYOND_FILE = /Dir\.(?:glob|children|entries|\[)|Open3\.|IO\.popen|CommitGuard|Exec\.capture|\bsystem\(/
  OPENER = /::Law\.define|^\s*class \w+ < Detector\b/

  def test_every_law_that_reads_beyond_its_file_says_so
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    undeclared = scanner.laws.reject { |law| law.reads_beyond_file? || test_defined?(law) }
                        .select { |law| law_source(law).match?(BEYOND_FILE) }

    assert_empty undeclared.map(&:id), "these read more than their file; declare reads_beyond_file?"
  end

  private

  # Scanner registries are process-local, and Minitest loads test-defined Law
  # subclasses into the same inherited registry. Those fixtures are not shipped
  # scanner laws and must not be judged as production code.
  def test_defined?(law)
    klass = law.class
    location = klass.name && Object.const_source_location(klass.name)&.first
    location ||= law.method(:check).source_location&.first
    location&.match?(%r{(?:\A|/)(?:test|spec)/})
  end

  # A Law's `check` block, or its detector class's #check.
  def law_source(law)
    definition = law.respond_to?(:definition) ? law.definition : nil
    block = definition&.check || definition&.detect
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
