# frozen_string_literal: true

require "stringio"

module OutputGuard
  MUTEX = Mutex.new
  DEFAULT_STREAMS = { stdout: $stdout, stderr: $stderr }.freeze

  module_function

  def capture(stdout: true, stderr: true)
    MUTEX.synchronize do
      original_stdout = $stdout
      original_stderr = $stderr

      out_io = stdout ? StringIO.new : nil
      err_io = stderr ? StringIO.new : nil

      $stdout = out_io if stdout
      $stderr = err_io if stderr

      result = yield

      out_str = out_io&.string
      err_str = err_io&.string

      [result, out_str, err_str]
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def silence(stdout: true, stderr: true, &block)
    capture(stdout: stdout, stderr: stderr, &block).first
  end

  def with_streams(stdout: DEFAULT_STREAMS[:stdout], stderr: DEFAULT_STREAMS[:stderr])
    MUTEX.synchronize do
      original_stdout = $stdout
      original_stderr = $stderr

      $stdout = stdout if stdout
      $stderr = stderr if stderr

      yield
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end
end