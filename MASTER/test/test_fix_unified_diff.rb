# frozen_string_literal: true

require_relative "test_helper"
require "fix/change_scope"

# git's diff read into hunks: one file's for a repair, a whole commit's for the
# pre-commit lint, and a span when git cannot run.
class TestFixUnifiedDiff < Minitest::Test
  Diff = Master::Fix::UnifiedDiff

  IDENTITY = %w[-c user.name=t -c user.email=t@example.com].freeze

  def git(dir, *args)
    out, status = Master::Io::Exec.capture2e("git", "-C", dir, *IDENTITY, *args)
    assert status.success?, out
    out
  end

  def write(dir, files)
    files.each do |name, text|
      path = File.join(dir, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
  end

  def numbered(count) = (1..count).map { |n| "line #{n}\n" }.join

  # The commit the hook lints: a file grown by an added line that reads like a header,
  # a file deleted, and a one-line edit.
  def commit_diff(dir)
    git(dir, "init", "-q")
    write(dir, "lib/a.rb" => numbered(5), "lib/gone.rb" => "bye\n", "b.css" => numbered(9))
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "base")

    write(dir, "lib/a.rb" => numbered(5).lines.insert(3, "++ looks like a header\n", "two\n").join,
               "b.css" => numbered(9).sub("line 7", "seven"))
    File.delete(File.join(dir, "lib/gone.rb"))
    git(dir, "diff", "-U0", "HEAD")
  end

  def test_a_commits_diff_gives_one_scope_per_path_with_a_new_side
    Dir.mktmpdir do |dir|
      scopes = Master::Fix::ChangeScope.from_diff(commit_diff(dir))

      assert_equal %w[b.css lib/a.rb], scopes.keys.sort
      assert_equal [4..5], scopes["lib/a.rb"].new_ranges
      assert scopes["lib/a.rb"].grew?
      assert_equal [7..7], scopes["b.css"].new_ranges
      refute scopes["b.css"].grew?
    end
  end

  def test_hunk_text_is_both_sides_without_their_marks
    hunks = Diff.hunks(Diff.between("a\nb\nc\n", "a\nB\nc\n"))

    assert_equal ["b\nB\n"], hunks.map(&:text)
  end

  # When git cannot run, the common prefix and suffix are trimmed and the rest is one hunk.
  def test_without_git_the_span_between_prefix_and_suffix_is_the_change
    old = numbered(10)
    new = old.sub("line 3", "three").sub("line 7", "seven")
    diff = Master::Io::Exec.stub(:capture2e, ->(*) { raise Errno::ENOENT, "git" }) do
      Master::Ground::Swallow.stub(:log, nil) { Diff.between(old, new) }
    end

    assert_nil diff
    assert_equal 3..7, Diff.span(old, new).new_range
    assert_equal 3..3, Diff.span(old, old.lines.insert(2, "x\n").join).new_range
  end
end
