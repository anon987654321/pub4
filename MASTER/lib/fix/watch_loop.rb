# frozen_string_literal: true

require "set"

module Master
  module Fix
  # Architecture #7: file-watcher reactive trigger — no polling.
  # Linux: inotify via rb-inotify. OpenBSD: kqueue via rb-kqueue.
  # A changed file triggers a targeted RuleLoop pass on that file only.
  # The system quiesces naturally — no STARTUP_DELAY, no idle sleep waste.
  #
  # Usage (VPS, after `gem install rb-kqueue` or `rb-inotify`):
  #   WatchLoop.new(rules:, agent:, scanner:, root:, bus:).run
    class WatchLoop
      DEBOUNCE_SECONDS = 5.0
      MAX_EVENTS_PER_MIN = 20
      WATCH_EXTENSIONS = %w[.rb .erb .yml .yaml .json .toml .js .css .html].freeze
      SKIP_DIRS = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze

      def initialize(rules:, agent:, scanner:, root:, bus: nil, learnings: nil, fix_loop: nil)
        @rules = rules
        @agent = agent
        @scanner = scanner
        @root = root
        @bus = bus
        @learnings = learnings
        @fix_loop = fix_loop
        @queue = Queue.new
        @mtime_map = {}
        @in_progress = Mutex.new
        @in_progress_set = Set.new
        @event_times = []
        @watcher = build_watcher
      end

      def run
        return unless ENV["MASTER_WATCH"] == "1"

        @bus&.publish("watch_loop:start", root: @root)
        Thread.new { drain_queue }
        @watcher.run
      rescue LoadError => e
        @bus&.publish("watch_loop:unavailable", reason: e.message)
      end

      private

      def build_watcher = require_kqueue_or_inotify

      def drain_queue
        pending = {}
        loop do
          path = @queue.pop
          next unless watchable?(path)
          mtime = latest_mtime(path)
          next if @mtime_map[path] == mtime

          pending[path] = mtime
          sleep DEBOUNCE_SECONDS
          ready = pending.select { |p, _m| latest_mtime(p) == pending[p] }.keys
          ready.each do |p|
            pending.delete(p)
            next if in_progress?(p)
            next unless rate_ok?
            @mtime_map[p] = latest_mtime(p)
            run_rules_on(p)
          end
        end
      end

      def run_rules_on(path)
        return unless File.exist?(path)
        mark_in_progress(path) do
          # Prefer a single-file FixLoop pass when one's available, so a
          # watched-file edit gets the same stagnation detection and commit
          # gating as the batch path instead of WatchLoop's own simpler
          # per-rule loop (which has neither).
          if @fix_loop
            @fix_loop.run(path, max_passes: 3, budget_seconds: 120, incremental: true)
          else
            applicable = @rules.select { |r| r.respond_to?(:applies_to?) ? r.applies_to?(path) : true }
            applicable.each do |rule|
              rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus, learnings: @learnings)
              result = rl.run_once([path])
              @bus&.publish("watch_loop:file_pass", file: path, rule: rule.id, **result)
            end
          end
        end
      rescue StandardError => e
        @bus&.publish("watch_loop:error", file: path, error: e.message)
      end

      def watchable?(path)
        return false if SKIP_DIRS.any? { |d| path.include?(d) }
        WATCH_EXTENSIONS.include?(File.extname(path))
      end

      def in_progress?(path)
        @in_progress.synchronize { @in_progress_set.include?(path) }
      end

      def mark_in_progress(path)
        @in_progress.synchronize { @in_progress_set.add(path) }
        yield
      ensure
        @in_progress.synchronize { @in_progress_set.delete(path) }
      end

      def rate_ok?
        now = Time.now.to_f
        @event_times.reject! { |t| now - t > 60.0 }
        return false if @event_times.size >= MAX_EVENTS_PER_MIN
        @event_times << now
        true
      end

      def latest_mtime(path)
        File.exist?(path) ? File.mtime(path).to_f : nil
      end

      def require_kqueue_or_inotify
        return kqueue_watcher if RUBY_PLATFORM.match?(/openbsd|freebsd/)

        inotify_watcher
      end

      def kqueue_watcher
        require "rb-kqueue"
        queue = KQueue::Queue.new
        queue.watch(@root, :recursive, :write, :rename) { |ev| @queue << ev.path.to_s }
        queue
      end

      def inotify_watcher
        require "rb-inotify"
        notifier = INotify::Notifier.new
        notifier.watch(@root, :close_write, :moved_to, :recursive) { |ev| @queue << ev.absolute_name }
        notifier
      end
    end
  end
end
