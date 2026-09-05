# frozen_string_literal: true

require "open3"
require "timeout"
# Exec is standalone-loadable on purpose -- it is the subprocess primitive, so
# anything that shells out may reach it before a runtime boot -- and both of its
# rescue paths call Swallow. Without this require the swallow raises NameError
# and the timeout path never kills the process group it exists to kill.
require_relative "../ground/swallow"

module Master
  module Io
    # The one sanctioned way to run a subprocess. Mirrors Open3.capture{2,2e,3}
    # (same argument shapes, same return shapes) but every call carries a hard
    # time budget and, on overrun, kills the child's whole process group so a
    # wedged command — or a grandchild it spawned — can never block the pipeline
    # forever (ROBUSTNESS: no unbounded Open3).
    #
    #   out, status      = Master::Io::Exec.capture2e("git", "status", chdir: root)
    #   out, err, status = Master::Io::Exec.capture3(env, "ruby", "-c", file)
    #
    # A leading env Hash, chdir:, stdin_data:, and other Open3 spawn options pass
    # through unchanged. On timeout the returned status is a non-success Process
    # status (the child signalled), so existing `status.success?` checks fall
    # through to their error path the same way they do for a real failure.
    module Exec
      module_function

      DEFAULT_TIMEOUT = Integer(ENV.fetch("MASTER_EXEC_TIMEOUT", "120"))
      GRACE_S = 0.2

      def capture3(*cmd, timeout: DEFAULT_TIMEOUT, **opts)
        stdin_data, spawn_opts = split_opts(opts)
        Open3.popen3(*cmd, pgroup: true, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
          feed(stdin, stdin_data)
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          status = bounded_wait(wait_thr, timeout, [out_reader, err_reader])
          [reap(out_reader), reap(err_reader), status]
        end
      end

      def capture2e(*cmd, timeout: DEFAULT_TIMEOUT, **opts)
        stdin_data, spawn_opts = split_opts(opts)
        Open3.popen2e(*cmd, pgroup: true, **spawn_opts) do |stdin, stdout_err, wait_thr|
          feed(stdin, stdin_data)
          reader = Thread.new { stdout_err.read }
          status = bounded_wait(wait_thr, timeout, [reader])
          [reap(reader), status]
        end
      end

      def capture2(*cmd, timeout: DEFAULT_TIMEOUT, **opts)
        stdin_data, spawn_opts = split_opts(opts)
        Open3.popen2(*cmd, pgroup: true, **spawn_opts) do |stdin, stdout, wait_thr|
          feed(stdin, stdin_data)
          reader = Thread.new { stdout.read }
          status = bounded_wait(wait_thr, timeout, [reader])
          [reap(reader), status]
        end
      end

      # Open3.capture* treat stdin_data:/binmode: as capture options and pass the
      # rest to spawn; mirror that split so chdir:/env/redirects still forward.
      def split_opts(opts)
        opts = opts.dup
        stdin_data = opts.delete(:stdin_data)
        opts.delete(:binmode)
        [stdin_data, opts]
      end

      def feed(stdin, data)
        stdin.write(data) if data
        stdin.close
      rescue Errno::EPIPE, IOError => e
        Master::Ground::Swallow.log(e, context: "Exec.feed")
        nil
      end

      def bounded_wait(wait_thr, timeout, readers)
        Timeout.timeout(timeout) { wait_thr.value }
      rescue Timeout::Error
        kill_group(wait_thr.pid)
        readers.each(&:kill)
        wait_thr.value
      end

      def kill_group(pid)
        pgid = Process.getpgid(pid)
        Process.kill("TERM", -pgid)
        sleep GRACE_S
        Process.kill("KILL", -pgid)
      rescue Errno::ESRCH, Errno::EPERM => e
        Master::Ground::Swallow.log(e, context: "Exec.kill_group")
        nil
      end

      def reap(reader)
        reader.value.to_s
      rescue StandardError
        ""
      end
    end
  end
end
