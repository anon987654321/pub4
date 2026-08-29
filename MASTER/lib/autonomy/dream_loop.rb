# frozen_string_literal: true

module Master
  module Autonomy
    # REM. WatchLoop is reactive — a file changes, it fixes that one file. This is
    # the complement: when the tree is quiet and no one is typing, MASTER works
    # the way a session does. It reads a rule, searches the web for how the wider
    # world states it (ar5iv, GitHub, Hacker News), links it to the code that
    # should honour it, proposes refactors — and only through the gated path,
    # fixes one.
    #
    # Opt-in (MASTER_DREAM=1), like WatchLoop's MASTER_WATCH. Two safety rules,
    # both load-bearing:
    #   - A keystroke wakes MASTER. idle? is checked every cadence, so a dream
    #     yields the moment the user returns — it never competes for the machine.
    #   - Only the `improve` mode writes, and it writes through FixLoop into a
    #     worktree that lands only on a clean gate. Research, connect and ideate
    #     are read-only: they record notes and proposals, they never touch the
    #     tree. So the half that could go wrong is bounded to the one path that
    #     already has commit gating and worktree isolation — a bad dream is
    #     discarded, not pushed.
    class DreamLoop
      MODES = %i[research connect ideate improve].freeze

      def initialize(scanner:, agent:, root:, bus: nil, web: nil, ideation: nil,
                     fix_loop: nil, idle: nil, config: {})
        @scanner = scanner
        @agent = agent
        @root = root
        @bus = bus
        @web = web            # Io::WebSearch — online search, ar5iv, GitHub, HN
        @ideation = ideation  # Council::Ideation — proposals, best after the 8th
        @fix_loop = fix_loop  # gated, worktree-isolated fixes
        @idle = idle          # ->{ boolean }: true while no user activity
        @startup_delay = Integer(config.fetch(:startup_delay, 30))
        @cadence = Integer(config.fetch(:idle_sleep, 300))
        @dreams = 0
      end

      def run
        return unless ENV["MASTER_DREAM"] == "1"

        emit("dream0", "REM armed", startup: @startup_delay, cadence: @cadence)
        sleep @startup_delay
        while idle?
          dream(MODES[@dreams % MODES.size])
          @dreams += 1
          sleep @cadence
        end
        emit("dream#{@dreams}", "woke", reason: "user active")
      rescue StandardError => e
        @bus&.publish("dream_loop:error", error: e.message)
      end

      private

      # One REM cycle. Read-only modes think and record; improve is the only mode
      # that writes, and it writes through the fix loop.
      def dream(mode)
        focus = pick_focus
        return if focus.nil?

        emit("dream#{@dreams}", "dreaming", mode:, focus:)
        send(mode, focus)
      rescue StandardError => e
        @bus&.publish("dream_loop:mode_error", mode:, error: e.message)
      end

      # A rule, or a tree, to dream about — rotate so no corner is starved.
      def pick_focus
        rules = Array(@scanner&.respond_to?(:rules) ? @scanner.rules : nil)
        return nil if rules.empty?

        rules[@dreams % rules.size]&.id
      end

      # Ask the world how it states this rule, and record what it learns. Read-only.
      def research(focus)
        return unless @web

        %W[#{focus} best practice ar5iv arxiv].then do |terms|
          notes = @web.search(terms.join(" "))
          record(:research, focus, notes)
          emit("dream#{@dreams}", "researched", focus:, found: Array(notes).size)
        end
      end

      # Link a rule to the code that should honour it — a mental edge, not an edit.
      def connect(focus)
        edges = @scanner&.respond_to?(:reach) ? @scanner.reach(focus) : nil
        record(:connect, focus, edges)
        emit("dream#{@dreams}", "linked", focus:, edges: Array(edges).size)
      end

      # Proposals for the focus. Best after the 8th; the panel keeps its own count.
      def ideate(focus)
        return unless @ideation

        proposals = @ideation.propose(focus)
        record(:ideate, focus, proposals)
        emit("dream#{@dreams}", "proposed", focus:, count: Array(proposals).size)
      end

      # The only writing mode: a single gated pass through the fix loop, which
      # runs in its own worktree and lands only on a clean gate.
      def improve(focus)
        return unless @fix_loop

        result = @fix_loop.run(focus, max_passes: 3, budget_seconds: 120, incremental: true, isolate: true)
        emit("dream#{@dreams}", "improved", focus:, landed: result.respond_to?(:ok?) ? result.ok? : false)
      end

      def idle? = @idle.nil? || @idle.call

      def record(kind, focus, payload)
        @bus&.publish("dream_loop:#{kind}", focus:, payload:)
      end

      def emit(unit, status, **fields)
        @bus&.publish("dream_loop:#{status}", unit:, **fields)
      end
    end
  end
end
