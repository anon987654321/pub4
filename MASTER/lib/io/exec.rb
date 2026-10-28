# frozen_string_literal: true

require "open3"
# Exec is standalone-loadable on purpose -- it is the subprocess primitive, so
# anything that shells out may reach it before a runtime boot -- and both of its
# rescue paths call Swallow. Without this require the swallow raises NameError
# and the timeout path never kills the process group it exists to kill.
require_relative "../ground/swallow"
require_relative "process_spawn"

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
    # Callers that need to distinguish a timeout may set raise_on_timeout: true.
    module Exec
      module_function

      DEFAULT_TIMEOUT = Integer(ENV.fetch("MASTER_EXEC_TIMEOUT", "120"))
      GRACE_S = 0.2

      class TimeoutError < StandardError
        attr_reader :result

        def initialize(message, result: nil)
          @result = result
          super(message)
        end
      end

      def capture3(*cmd, timeout: DEFAULT_TIMEOUT, raise_on_timeout: false, **opts) =
        run_capture(:popen3, cmd, timeout, opts, raise_on_timeout:)

      def capture2e(*cmd, timeout: DEFAULT_TIMEOUT, raise_on_timeout: false, **opts) =
        run_capture(:popen2e, cmd, timeout, opts, raise_on_timeout:)

      def capture2(*cmd, timeout: DEFAULT_TIMEOUT, raise_on_timeout: false, **opts) =
        run_capture(:popen2, cmd, timeout, opts, raise_on_timeout:)

      # The body the three captures share: spawn in its own process group, drain
      # every output stream on a thread, feed stdin on another, wait with a bound
      # and return the reaped streams in popen order followed by the status.
      # on_stdout: receives each chunk of the first output stream as it is read, so a caller can show a
      # reply while the child is still writing it; the whole output is still returned at the end.
      def run_capture(opener, cmd, timeout, opts, raise_on_timeout: false)
        stdin_data, binmode, spawn_opts = split_opts(opts)
        on_stdout = spawn_opts.delete(:on_stdout)
        options = ProcessSpawn.options(spawn_opts.merge(pgroup: true))
        Open3.public_send(opener, *cmd, **options) do |stdin, *streams, wait_thr|
          if binmode
            stdin.binmode
            streams.each(&:binmode)
          end
          readers = streams.each_with_index.map { |stream, index| reader_for(stream, (on_stdout if index.zero?)) }
          writer = writer_for(stdin, stdin_data)
          status, timed_out = bounded_wait(wait_thr, timeout, readers)
          writer&.join
          result = [*readers.map { |reader| reap(reader) }, status]
          raise TimeoutError.new("process timed out after #{timeout}s", result:) if timed_out && raise_on_timeout

          result
        end
      end
      private_class_method :run_capture

      HOMEBREW_BINS = %w[/opt/homebrew/bin /usr/local/bin].freeze

      # Resolve explicit paths or command names on PATH, including PATHEXT on
      # Windows. Preferred directories retain precedence over PATH, and names
      # that already have an extension are never expanded a second time.
      def which(name, path: ENV.fetch("PATH", ""), prefer: [], extensions: ENV["PATHEXT"])
        name = name.to_s
        return if name.empty?

        suffixes = extensions.to_s.split(";").reject(&:empty?)
        names = File.extname(File.basename(name)).empty? ? [name, *suffixes.map { |suffix| "#{name}#{suffix}" }] : [name]
        if name.include?(File::SEPARATOR)
          names.each do |candidate|
            return File.expand_path(candidate) if File.file?(candidate) && File.executable?(candidate)
          end
          return
        end

        [*prefer, *path.to_s.split(File::PATH_SEPARATOR)].uniq.each do |dir|
          names.each do |candidate_name|
            candidate = File.join(dir, candidate_name)
            return candidate if File.file?(candidate) && File.executable?(candidate)
          end
        end
        nil
      end

      def on_path?(name, **) = !name.to_s.include?(File::SEPARATOR) && !which(name, **).nil?

      # Where a user-installed CLI lands when PATH does not name it: the Claude Code installer puts claude in
      # ~/.local/bin. A /fix launched from a script whose PATH left that out found "no claude on PATH" on every
      # call, skipped MASTER's first lane, and ran on the next one without saying why.
      USER_BINS = [File.expand_path("~/.local/bin")].freeze

      # A subscription CLI (claude, grok) by full path: PATH first, then USER_BINS and HOMEBREW_BINS.
      def cli_binary(name, user_bins: USER_BINS)
        which(name, path: [ENV.fetch("PATH", ""), *user_bins, *HOMEBREW_BINS].join(File::PATH_SEPARATOR))
      end

      # Open3.capture* consume stdin_data and binmode; all other options belong
      # to spawn and must pass through, including env, chdir, and redirects.
      def split_opts(opts)
        opts = opts.dup
        stdin_data = opts.delete(:stdin_data)
        binmode = opts.delete(:binmode)
        [stdin_data, binmode, opts]
      end

      def writer_for(stdin, data)
        return close_stdin(stdin) unless data

        Thread.new do
          feed(stdin, data)
        end.tap { |thread| thread.report_on_exception = false }
      end

      def feed(stdin, data)
        stdin.write(data)
      rescue Errno::EPIPE, IOError => e
        Master::Ground::Swallow.log(e, context: "Exec.feed")
        nil
      ensure
        close_stdin(stdin)
      end

      def close_stdin(stdin)
        stdin.close unless stdin.closed?
      rescue IOError
        nil
      end

      # The children one turn spawned. The CLI puts one in Fiber[:master_children]
      # for each turn, and every thread the turn starts inherits fiber storage, so
      # a user:interrupt kills that turn's processes and no one else's. Without it
      # a cancelled turn's thread sits in popen's ensure waiting for its child,
      # and the prompt waits with it for up to DEFAULT_TIMEOUT.
      class Children
        def initialize
          @pids = []
          @lock = Mutex.new
        end

        def track(pid)
          @lock.synchronize { @pids << pid }
          yield
        ensure
          @lock.synchronize { @pids.delete(pid) }
        end

        def kill_all
          @lock.synchronize { @pids.dup }.each { |pid| Exec.kill_group(pid) }.size
        end
      end

      # Thread#join(limit) is the bound: Exec runs before Bundler activates the
      # lockfile, and requiring the timeout default gem here pins the stock
      # version and fails Bundler.setup when the lockfile asks for a newer one.
      def bounded_wait(wait_thr, timeout, readers)
        # The direct child can exit while a grandchild keeps stdout/stderr open.
        # Waiting only for the direct PID then reaping readers without a deadline
        # turns a successful-looking parent exit into an unbounded pipeline hang.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        children = Fiber[:master_children]

        loop do
          return [wait_thr.value, false] unless wait_thr.alive? || readers.any?(&:alive?)

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0

          wait = -> { wait_thr.join([remaining, 0.01].min) }
          children ? children.track(wait_thr.pid, &wait) : wait.call if wait_thr.alive?
          sleep([remaining, 0.005].min) if !wait_thr.alive? && readers.any?(&:alive?)
        end

        stop_child(wait_thr, readers)
        [wait_thr.value, true]
      ensure
        stop_child(wait_thr, readers) if wait_thr.alive? || readers.any?(&:alive?)
      end

      # An outer deadline (Timeout.timeout around a model call, a file's repair budget) interrupts the
      # wait from outside, and popen's ensure then joins the child with no bound: a /fix pass sat 711s
      # on a claude call whose 240s budget had already fired. The child goes with the wait.
      def stop_child(wait_thr, readers)
        kill_group(wait_thr.pid)
        readers.each(&:kill)
      end

      def kill_group(pid)
        # Every sanctioned spawn starts a new process group. Use the child's PID
        # as that group ID: once the parent exits, getpgid(pid) raises ESRCH even
        # while a grandchild is alive and holding the output pipes open.
        Process.kill("TERM", -pid)
        sleep GRACE_S
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        nil
      rescue Errno::EPERM => e
        Master::Ground::Swallow.log(e, context: "Exec.kill_group")
        nil
      end

      # A cancelled turn closes the pipes under a reader mid-read. reap reads
      # the IOError as empty output, so it must not also print a backtrace over
      # the operator's prompt.
      # Preserve already-read diagnostics when a deadline terminates the reader.
      # Thread#value alone loses the block's partial String when Thread#kill wins.
      class OutputReader
        def initialize(io, on_chunk = nil)
          @io = io
          @on_chunk = on_chunk
          @output = String.new(encoding: io.external_encoding || Encoding::BINARY)
          @lock = Mutex.new
          @thread = Thread.new { read }
          @thread.report_on_exception = false
        end

        def kill = @thread.kill
        def alive? = @thread.alive?

        def value
          @thread.value
          @lock.synchronize { @output.dup }
        end

        private

        def read
          loop do
            chunk = @io.readpartial(16_384)
            @lock.synchronize { @output << chunk }
            notify(chunk)
          end
        rescue EOFError, IOError
          nil
        end

        # A listener that raises must not stop the read: the whole output is still owed to the caller.
        def notify(chunk)
          @on_chunk&.call(chunk)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Exec.on_stdout")
        end
      end

      def reader_for(io, on_chunk = nil)
        OutputReader.new(io, on_chunk)
      end

      def reap(reader)
        reader.value.to_s
      rescue StandardError
        ""
      end
    end
  end
end
