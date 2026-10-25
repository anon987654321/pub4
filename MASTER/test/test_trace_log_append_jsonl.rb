# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class TraceLogAppendJsonlTest < Minitest::Test
  LOG = Master::Trace::Log

  def test_rotation_keeps_active_and_rotated_files_within_the_cap
    Dir.mktmpdir("trace-jsonl-cap-") do |dir|
      path = File.join(dir, "events.ndjson")
      8.times do |index|
        LOG.append_jsonl(
          path,
          { "event" => "metric", "detail" => "x" * 80, "n" => index },
          max_bytes: 400,
          mode: 0o600,
          directory_mode: 0o700,
        )
      end

      assert File.file?("#{path}.1")
      assert_operator File.size(path), :<=, 400
      assert_operator File.size("#{path}.1"), :<=, 400
      File.readlines(path, chomp: true).each { |line| JSON.parse(line) }
      File.readlines("#{path}.1", chomp: true).each { |line| JSON.parse(line) }
      assert_operator File.size("#{path}.1"), :>, 0
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o600, File.stat("#{path}.lock").mode & 0o777
      assert_equal 0o700, File.stat(dir).mode & 0o777
    end
  end

  def test_rejects_a_record_larger_than_the_cap
    Dir.mktmpdir("trace-jsonl-oversize-") do |dir|
      path = File.join(dir, "events.ndjson")

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "detail" => "x" * 200 }, max_bytes: 40)
      end
      refute File.exist?(path)
    end
  end

  def test_refuses_a_symlink_destination
    Dir.mktmpdir("trace-jsonl-symlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      target = File.join(dir, "target.ndjson")
      File.write(target, "keep\n")
      File.symlink(target, path)

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "event" => "should-not-write" })
      end
      assert_equal "keep\n", File.read(target)
    end
  end
end
