# frozen_string_literal: true

require_relative "../io/exec"
require_relative "../trace/dmesg"

module Operator
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
      Master::Trace::Dmesg.attach(unit, "#{@prefix}0", name) unless @quiet
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = capture(env, *cmd)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      ok = status.success?
      @results << Result.new(name:, success: ok, output: out)
      report(unit, name, ok, elapsed)
      Master::Trace::Dmesg::Report.print(unit, out, parent: "#{@prefix}0") if !out.empty? && (!ok || ENV["CHECK_VERBOSE"] == "1")
      ok
    end

    private

    def report(unit, name, ok, elapsed)
      return if @quiet

      Master::Trace::Dmesg.status(unit, ok ? "clean" : "failed")
      return unless ok && elapsed > @timeout * SLOW_STEP_FRACTION

      Master::Trace::Dmesg.status(
        unit,
        "#{elapsed.round}s of #{@timeout}s timeout, consider splitting #{name}",
      )
    end

    # A step writes to .master/check/<name>.log as it runs, and StepWatch reads it while it does:
    # a buffered step said nothing until it ended, so a suite that died after 3,632 tests and one
    # that was still running looked the same for twenty minutes.
    def capture(env, *cmd)
      log = StepWatch.log_path(cmd.last(2).join(" "))
      pid = Process.spawn(env, *cmd, chdir: @root, in: File::NULL, out: log, err: %i[child out], pgroup: true)
      watch = StepWatch.new(log, unit: "#{@prefix}#{@results.size + 1}") unless @quiet

      status = wait_bounded(pid)
      output = File.read(log, encoding: "UTF-8", invalid: :replace, undef: :replace)
      return [output, status] if status

      ["#{output}\nstep timed out after #{@timeout}s: #{cmd.join(' ')}\n", TimeoutStatus.new]
    ensure
      watch&.stop
    end

    # The exit status, or nil after the step's whole process group is killed at the timeout.
    def wait_bounded(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        status = Process.wait2(pid, Process::WNOHANG)&.last
        return status if status

        sleep 0.05
      end
      stop_group(pid)
      nil
    end

    # ESRCH: the group is gone. EPERM: macOS answers so for a group left holding only a zombie.
    def stop_group(pid)
      Process.kill("TERM", -pid)
      sleep 1

      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      :already_gone
    ensure
      reap(pid)
    end

    def reap(pid)
      Process.wait(pid)
    rescue Errno::ECHILD
      :already_reaped
    end
  end
end

require_relative "check_runner/step_watch"
