# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "stringio"
require_relative "../lib/fix/kernel"

class TestFixKernel < Minitest::Test
  K = Master::Fix::Kernel

  # Writes a valid chain the way an appender must: seq, prev and the body hash.
  def write_log(root, rows)
    previous = K::GENESIS

    lines = rows.each_with_index.map do |(kind, run_id), index|
      body = { "seq" => index + 1, "at" => "2026-10-28T00:00:00Z", "run_id" => run_id,
               "kind" => kind, "payload" => {}, "prev" => previous }
      row = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
      previous = row.fetch("hash")
      JSON.generate(row) + "\n"
    end

    path = File.join(root, K::LOG_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, lines.join)
    File.chmod(0o600, path)
    path
  end

  def with_workspace
    Dir.mktmpdir("pub4-kernel") do |root|
      Dir.mkdir(File.join(root, ".git"))
      yield root
    end
  end

  def test_replay_returns_the_complete_run_for_a_sequence
    with_workspace do |root|
      write_log(root, [%w[run_started a], %w[observation b], %w[terminal a]])

      replay = K.replay_events(root: File.join(root, "MASTER"), seq: 3)
      assert_equal "a", replay.fetch("run_id")
      assert_equal %w[run_started terminal], replay.fetch("events").map { |row| row.fetch("kind") }
      assert_nil K.replay_events(root:, seq: 9)
    end
  end

  def test_replay_cli_exit_codes
    with_workspace do |root|
      write_log(root, [%w[terminal a]])

      assert_equal 64, capture_cli(root, "x")
      assert_equal 1, capture_cli(root, "2")
      assert_equal 0, capture_cli(root, "1")
    end
  end

  def test_replay_cli_reports_a_corrupt_log
    with_workspace do |root|
      path = write_log(root, [%w[terminal a]])
      File.write(path, File.read(path).sub('"kind":"terminal"', '"kind":"changed"'))

      assert_equal 1, capture_cli(root, "1")
    end
  end

  def test_full_verification_refuses_an_incomplete_final_record
    with_workspace do |root|
      path = write_log(root, [%w[terminal a]])
      File.binwrite(path, File.binread(path).delete_suffix("\n"))

      assert_raises(K::LedgerCorruption) { K.read_log(path) }
    end
  end

  def test_sequence_gap_is_refused
    with_workspace do |root|
      path = write_log(root, [%w[observation a], %w[terminal a]])
      File.write(path, File.readlines(path).last)

      assert_raises(K::LedgerCorruption) { K.read_log(path) }
    end
  end

  def test_read_log_refuses_a_symlink_without_reading_its_target
    with_workspace do |root|
      directory = File.join(root, ".master")
      FileUtils.mkdir_p(directory, mode: 0o700)
      target = File.join(root, "outside-ledger.jsonl")
      original = "private external bytes\n"
      File.write(target, original)
      File.chmod(0o600, target)
      path = File.join(directory, "log.jsonl")
      File.symlink(target, path)

      error = assert_raises(K::LedgerCorruption) { K.read_log(path) }

      assert_match(/symlinked, hard-linked or non-regular/, error.message)
      assert_equal original, File.read(target)
    end
  end

  def test_read_log_refuses_a_hard_linked_ledger
    with_workspace do |root|
      directory = File.join(root, ".master")
      FileUtils.mkdir_p(directory, mode: 0o700)
      target = File.join(root, "outside-ledger.jsonl")
      write_log(root, [%w[terminal run]])
      original_path = File.join(root, K::LOG_RELATIVE_PATH)
      File.rename(original_path, target)
      path = File.join(directory, "log.jsonl")
      File.link(target, path)

      error = assert_raises(K::LedgerCorruption) { K.read_log(path) }

      assert_match(/symlinked, hard-linked or non-regular/, error.message)
      assert_operator File.stat(target).nlink, :>, 1
    end
  end

  def test_read_log_refuses_group_or_world_readable_ledger
    with_workspace do |root|
      path = write_log(root, [%w[terminal run]])
      File.chmod(0o644, path)

      error = assert_raises(K::LedgerCorruption) { K.read_log(path) }

      assert_match(/permissions must be private/, error.message)
      assert File.file?(path)
    end
  end

  def test_read_log_refuses_a_symlinked_parent_directory
    with_workspace do |root|
      outside = File.join(root, "outside")
      Dir.mkdir(outside, 0o700)
      File.write(File.join(outside, "log.jsonl"), "{}\n")
      File.chmod(0o600, File.join(outside, "log.jsonl"))
      File.symlink(outside, File.join(root, ".master"))

      error = assert_raises(K::LedgerCorruption) do
        K.read_log(File.join(root, K::LOG_RELATIVE_PATH))
      end

      assert_match(/symlinked audit log directory/, error.message)
    end
  end

  def test_missing_log_reads_empty
    with_workspace do |root|
      assert_equal [], K.read_log(File.join(root, K::LOG_RELATIVE_PATH))
    end
  end

  private

  def capture_cli(root, seq)
    status = nil
    capture_io { status = K.replay_cli(root:, seq:) }
    status
  end
end
