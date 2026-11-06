# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/trace/log"
require_relative "../lib/trace/dmesg"

# bin/master sets Encoding.default_internal to UTF-8, so a text-mode write
# transcodes, and bytes read from a file or a tool raise on their first
# non-ASCII byte. Both writers here met a "—" that way during /fix.
class TestBinaryTextWrites < Minitest::Test
  DASH = "law - finding".b

  def with_default_internal
    previous = Encoding.default_internal
    silence_warnings { Encoding.default_internal = Encoding::UTF_8 }
    yield
  ensure
    silence_warnings { Encoding.default_internal = previous }
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  def test_compacting_a_rotated_log_keeps_non_ascii_records
    Dir.mktmpdir do |dir|
      path = File.join(dir, "hits.jsonl")
      File.binwrite(path, "#{"x" * 40}\n#{DASH}\n#{DASH}\n")
      File.chmod(0o600, path)

      with_default_internal { Master::Trace::Log.compact_rotated(path, 40) }

      assert_equal "#{DASH}\n#{DASH}\n".b, File.binread(path)
    end
  end

  def test_a_dmesg_line_built_from_bytes_is_written
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.log")
      with_default_internal do
        File.open(path, "w") { |io| Master::Trace::Dmesg.emit(DASH, io:, force: true) }
      end

      assert_includes File.read(path, encoding: "UTF-8"), "law - finding"
    end
  end
end
