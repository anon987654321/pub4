# frozen_string_literal: true

require "open3"

module Shared
  # Rails-owned subprocess boundary for shared-engine and app-specific jobs.
  # Captures each stream separately and kills the whole process group at timeout.
  module Subprocess
    class TimeoutError < StandardError; end

    module_function

    def capture3(*command, timeout:, env: nil, chdir: nil)
      seconds = Float(timeout)
      raise ArgumentError, "timeout must be finite and positive" unless seconds.finite? && seconds.positive?
      raise ArgumentError, "command must not be empty" if command.empty?

      popen = env.nil? ? command : [env, *command]
      options = { pgroup: true }
      options[:chdir] = chdir if chdir
      deadline = monotonic + seconds

      Open3.popen3(*popen, **options) do |stdin, stdout, stderr, waiter|
        readers = []
        completed = false
        begin
          stdin.close
          readers = [stdout, stderr].map do |io|
            Thread.new { io.read }.tap { |thread| thread.report_on_exception = false }
          end

          unless wait_for(waiter, deadline)
            raise TimeoutError, "process timed out after #{seconds.round(3)}s: #{command_label(command)}"
          end

          readers.each_with_index do |reader, index|
            remaining = deadline - monotonic
            stream = index.zero? ? "stdout" : "stderr"
            unless remaining.positive? && reader.join(remaining)
              raise TimeoutError, "process timed out waiting for #{stream}: #{command_label(command)}"
            end
          end

          result = [readers[0].value, readers[1].value, waiter.value]
          completed = true
          result
        ensure
          unless completed
            terminate_group(waiter.pid)
            readers.each do |reader|
              reader.kill if reader.alive?
              begin
                reader.join
              rescue IOError, SystemCallError
                nil
              end
            end
          end
          [stdin, stdout, stderr].each do |io|
            io.close unless io.closed?
          rescue IOError, SystemCallError
            nil
          end
        end
      end
    end

    def wait_for(waiter, deadline)
      remaining = deadline - monotonic
      remaining.positive? && waiter.join(remaining)
    end
    private_class_method :wait_for

    def terminate_group(pid)
      signal_group("TERM", pid)
      sleep 0.2
      signal_group("KILL", pid)
    end
    private_class_method :terminate_group

    def signal_group(signal, pid)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH, Errno::EPERM, Errno::EINVAL
      nil
    end
    private_class_method :signal_group

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    private_class_method :monotonic

    def command_label(command)
      File.basename(command.find { |part| !part.is_a?(Hash) }.to_s)
    end
    private_class_method :command_label
  end
end
