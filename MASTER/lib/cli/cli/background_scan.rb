# frozen_string_literal: true

module Master
  module CLI
    class CLI
      private

      def start_background_loop
        # Built on the main thread, before either scanner thread exists, so both
        # find the same gate rather than racing to create one.
        @scan_gate = Mutex.new
        @bg_thread = Thread.new do
          loop do
            break if background_stop_requested?

            background_cycle unless @user_active
          end
        rescue StandardError => e
          @refs.bus&.publish("cli:bg_error", error: e.message)
        end
      end

      def stop_background_loop
        @boot_scan_thread&.kill
        @boot_scan_thread = nil
        return unless @bg_thread

        @bg_control << :stop
        @bg_thread.join(2)
        @bg_thread = nil
      end

      def background_stop_requested?
        IDLE_SLEEP_DEFAULT.times do
          return true if background_control_message == :stop

          sleep 1
        end
        false
      end

      def background_control_message
        @bg_control.pop(true)
      rescue ThreadError => e
        Master::Ground::Swallow.log(e, context: "CLI.background_control_message")
        nil
      end

      # The deep self-scan over lib/ runs 181 rules and takes north of a minute.
      # Inline it held the prompt hostage for the whole boot, so the operator sat
      # at "scan…" with no way to type. It reports when it lands instead.
      def start_boot_scan
        @boot_scan_thread = Thread.new { @scan_gate.synchronize { boot_scan } }
      end

      def boot_scan
        result = Master::Review::Scan::SelfScan.new(scanner: @refs.scanner, root: @refs.root, event_bus: @refs.bus).call(autofix: false)
        return unless result.ok?

        summary = result.value!
        set_violations(summary.violation_count)
        $stdout.puts "\n#{@refs.renderer.render(summary.line, mode: :dim)}"
        $stdout.puts @refs.renderer.boot_wayfinding(constitution: true, agent: true, scan: :done)
        $stdout.flush
      rescue StandardError => e
        @refs.bus&.publish("cli:warn", error: e.message)
      end

      def run_self_scan
        result = Master::Review::Scan::SelfScan.new(scanner: @refs.scanner, root: @refs.root, event_bus: @refs.bus).call(stream: true, autofix: true)
        line = result.ok? ? result.value!.line : result.message
        puts @refs.renderer.render(line, mode: result.ok? ? :dim : :warning)
      end

      def changed_lib_files(lib_dir)
        out, = Master::Io::Exec.capture2e("git", "-C", @refs.root, "diff", "--name-only", "HEAD")
        return [] if out.strip.empty?
        out.lines
           .map { |l| File.join(@refs.root, l.strip) }
           .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.changed_lib_files", event_bus: @refs.bus)
        []
      end

      def scan_files(paths)
        Result.ok(paths.map { |p| [p, @refs.scanner.scan(p, depth: :deep)] })
      end

      def count_violations(pairs)
        pairs.sum do |_file, file_result|
          file_result.ok? ? file_result.value!.size : 0
        end
      end

      # Skips rather than queues: this fires every idle_sleep_seconds, and a tick
      # that waited its turn would only start a redundant rescan of a tree the
      # in-flight scan is already covering.
      def background_cycle
        return unless @scan_gate.try_lock

        begin
          background_cycle!
        ensure
          @scan_gate.unlock
        end
      end

      def background_cycle!
        lib_dir = File.join(@refs.root, "lib")
        result = @refs.scanner.scan_dir(lib_dir, depth: :deep)
        return unless result.ok?
        n = count_violations(result.value!)
        prev = violations_count
        return if n == prev
        delta = n - prev
        set_violations(n)
        sign = delta.positive? ? "+#{delta}" : delta.to_s
        msg = n.positive? ? "bg: #{n}v (#{sign})" : "bg: clean (#{sign})"
        $stdout.puts "\n#{@refs.renderer.render(msg, mode: :dim)}"
        @refs.bus&.publish("cli:violation_delta", count: n, delta:, previous: prev)
        $stdout.flush
      rescue StandardError => e
        @refs.bus&.publish("cli:bg_error", error: e.message)
      end

      def refresh_skills!
        @refs.skills&.discover!
      end

      INIT_FRAMES = 20
      INIT_FRAME_MS = 0.04
    end
  end
end
