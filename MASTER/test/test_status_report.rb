# frozen_string_literal: true

require_relative "test_helper"
require "pub4/status_report"

# `bin/pub4 status` tells one session which trees hold another session's
# uncommitted work. That line is the repo's answer to a shared checkout, so it
# has to name the trees correctly — a mangled name reads as a tree nobody
# recognises, and the reflex is to ignore the line rather than to distrust it.
class TestStatusReport < Minitest::Test
  def tree_of(line) = Pub4::StatusReport.allocate.send(:tree_of, line)

  # git quotes a path the moment it holds a space or a non-ASCII byte, which
  # STUDIO/dilla produces routinely. Unquoted, `STUDIO/dilla/før.wav` tallied
  # under the tree `"STUDIO`.
  def test_a_quoted_path_is_attributed_to_its_real_tree
    assert_equal "RAILS", tree_of(%q{ M "RAILS/sp ace.rb"})
    assert_equal "STUDIO", tree_of(%q{?? "STUDIO/dilla/f\303\270r.wav"})
  end

  # A rename reports `<old> -> <new>`, and the tree that holds the file now is
  # the one a session needs to be warned about.
  def test_a_rename_is_attributed_to_where_the_file_landed
    assert_equal "OPENBSD", tree_of("R  RAILS/old.rb -> OPENBSD/new.rb")
  end

  def test_the_ordinary_shapes_still_work
    assert_equal "RAILS", tree_of(" M RAILS/a.rb")
    assert_equal "STUDIO", tree_of("?? STUDIO/b")
    assert_equal "MASTER", tree_of("MM MASTER/lib/core/world.rb")
  end

  # Blank and whitespace-only lines are not a tree called "".
  def test_a_line_with_no_path_is_not_a_tree
    assert_nil tree_of("   ")
    assert_nil tree_of("")
  end

  # The offset itself is correct and deliberately unchanged: quoting alters the
  # path, not the two status characters before it. Pinned because the obvious
  # reading of the quoting bug blames the slice, and "fixing" that would break
  # every ordinary line above.
  def test_the_status_prefix_is_two_characters_and_a_space
    assert_equal "RAILS", tree_of(" M RAILS/a.rb")
    assert_equal "RAILS", tree_of("A  RAILS/a.rb")
  end

  # The bug that produced "dirty in ASTER: 1" beside a correct MASTER.
  #
  # In porcelain the leading whitespace is DATA — an unstaged modification is
  # " M path" — and the reader did `out.strip`, which ate that space off the
  # FIRST line only. So the tree of whichever file sorted first lost a character
  # whenever that file was unstaged-modified, and was tallied as its own tree.
  # Intermittent, and invisible unless you happened to read the line.
  def test_the_first_line_keeps_its_leading_status_space
    porcelain = " M MASTER/lib/a.rb\n?? MASTER/test/b.rb\n M RAILS/c.rb\n"

    assert_equal({ "MASTER" => 2, "RAILS" => 1 },
                 porcelain.rstrip.lines.filter_map { |line| tree_of(line) }.tally)

    # The contrast, stated as fact rather than asserted of tree_of — which is not
    # the thing at fault. strip damages the line before any parser sees it, and
    # rstrip leaves it intact. This is the whole difference the fix turns on.
    assert_equal "ASTER", tree_of(porcelain.strip.lines.first), "strip eats the leading status space"
    assert_equal "MASTER", tree_of(porcelain.rstrip.lines.first), "rstrip preserves it"
  end
end
