# frozen_string_literal: true

require "open3"
require "timeout"

module Pub4
  class CheckRunner
    TimeoutStatus = Struct.new(:success?) do
      def initialize = super(false)
    end

    def initialize(prefix:, root:, timeout:)
      @prefix = prefix
      @root = root
      @timeout = timeout
    end

    def run(name, *cmd, env: {})
      print "#{@prefix}: #{name.ljust(22)} "
      $stdout.flush
      out, status = capture(env, *cmd)
      puts(status.success? ? "ok" : "fail")
      warn out if !out.empty? && (!status.success? || ENV["CHECK_VERBOSE"] == "1")
      status.success?
    end

    private

    def capture(env, *cmd)
      output = +""
      status = nil
      Open3.popen2e(env, *cmd, chdir: @root, pgroup: true) do |_stdin, stdout, wait_thread|
        Timeout.timeout(@timeout) do
          output << stdout.read
          status = wait_thread.value
        end
      rescue Timeout::Error
        terminate_process_group(wait_thread.pid)
        output << "\nstep timed out after #{@timeout}s: #{cmd.join(' ')}\n"
      end
      [output, status || TimeoutStatus.new]
    end

    def terminate_process_group(pid)
      Process.kill("TERM", -pid)
      sleep 1
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
    end
  end
end
