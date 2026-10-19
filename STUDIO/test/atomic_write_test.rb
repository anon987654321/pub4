# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../replicate/atomic_write"

class StudioAtomicWriteTest < Minitest::Test
  def writer_with_sync_log
    synced = []
    writer = Object.new.extend(Studio::AtomicWrite)
    writer.define_singleton_method(:fsync_directory) do |directory|
      synced << File.expand_path(directory)
    end
    [writer, synced]
  end

  def test_write_atomic_publishes_complete_content_and_syncs_parent
    Dir.mktmpdir do |directory|
      path = File.join(directory, "artifact.json")
      File.write(path, "old")
      File.chmod(0o640, path)
      writer, synced = writer_with_sync_log

      writer.write_atomic(path, "new")

      assert_equal "new", File.read(path)
      assert_equal 0o640, File.stat(path).mode & 0o777
      assert_equal([File.expand_path(directory)], synced) if RUBY_PLATFORM !~ /win32|mingw/
    end
  end

  def test_copy_atomic_publishes_complete_content_and_syncs_parent
    Dir.mktmpdir do |directory|
      source = File.join(directory, "source.bin")
      destination = File.join(directory, "destination.bin")
      File.binwrite(source, "\x00payload".b)
      writer, synced = writer_with_sync_log

      writer.copy_atomic(source, destination)

      assert_equal "\x00payload".b, File.binread(destination)
      assert_equal([File.expand_path(directory)], synced) if RUBY_PLATFORM !~ /win32|mingw/
    end
  end
end
