# frozen_string_literal: true

require "open3"
require "timeout"

module Pub4
  class CheckRunner
    Result = Struct.new(:name, :success, :output, keyword_init: true)

    TimeoutStatus = Struct.new(:success?) do
      def initialize = super(false)
    end

    attr_reader :results

    def initialize(prefix:, root:, timeout:, quiet: false)
      @prefix = prefix
      @root = root
      @timeout = timeout
      @quiet = quiet
      @results = []
    end

    def run(name, *cmd, env: {})
      print "#{@prefix}: #{name.ljust(22)} " unless @quiet
      $stdout.flush unless @quiet
      out, status = capture(env, *cmd)
      ok = status.success?
      @results << Result.new(name:, success: ok, output: out)
      if @quiet
        warn "#{@prefix}: #{name} #{ok ? 'ok' : 'fail'}"
      else
        puts(ok ? "ok" : "fail")
      end
      warn out if !out.empty? && (!ok || ENV["CHECK_VERBOSE"] == "1")
      ok
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
