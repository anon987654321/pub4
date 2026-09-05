# frozen_string_literal: true

require_relative "dilla_helper"
require "fileutils"
require "tmpdir"

# A named take in OUTPUT_DIR is irreplaceable. The write site refuses rather
# than overwrite, unless DILLA_OVERWRITE=1. Scratch is PID-scoped and still
# overwrites; a retry of the same destination in one process is not a second take.
class TestTakeWrite < Minitest::Test
  def test_refuses_an_existing_named_take
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      File.write(path, "x")
      err = assert_raises(SystemExit) { send(:refuse_existing_take!, path) }
      assert_match(/refusing to overwrite existing take/, err.message)
      assert_includes err.message, path
      assert_match(/DILLA_OVERWRITE=1/, err.message)
      assert_equal "x", File.read(path)
    end
  end

  def test_overwrite_env_allows_the_write
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      File.write(path, "x")
      with_env("DILLA_OVERWRITE" => "1") { send(:refuse_existing_take!, path) }
    end
  end

  def test_scratch_still_overwrites
    path = File.join(SCRATCH_DIR, "dilla_take_write_#{Process.pid}.wav")
    FileUtils.mkdir_p(SCRATCH_DIR)
    File.write(path, "x")
    begin
      send(:refuse_existing_take!, path)
    ensure
      FileUtils.rm_f(path)
    end
  end

  def test_a_retry_of_the_same_take_is_not_a_second_take
    Dir.mktmpdir do |dir|
      path = File.join(dir, "loop.wav")
      send(:refuse_existing_take!, path)
      File.write(path, "x")
      send(:refuse_existing_take!, path)
    end
  end

  def test_stream_demo_is_a_rolling_capture
    Dir.mktmpdir do |dir|
      path = File.join(dir, "demo.wav")
      File.write(path, "x")
      with_env("DILLA_STREAMING" => "1", "STREAM_DEMO" => path) do
        send(:refuse_existing_take!, path)
      end
    end
  end
end
