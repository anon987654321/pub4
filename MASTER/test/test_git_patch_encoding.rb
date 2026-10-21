# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# A /fix report shows the patch the repair wrote. git's output is bytes; once it passed the line limit
# it was joined to a UTF-8 ellipsis and raised Encoding::CompatibilityError, ending the pass after the
# work was done.
class TestGitPatchEncoding < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("patch-encoding")
    [%w[init -q], %w[config user.email t@example.test], %w[config user.name t]].each { |argv| git(*argv) }

    File.write(File.join(@dir, "note.txt"), "one\n")
    git("add", "note.txt")
    git("commit", "-q", "-m", "base")

    File.write(File.join(@dir, "note.txt"), Array.new(12) { |index| "line #{index} — på norsk\n" }.join)
    @operations = Master::Io::GitOperations.new(@dir)
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_a_long_working_patch_with_non_ascii_text_reads_as_text
    patch = @operations.working_patch(limit: 4)

    assert_equal Encoding::UTF_8, patch.encoding
    assert_includes patch, "more lines of patch"
    assert_predicate patch, :valid_encoding?
  end

  def test_a_short_working_patch_keeps_its_text
    assert_includes @operations.working_patch(limit: 400), "på norsk"
  end

  private

  def git(*argv)
    assert system("git", *argv, chdir: @dir, out: File::NULL, err: File::NULL), "git #{argv.join(" ")}"
  end
end
