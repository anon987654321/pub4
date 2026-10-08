# frozen_string_literal: true

require_relative "test_helper"

class TestSnapshotArtifact < Minitest::Test
  # /critique's snapshot_artifact byte-truncates file contents (SNAPSHOT_FILE_BYTES = 8000)
  # via String#b so a byte limit can't be exceeded by a multi-byte char -- but that leaves
  # the result tagged BINARY. Concatenating it into a UTF-8 prompt (every /critique persona
  # does this) raised Encoding::CompatibilityError whenever the byte cut landed mid-character
  # and the surviving bytes weren't valid ASCII -- confirmed live: every persona failing
  # identically across every /critique this session, until this was found and fixed.
  def test_truncated_multibyte_content_stays_valid_utf8
    Dir.mktmpdir do |dir|
      # "€" is 3 bytes in UTF-8; repeating it means byte offset 8000 (not a
      # multiple of 3) reliably lands mid-character.
      path = File.join(dir, "sample.rb")
      File.write(path, "€" * 4000)

      result = Master::CLI::CommandRegistry.snapshot_artifact(path)

      refute_equal Encoding::ASCII_8BIT, result.encoding, "must not stay tagged BINARY -- that's what crashed every /critique persona"
      assert result.valid_encoding?, "truncated snapshot must be valid in its own encoding"
    end
  end

  def test_truncated_dir_snapshot_stays_valid_utf8
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "€" * 4000)
      File.write(File.join(dir, "b.rb"), "hello world\n")

      result = Master::CLI::CommandRegistry.snapshot_artifact(dir)

      refute_equal Encoding::ASCII_8BIT, result.encoding, "must not stay tagged BINARY -- that's what crashed every /critique persona"
      assert result.valid_encoding?, "truncated dir snapshot must be valid in its own encoding"
    end
  end
end
