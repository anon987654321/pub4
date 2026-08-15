# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "timeout"
require "time"

module Master::Core
  # World — the only thing that touches the outside. Each verb is one handler;
  # the set is closed (Master::Core::VERBS), so the blast radius of the agent is the
  # surface of this file and nothing else. The Constitution has already admitted
  # whatever arrives here, so handlers do the IO plainly — their only added duty
  # is crash-safety (writes are atomic) and honest reporting. Reversing a whole
  # effect is the Fold's job via #checkpoint/#rollback, so handlers keep no
  # second, per-write backup of their own.
  #
  # This is where the old reach/ (git, web, fs), ops/, and tools/ collapse to.
  class World
    EXEC_TIMEOUT = 120  # seconds — max time for any subprocess call
    TERM_GRACE = 2      # seconds a killed child gets to exit on TERM before KILL

    # A subprocess killed by the timeout never exited, so there is no
    # Process::Status to report. Every caller of bounded_capture2e asks
    # `.success?`, so handing back nil turned a wedged git into a
    # NoMethodError raised from inside the fold — the one place that has to
    # stay standing when the outside world misbehaves. This stands in for the
    # missing status: not successful, no exit code.
    TimedOutStatus = Class.new do
      def success? = false
      def exitstatus = nil
      def to_s = "timed out"
    end
    TIMED_OUT = TimedOutStatus.new.freeze

    def initialize(root:, ask: nil, critique_runner: nil)
      @root = File.expand_path(root)
      @ask = ask
      @critique_runner = critique_runner
    end

    def verbs = Master::Core::VERBS

    def perform(effect)
      send("do_#{effect.verb}", **effect.args)
    rescue StandardError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    def checkpoint
      {
        id: SecureRandom.hex(8),
        patch: worktree_patch,
      }
    end

    def rollback(checkpoint)
      return Observation.ok("rollback: clean #{checkpoint[:id]}") if checkpoint[:patch].to_s.empty?

      if git_has_head?
        git_capture("reset", "--hard", "HEAD")
        apply_patch(checkpoint[:patch])
      else
        apply_patch_reverse(checkpoint[:patch])
      end
      Observation.ok("rolled back tracked changes #{checkpoint[:id]}")
    rescue StandardError => e
      Observation.no("rollback failed: #{e.class}: #{e.message}")
    end

    private

    def do_read(path:, **)
      Observation.ok(File.read(within(path), encoding: "UTF-8").scrub)
    end

    def do_write(path:, content:, **)
      abs = within(path)
      FileUtils.mkdir_p(File.dirname(abs))
      write_atomic(abs, content)
      Observation.ok("wrote #{path} (#{content.bytesize}b)")
    end

    def do_exec(argv:, timeout: 60, env: {}, **)
      raise ArgumentError, "argv must be an array" unless argv.is_a?(Array)
      raise ArgumentError, "argv cannot be empty" if argv.empty?
      raise ArgumentError, "argv entries must be strings" unless argv.all? { |arg| arg.is_a?(String) }

      # Model-chosen env used to ride through (LD_PRELOAD, PATH, …). The
      # constitution only inspects argv. Inherit nothing from the effect.
      _ignored_env = env
      seconds = timeout.to_i
      seconds = EXEC_TIMEOUT if seconds <= 0 || seconds > EXEC_TIMEOUT

      out, status = bounded_capture2e(
        *argv,
        env: nil,
        chdir: @root,
        timeout: seconds,
      )
      status.success? ? Observation.ok(out.to_s.strip) : Observation.no(out.to_s.strip)
    end

    def do_git(operation:, paths: [], message: nil, **)
      case operation.to_s.to_sym
      when :diff then Observation.ok(git_capture("diff"))
      when :stage then Observation.ok(git_capture("add", "--", *Array(paths)))
      when :commit then Observation.ok(git_capture("commit", "-m", message.to_s))
      else Observation.no("unknown git operation: #{operation}")
      end
    end

    def do_ask(prompt:, options: nil, **)
      return Observation.no("no surface to ask") unless @ask

      Observation.ok(@ask.call(prompt:, options:))
    end

    def do_note(**) = Observation.ok # the Memory keeps the note; nothing to do here

    def do_critique(scope: "diff", **)
      return Observation.no("critique: council runner unavailable") unless @critique_runner

      result = @critique_runner.call(root: @root, scope: scope.to_s)
      result.ok? ? Observation.ok(result.value!.to_s) : Observation.no(result.message.to_s)
    rescue StandardError => e
      Observation.no("critique: #{e.class}: #{e.message}")
    end

    # Paths are sandboxed to root; nothing escapes the workspace.
    def within(path)
      abs = File.expand_path(path, @root)
      raise "path escapes workspace: #{path}" unless under_root?(abs, @root)

      # expand_path does not follow a symlink the agent just created with ln.
      # realpath of the existing ancestor must still sit under the real root.
      real_root = File.realpath(@root)
      existing = abs
      existing = File.dirname(existing) until File.exist?(existing)
      raise "path escapes workspace: #{path}" unless under_root?(File.realpath(existing), real_root)

      abs
    end

    def under_root?(abs, root)
      abs == root || abs.start_with?(root + File::SEPARATOR)
    end

    # Write via tmp+rename: an OOM kill or crash mid-write can never leave a
    # half-written file, since rename is atomic on a POSIX filesystem. The tmp
    # sits beside the target so the rename stays on one device.
    def write_atomic(abs, content)
      tmp = "#{abs}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}"
      File.write(tmp, content)
      File.rename(tmp, abs)
    rescue StandardError
      File.delete(tmp) if tmp && File.exist?(tmp)
      raise
    end

    def git_repo?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--is-inside-work-tree")
      status.success?
    end

    def git_has_head?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--verify", "HEAD")
      status.success?
    end

    # A workspace need not be a git repo. When it isn't, there is nothing to
    # capture and rollback becomes a clean no-op, so the fold still runs.
    def worktree_patch
      return "" unless git_repo?

      if git_has_head?
        git_capture("diff", "HEAD", "--binary", raw: true)
      else
        git_capture("diff", "--binary", raw: true)
      end
    end

    def git_capture(*args, raw: false)
      out, status = bounded_capture2e("git", "-C", @root, *args)
      raise out.strip unless status.success?

      raw ? out : out.strip
    end

    def apply_patch(patch)
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end

    private

    # Bounded subprocess call with a hard timeout, which means killing the child
    # — not just abandoning it.
    #
    # This used to wrap Open3.capture3 in Timeout.timeout. Timeout only unwinds
    # the *block*; the process it spawned keeps running, and Ruby then blocks at
    # exit waiting for it. Measured: a 1s timeout around `sleep 30` took the full
    # 30 seconds to return, so the bound this method exists to provide did not
    # exist. popen3 gives us the pid, so the deadline can actually be enforced:
    # TERM, a short grace period, then KILL.
    def bounded_capture2e(*cmd, stdin_data: nil, env: nil, chdir: nil, timeout: nil)
      timeout_sec = Integer(timeout || ENV.fetch("MASTER_EXEC_TIMEOUT", EXEC_TIMEOUT))
      popen = env ? [env, *cmd] : cmd
      opts = {}
      opts[:chdir] = chdir if chdir

      Open3.popen3(*popen, pgroup: true, **opts) do |stdin, stdout, stderr, wait_thread|
        write_stdin(stdin, stdin_data)
        # Readers run off-thread: a child that fills its stdout pipe blocks on
        # write, so draining only after wait_thread returns would deadlock
        # exactly the wedged process this bound is for.
        out_reader = Thread.new { stdout.read }
        err_reader = Thread.new { stderr.read }

        unless wait_thread.join(timeout_sec)
          terminate(wait_thread.pid)
          [out_reader, err_reader].each(&:kill)
          next ["TIMEOUT after #{timeout_sec}s: #{cmd.first}", TIMED_OUT]
        end

        out = "#{out_reader.value}#{err_reader.value}"
        [out, wait_thread.value]
      end
    end

    def write_stdin(stdin, data)
      stdin.write(data) if data
      stdin.close
    rescue Errno::EPIPE
      # The child exited before reading its input; its status is the real signal.
      nil
    end

    # TERM first so the child can clean up, KILL if it ignores that. ESRCH means
    # it exited between the join timing out and this call — already gone.
    def terminate(pid)
      target = -Process.getpgid(pid)
      Process.kill("TERM", target)
      return if wait_for_exit(pid, TERM_GRACE)

      Process.kill("KILL", target)
      wait_for_exit(pid, TERM_GRACE)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def wait_for_exit(pid, seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        return true if Process.waitpid(pid, Process::WNOHANG)

        sleep 0.02
      end
      false
    rescue Errno::ECHILD
      true
    end

    # Bounded like every other git call here. This is rollback's no-HEAD path;
    # leaving it on raw Open3 meant a wedged git could hang rollback forever,
    # which is exactly the failure the bound exists to prevent.
    def apply_patch_reverse(patch)
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--reverse", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end
  end
end
