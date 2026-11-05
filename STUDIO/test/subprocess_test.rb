# frozen_string_literal: true

require "rbconfig"
require_relative "minitest_helper"
require_relative "../subprocess"

class TestStudioSubprocess < Minitest::Test
  def test_capture3_keeps_stdout_and_stderr_separate
    stdout, stderr, status = Studio::Subprocess.capture3(
      RbConfig.ruby, "-e", '$stdout.write("out"); $stderr.write("err")',
      timeout: 2,
      chdir: File.expand_path("..", __dir__)
    )

    assert status.success?
    assert_equal "out", stdout
    assert_equal "err", stderr
  end

  def test_deadline_covers_a_descendant_that_keeps_pipes_open
    child = "trap('TERM') {}; sleep 10"
    parent = "Process.spawn(#{RbConfig.ruby.dump}, '-e', #{child.dump}); puts 'leader exited'; exit 0"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    error = assert_raises(Studio::Subprocess::TimeoutError) do
      Studio::Subprocess.capture3(
        RbConfig.ruby, "-e", parent,
        timeout: 0.2,
        chdir: File.expand_path("..", __dir__)
      )
    end

    assert_match(/stdout/, error.message)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3.0
  end
end
