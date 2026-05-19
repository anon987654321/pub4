# frozen_string_literal: true

module Master
  module Loop
  # Architecture #7: file-watcher reactive trigger — no polling.
  # Linux: inotify via rb-inotify. OpenBSD: kqueue via rb-kqueue.
  # A changed file triggers a targeted RuleLoop pass on that file only.
  # The system quiesces naturally — no STARTUP_DELAY, no idle sleep waste.
  #
  # Usage (VPS, after `gem install rb-kqueue` or `rb-inotify`):
  #   WatchLoop.new(rules:, agent:, scanner:, root:, bus:).run
  class WatchLoop
    DEBOUNCE_SECONDS = 1.0
    SKIP_DIRS        = FixLoop::SKIP_DIRS

    def initialize(rules:, agent:, scanner:, root:, bus: nil, learnings: nil)
      @rules     = rules
      @agent     = agent
      @scanner   = scanner
      @root      = root
      @bus       = bus
      @learnings = learnings
      @queue     = Queue.new
      @watcher   = build_watcher
    end

    def run
      @bus&.publish("watch_loop:start", root: @root)
      Thread.new { drain_queue }
      @watcher.run
    rescue LoadError => e
      @bus&.publish("watch_loop:unavailable", reason: e.message)
    end

    private

    def build_watcher
      require_kqueue_or_inotify
    rescue LoadError
      raise
    end

    # Drains the queue with debounce — coalesces rapid file events.
    def drain_queue
      pending = {}
      loop do
        path = @queue.pop
        next if SKIP_DIRS.any? { |d| path.include?(d) }
        pending[path] = Time.now.to_f
        sleep DEBOUNCE_SECONDS
        now = Time.now.to_f
        ready = pending.select { |_, t| now - t >= DEBOUNCE_SECONDS }.keys
        ready.each do |p|
          pending.delete(p)
          run_rules_on(p)
        end
      end
    end

    def run_rules_on(path)
      return unless File.exist?(path)
      @rules.each do |rule|
        rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus, learnings: @learnings)
        result = rl.run([path])
        @bus&.publish("watch_loop:file_pass", file: path, rule: rule.id, **result)
      end
    rescue StandardError => e
      @bus&.publish("watch_loop:error", file: path, error: e.message)
    end

    # Platform-specific watcher. Enqueues paths into @queue on change events.
    def require_kqueue_or_inotify
      if RUBY_PLATFORM.include?("openbsd") || RUBY_PLATFORM.include?("freebsd")
        require "rb-kqueue"
        queue = KQueue::Queue.new
        queue.watch(@root, :recursive, :write, :rename) { |ev| @queue << ev.path.to_s }
        queue
      else
        require "rb-inotify"
        n = INotify::Notifier.new
        n.watch(@root, :close_write, :moved_to, :recursive) { |ev| @queue << ev.absolute_name }
        n
      end
    end
  end
  end
end
