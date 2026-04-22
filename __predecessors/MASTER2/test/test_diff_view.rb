# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ui"

class TestDiffView < Minitest::Test
  def test_unified_diff_no_changes
    original = "line 1\nline 2\nline 3\n"
    modified = "line 1\nline 2\nline 3\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt")
    
    # Should have header but no hunks
    assert_match /--- a\/test.txt/, diff
    assert_match /\+\+\+ b\/test.txt/, diff
    refute_match /@@ /, diff
  end

  def test_unified_diff_single_line_change
    original = "line 1\nline 2\nline 3\n"
    modified = "line 1\nmodified line 2\nline 3\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt")
    
    assert_match /--- a\/test.txt/, diff
    assert_match /\+\+\+ b\/test.txt/, diff
    assert_match /@@ /, diff
    assert_match /-line 2/, diff
    assert_match /\+modified line 2/, diff
  end

  def test_unified_diff_addition
    original = "line 1\nline 2\n"
    modified = "line 1\nline 2\nline 3\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt")
    
    assert_match /\+line 3/, diff
  end

  def test_unified_diff_deletion
    original = "line 1\nline 2\nline 3\n"
    modified = "line 1\nline 3\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt")
    
    assert_match /-line 2/, diff
  end

  def test_unified_diff_multiple_changes
    original = "a\nb\nc\nd\ne\n"
    modified = "a\nB\nc\nD\ne\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt")
    
    assert_match /-b/, diff
    assert_match /\+B/, diff
    assert_match /-d/, diff
    assert_match /\+D/, diff
  end

  def test_unified_diff_preserves_filename
    original = "content\n"
    modified = "new content\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "my_file.rb")
    
    assert_match /--- a\/my_file\.rb/, diff
    assert_match /\+\+\+ b\/my_file\.rb/, diff
  end

  def test_unified_diff_context_lines
    original = "1\n2\n3\n4\n5\n6\n7\n8\n9\n"
    modified = "1\n2\n3\n4\nCHANGED\n6\n7\n8\n9\n"
    
    diff = MASTER::DiffView.unified_diff(original, modified, filename: "test.txt", context_lines: 2)
    
    # Should include 2 lines of context before and after the change
    assert_match(/ 3/, diff)
    assert_match(/ 4/, diff)
    assert_match(/-5/, diff)
    assert_match(/\+CHANGED/, diff)
    assert_match(/ 6/, diff)
    assert_match(/ 7/, diff)
  end
end
