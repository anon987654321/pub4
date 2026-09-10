# frozen_string_literal: true

require "open3"

# A subprocess a gate spawns, with a bound on it.
#
# Open3.capture2e has no timeout. A gate that shells out and waits forever
# prints nothing, reports nothing and blocks every gate after it in the --all
# order, which is a whole run lost to one child that never exits — and it has
# happened here, with no output and no verdict to say which gate it was.
#
# git is the usual caller and git is usually instant, so the point is not speed:
# it is that `git` inside a repository with a stale index lock, or a build
# script that decides to compile, has no upper bound of its own. Thirty seconds
# is far past anything these commands legitimately need.
#
# Returns [output, status], where status is a Process::Status or :timeout. A
# caller reading `status.success?` must therefore ask whether it timed out
# first; the shape is deliberate, because silently mapping a timeout onto
# failure is how "the gate ran and found a problem" and "the gate never ran"
# become one verdict again.
module BoundedCommand
  DEFAULT_TIMEOUT_S = 30

  module_function

  def capture2e(*command, timeout: DEFAULT_TIMEOUT_S, **options)
    Open3.popen2e(*command, **options) do |stdin, out, wait|
      stdin.close
      output = +""
      # Read on a thread: the pipe fills at 64KB, so waiting on the process
      # before draining it deadlocks against the child's own output.
      reader = Thread.new { output << out.read.to_s }
      unless wait.join(timeout)
        kill_tree(wait.pid)
        reader.join(5)
        next [output, :timeout]
      end

      reader.join
      [output, wait.value]
    end
  rescue Errno::ENOENT, Errno::EACCES => e
    ["#{e.class}: #{e.message}", :timeout]
  end

  # TERM first, then KILL, so a child ignoring the polite signal still goes.
  def kill_tree(pid)
    Process.kill("TERM", pid)
    sleep 2
    Process.kill("KILL", pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def timed_out?(status) = status == :timeout

  def success?(status) = !timed_out?(status) && status.success?
end
