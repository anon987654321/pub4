# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

# TODO.md, Test coverage: no test named AtomicWrite. Every durable write in the
# runtime goes through it — standing orders state, memory, findings — so a
# half-written file here is a corrupted runtime, and the failure path (leaving a
# .master_atomic_ temp behind on error) was never exercised.
class AtomicWriteTest < Minitest::Test
  Writer = Class.new { include Master::Ground::AtomicWrite }

  def setup
    @writer = Writer.new
    @dir = Dir.mktmpdir("atomic_write_test")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def path(name = "out.txt") = File.join(@dir, name)

  def test_writes_content_and_returns_the_path
    result = @writer.write_atomic(path, "hello")

    assert_equal path, result
    assert_equal "hello", File.read(path)
  end

  def test_creates_missing_parent_directories
    nested = File.join(@dir, "a", "b", "c.txt")
    @writer.write_atomic(nested, "deep")

    assert_equal "deep", File.read(nested)
  end

  def test_replaces_an_existing_file_without_leaving_a_temp_behind
    @writer.write_atomic(path, "first")
    @writer.write_atomic(path, "second")

    assert_equal "second", File.read(path)
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_applies_the_requested_mode
    @writer.write_atomic(path, "x", mode: 0o600)

    assert_equal "600", format("%o", File.stat(path).mode & 0o777)
  end

  def test_default_mode_is_readable
    @writer.write_atomic(path, "x")

    assert_equal "644", format("%o", File.stat(path).mode & 0o777)
  end

  def test_handles_empty_and_binary_content
    @writer.write_atomic(path("empty"), "")
    assert_equal "", File.read(path("empty"))

    bytes = (0..255).map(&:chr).join.b
    @writer.write_atomic(path("bin"), bytes)
    assert_equal bytes, File.binread(path("bin"))
  end

  # The point of the temp+rename: a reader either sees the old file or the new
  # one, never a partial write. Nothing is left in the directory mid-flight.
  def test_the_target_never_holds_a_partial_write
    @writer.write_atomic(path, "old")
    seen = []
    @writer.stub(:fsync_directory, ->(_dir) { seen << File.read(path) }) do
      @writer.write_atomic(path, "new content")
    end

    assert_equal ["new content"], seen, "rename must happen before the directory fsync"
  end

  def test_a_failed_write_removes_its_temp_file
    error = Class.new(StandardError)
    @writer.stub(:fsync_directory, ->(_dir) { raise error, "disk gone" }) do
      assert_raises(error) { @writer.write_atomic(path, "doomed") }
    end

    # The rename already landed, so the target exists; what must not survive is a
    # stray temp in the same directory.
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_cleanup_tolerates_a_missing_temp
    assert_nil @writer.cleanup_atomic_temp(nil)
  end
end
