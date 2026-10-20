# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/where"

# The locator names a definition by tree, file and line, and a file by every place its basename lives.
class TestToolsWhere < Minitest::Test
  def test_finds_a_module_by_name_with_its_line
    rows = Operator::Where.definitions("Chords")
    assert(rows.any? { |row| row.start_with?("STUDIO/dilla/dilla.rb:") && row.include?("module Chords") })
  end

  def test_finds_every_file_that_shares_a_basename
    rows = Operator::Where.files("session.rb")
    assert_operator rows.size, :>=, 4
    assert(rows.all? { |row| row.end_with?("session.rb") })
  end

  def test_a_name_nobody_defines_finds_nothing
    assert_empty Operator::Where.definitions("NoSuchConstantAnywhereAtAll")
  end
end
