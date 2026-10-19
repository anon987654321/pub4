# frozen_string_literal: true

require "open3"

module Studio
  # A subprocess contract shared by media tools: bounded wall-clock time,
  # separate stdout/stderr, and process-group cleanup on timeout or exceptions.
  module Subprocess
    class TimeoutError < StandardError; end

    module_function

    def capture3(*command, timeout:, **options)
      limit = Float(timeout)
      raise ArgumentError, "timeout must be finite and positive" unless limit.finite? && limit.positive?
      raise ArgumentError, "command must not be empty" if command.empty?

      output = error_output = status = nil
      Open3.popen3(*command, pgroup: true, **options) do |stdin, stdout, stderr, waiter|
        readers = []
        begin
          stdin.close
          readers = [Thread.new { stdout.read }, Thread.new { stderr.read }]
          unless waiter.join(limit)
            terminate(waiter)
            raise TimeoutError, "process timed out after #{limit.to_f.round(3)}s: #{command_label(command)}"
          end

          output = readers.fetch(0).value
          error_output = readers.fetch(1).value
          status = waiter.value
        ensure
          terminate(waiter) if waiter.alive?
          [stdin, stdout, stderr].each do |io|
            io.close unless io.closed?
          rescue IOError, SystemCallError
            nil
          end
          readers.each do |reader|
            reader.kill if reader.alive?
            reader.join
          end
        end
      end
      [output, error_output, status]
    end

    def terminate(waiter)
      begin
        ::Process.kill("TERM", -waiter.pid)
      rescue Errno::ESRCH, Errno::EPERM, Errno::EINVAL
        nil
      end
      return unless waiter.alive?
      return if waiter.join(0.25)

      begin
        ::Process.kill("KILL", -waiter.pid)
      rescue Errno::ESRCH, Errno::EPERM, Errno::EINVAL
        nil
      ensure
        waiter.join(1)
      end
    end
    private_class_method :terminate

    def command_label(command)
      first = command.find { |part| !part.is_a?(Hash) }
      File.basename(first.to_s)
    end
    private_class_method :command_label
  end
end
