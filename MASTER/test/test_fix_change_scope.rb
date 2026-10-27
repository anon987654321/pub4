# frozen_string_literal: true

require_relative "test_helper"
require "fix/change_scope"

# One reading of what a repair changed, for every per-fix check. Each case is
# one the separate readings disagreed on, or one git's bytes could break.
class TestFixChangeScope < Minitest::Test
  Scope = Master::Fix::ChangeScope

  def numbered(count) = (1..count).map { |n| "line #{n}\n" }

  def test_an_identical_file_changed_nothing
    scope = Scope.between("a\nb\n", "a\nb\n")

    assert_empty scope
    refute scope.covers?(line: 1)
    assert_equal 0, scope.line_delta
  end

  def test_a_replaced_line_is_one_hunk_on_both_sides
    old = numbered(10)
    new = old.dup.tap { |lines| lines[4] = "five\n" }
    scope = Scope.between(old.join, new.join)

    assert_equal 5..5, scope.hunks.first.old_range
    assert_equal [5..5], scope.new_ranges
    assert scope.covers?(line: 5)
    refute scope.covers?("line" => 4)
    refute scope.grew?
  end

  def test_an_insertion_covers_its_new_lines_and_grows_the_file
    old = numbered(10)
    new = old.dup.insert(3, "added a\n", "added b\n")
    scope = Scope.between(old.join, new.join)

    assert_equal [4..5], scope.new_ranges
    assert_equal 3..3, scope.hunks.first.old_range, "an insertion sits at the old line it follows"
    assert scope.covers?(line: 4)
    refute scope.covers?(line: 6)
    assert_equal 2, scope.line_delta
  end

  def test_a_deletion_covers_the_seam_it_leaves_and_shrinks_the_file
    old = numbered(10)
    new = old.dup.tap { |lines| lines.slice!(4, 3) }
    scope = Scope.between(old.join, new.join)

    assert_equal 5..7, scope.hunks.first.old_range
    assert_equal [4..4], scope.new_ranges
    assert scope.covers?(line: 4), "a finding where the deletion closed up is the deletion's"
    assert_equal(-3, scope.line_delta)
    refute scope.grew?
  end

  # A block moved down the file is a deletion and an insertion; nothing between them changed.
  def test_a_moved_block_is_two_hunks_and_the_lines_between_are_untouched
    old = numbered(20)
    new = old.dup
    block = new.slice!(1, 2)
    new.insert(16, *block)
    scope = Scope.between(old.join, new.join)

    assert_equal 2, scope.hunks.size
    refute scope.covers?(line: 8)
    assert scope.covers?(line: 17)
    assert_equal 0, scope.line_delta
  end

  def test_crlf_lines_are_compared_whole
    crlf = ->(*lines) { lines.map { |line| "#{line}\r\n" }.join }
    scope = Scope.between(crlf.call("a", "b", "c"), crlf.call("a", "B", "c"))

    assert_equal [2..2], scope.new_ranges
    assert_equal crlf.call("b", "B"), scope.hunks.first.text
  end

  # git called a file with a NUL or an invalid byte binary and gave no hunks; every check then
  # read "nothing changed".
  def test_non_utf8_and_nul_bytes_still_give_hunks
    old = ["ok\n", "\xFF\xFE\n", "\x00tail\n"].join.b
    new = ["ok\n", "\xFF\xFD\n", "\x00tail\n"].join.b
    scope = Scope.between(old, new)
    text = scope.hunks.first.text

    assert_equal [2..2], scope.new_ranges
    assert text.valid_encoding?
  end

  def test_an_empty_file_and_a_new_file
    created = Scope.between("", "one\ntwo\n")

    assert_equal [1..2], created.new_ranges
    assert created.grew?
    assert_nil created.size_ratio, "an empty file has no size to shrink from"

    emptied = Scope.between("one\ntwo\n", "")
    assert_equal 1..2, emptied.hunks.first.old_range
    assert_in_delta 0.0, emptied.size_ratio
    assert_in_delta 0.5, Scope.between("x" * 100, "x" * 50).size_ratio
  end
end
