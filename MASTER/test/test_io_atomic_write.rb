# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# Every durable write in the runtime goes through AtomicWrite — standing orders
# state, memory, findings — so a half-written file here is a corrupted runtime,
# and the failure path must not leave a .master_atomic_ temp behind.
class AtomicWriteTest < Minitest::Test
  Writer = Class.new { include Master::Io::AtomicWrite }

  def setup
    @writer = Writer.new
    @dir = Dir.mktmpdir("atomic_write_test")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def path(name = "out.txt") = File.join(@dir, name)

  # A /fix rollback restores File.binread snapshots, and bin/master runs with default_internal UTF-8: the
  # text-mode temp file raised on the first non-ASCII byte, mid-rollback.
  def test_binary_bytes_are_written_as_given_under_a_utf8_default_internal
    previous = Encoding.default_internal
    Encoding.default_internal = Encoding::UTF_8
    bytes = "a — b".b

    @writer.write_atomic(path, bytes)

    assert_equal bytes, File.binread(path)
  ensure
    Encoding.default_internal = previous
  end

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

  def test_a_rewrite_keeps_the_file_executable
    File.write(path("run"), "#!/bin/sh\n")
    File.chmod(0o755, path("run"))

    @writer.write_atomic(path("run"), "#!/bin/sh\necho hi\n")

    assert_equal "755", format("%o", File.stat(path("run")).mode & 0o777)
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

  def test_refuses_a_symlinked_parent_directory
    outside = File.join(@dir, "outside")
    Dir.mkdir(outside, 0o700)
    File.symlink(outside, File.join(@dir, "redirect"))

    error = assert_raises(IOError) do
      @writer.write_atomic(File.join(@dir, "redirect", "escaped.txt"), "private")
    end

    assert_match(/symlinked atomic-write directory/, error.message)
    refute File.exist?(File.join(outside, "escaped.txt"))
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_refuses_a_symlinked_ancestor_before_creating_nested_directories
    outside = File.join(@dir, "outside")
    Dir.mkdir(outside, 0o700)
    File.symlink(outside, File.join(@dir, "redirect"))
    destination = File.join(@dir, "redirect", "new", "deep", "escaped.txt")

    error = assert_raises(IOError) { @writer.write_atomic(destination, "private") }

    assert_match(/symlinked atomic-write directory component/, error.message)
    refute File.exist?(File.join(outside, "new")), "mkdir_p must not create through an ancestor symlink"
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_refuses_a_symlinked_destination_without_changing_its_target
    target = path("outside-target.txt")
    File.write(target, "original target\n")
    destination = path("link.txt")
    File.symlink(target, destination)

    error = assert_raises(IOError) { @writer.write_atomic(destination, "replacement") }

    assert_match(/singly linked regular file/, error.message)
    assert File.symlink?(destination)
    assert_equal "original target\n", File.read(target)
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_refuses_a_hard_linked_destination_without_changing_its_target
    target = path("hard-target.txt")
    File.write(target, "original target\n")
    destination = path("hard-link.txt")
    File.link(target, destination)

    error = assert_raises(IOError) { @writer.write_atomic(destination, "replacement") }

    assert_match(/singly linked regular file/, error.message)
    assert_equal "original target\n", File.read(target)
    assert_equal "original target\n", File.read(destination)
    assert_equal 2, File.stat(target).nlink
    assert_empty Dir.glob(File.join(@dir, ".master_atomic_*"))
  end

  def test_cleanup_tolerates_a_missing_temp
    assert_nil @writer.cleanup_atomic_temp(nil)
  end
end
