# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "dmesg"

module Deploy
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

    # The timeout is a hang guard, not a performance budget — a hung step is
    # infinite, so any generous ceiling catches it equally well. Treating it as
    # a budget is how `rake test` at 247s started failing a 360s limit on any
    # machine that was also doing something else, and reported it as
    # "first_failure: test / category: true_violation", i.e. as if a unit test
    # had broken. A gate that goes red for reasons unrelated to the code is a
    # gate people learn to ignore.
    #
    # So: warn as soon as a step spends most of its allowance, while it is still
    # passing. The next person then finds out from a green run that a step is
    # creeping up, instead of from a red one after it has already tipped over.
    SLOW_STEP_FRACTION = 0.6

    def run(name, *cmd, env: {})
      unit = "#{@prefix}#{@results.size + 1}"
      Deploy::Dmesg.attach(unit, "#{@prefix}0", name) unless @quiet
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = capture(env, *cmd)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      ok = status.success?
      @results << Result.new(name:, success: ok, output: out)
      report(unit, name, ok, elapsed)
      Deploy::Dmesg::Report.print(unit, out, parent: "#{@prefix}0") if !out.empty? && (!ok || ENV["CHECK_VERBOSE"] == "1")
      ok
    end

    private

    def report(unit, name, ok, elapsed)
      return if @quiet

      Deploy::Dmesg.status(unit, ok ? "clean" : "failed")
      return unless ok && elapsed > @timeout * SLOW_STEP_FRACTION

      Deploy::Dmesg.status(
        unit,
        "#{elapsed.round}s of #{@timeout}s timeout, consider splitting #{name}"
      )
    end

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
      :already_exited
    end
  end
end
