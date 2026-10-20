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

      deadline = monotonic + limit
      output = error_output = status = nil
      Open3.popen3(*command, pgroup: true, **options) do |stdin, stdout, stderr, waiter|
        readers = []
        completed = false
        begin
          stdin.close
          readers = [Thread.new { stdout.read }, Thread.new { stderr.read }]

          remaining = deadline - monotonic
          unless remaining.positive? && waiter.join(remaining)
            raise TimeoutError, "process timed out after #{limit.round(3)}s: #{command_label(command)}"
          end

          output = read_before_deadline(readers.fetch(0), deadline, "stdout", command)
          error_output = read_before_deadline(readers.fetch(1), deadline, "stderr", command)
          status = waiter.value
          completed = true
        ensure
          terminate_group(waiter) unless completed
          # Stop the readers before the pipes close under them: a reader that dies on a
          # closed stream re-raises its IOError from join and hides the TimeoutError.
          readers.each do |reader|
            reader.kill if reader.alive?
            begin
              reader.join
            rescue IOError, SystemCallError
              nil
            end
          end
          [stdin, stdout, stderr].each do |io|
            io.close unless io.closed?
          rescue IOError, SystemCallError
            nil
          end
        end
      end
      [output, error_output, status]
    end

    def read_before_deadline(reader, deadline, stream, command)
      remaining = deadline - monotonic
      unless remaining.positive? && reader.join(remaining)
        raise TimeoutError, "process timed out waiting for #{stream}: #{command_label(command)}"
      end

      reader.value
    end
    private_class_method :read_before_deadline

    def terminate_group(waiter)
      signal_group("TERM", waiter.pid)
      waiter.join(0.25)
      # Even after the leader exits, a descendant can keep the pipes open. Signal
      # the process group again so timed-out grandchildren cannot outlive the call.
      signal_group("KILL", waiter.pid)
      waiter.join(1)
    end
    private_class_method :terminate_group

    def signal_group(signal, pid)
      ::Process.kill(signal, -pid)
    rescue Errno::ESRCH, Errno::EPERM, Errno::EINVAL
      nil
    end
    private_class_method :signal_group

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :monotonic

    def command_label(command)
      first = command.find { |part| !part.is_a?(Hash) }
      File.basename(first.to_s)
    end
    private_class_method :command_label
  end
end
