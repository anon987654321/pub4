# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"
require_relative "../subprocess"

class StudioSubprocessTest < Minitest::Test
  def test_on_path_finds_only_executables_from_the_supplied_path
    Dir.mktmpdir("studio-path") do |dir|
      executable = File.join(dir, "brew")
      plain_file = File.join(dir, "plain")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(0o755, executable)
      File.write(plain_file, "not executable")
      Dir.mkdir(File.join(dir, "folder"))

      assert Studio::Subprocess.on_path?("brew", path: dir)
      refute Studio::Subprocess.on_path?("plain", path: dir)
      refute Studio::Subprocess.on_path?("folder", path: dir)
      refute Studio::Subprocess.on_path?("", path: dir)
      refute Studio::Subprocess.on_path?("./brew", path: dir)
      refute Studio::Subprocess.on_path?("brew", path: "/nonexistent")
    end
  end

  def test_capture_returns_separate_output_and_exit_status
    stdout, stderr, status = Studio::Subprocess.capture3(
      RbConfig.ruby, "-e", "STDOUT.write('out'); STDERR.write('err')", timeout: 5
    )

    assert_equal "out", stdout
    assert_equal "err", stderr
    assert status.success?
  end

  def test_timeout_terminates_the_child_process_group
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Studio::Subprocess::TimeoutError) do
      Studio::Subprocess.capture3(RbConfig.ruby, "-e", "sleep 10", timeout: 0.1)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_match(/timed out/, error.message)
    assert_operator elapsed, :<, 3.0
  end

  def test_timeout_covers_descendants_that_keep_output_pipes_open
    error = assert_raises(Studio::Subprocess::TimeoutError) do
      Studio::Subprocess.capture3(
        RbConfig.ruby, "-e",
        "Process.spawn('sleep', '10', out: STDOUT, err: STDERR); exit 0",
        timeout: 0.1
      )
    end

    assert_match(/timed out/, error.message)
  end

  def test_invalid_deadlines_are_rejected
    assert_raises(ArgumentError) do
      Studio::Subprocess.capture3(RbConfig.ruby, "-e", "exit", timeout: Float::INFINITY)
    end
  end
end
