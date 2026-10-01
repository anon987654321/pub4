# frozen_string_literal: true

require "set"
# DmesgUnit names each event component's unit. It lives in logging.rb, and no
# autoload reaches it by that name.
require_relative "logging"

module Master
  module Trace
    # OpenBSD dmesg-style kernel lines for operator progress.
    # Shape: "unitN at parent: detail" / "unitN: status". Prose, not key=value:
    # "scan0: 3 violations in 2 files", as the kernel says "sd0: 244198MB".
    # Config: data/limits.yml#dmesg (enabled: true). Normal is the configured default; verbose and trace are explicit.
    # ENV MASTER_DMESG accepts 0, quiet, normal, verbose, or trace.
    #
    # This shape is the CLI's whole style guide: append-only, one line per fact,
    # no banner. The machine-readable form of the same facts is the event bus
    # and the JSONL ledgers under runtime/, not a second presenter here.
    module Dmesg
      module_function

      LEVELS = %w[quiet normal verbose trace].freeze

      def enabled?
        return false if @verbosity_override == "quiet"
        return false if ENV["MASTER_QUIET"] == "1"

        env = ENV["MASTER_DMESG"].to_s.downcase
        return false if env == "0" || env == "quiet"
        return true if %w[1 normal verbose trace].include?(env)

        cfg.fetch("enabled", true) != false
      end

      def verbosity
        override = @verbosity_override
        return override if override

        env = ENV["MASTER_DMESG"].to_s.downcase
        return "quiet" if env.empty? && ENV["MASTER_QUIET"] == "1"
        return normalize_verbosity(env) unless env.empty?

        normalize_verbosity(cfg.fetch("verbosity", "verbose"))
      end

      def verbose?
        %w[verbose trace].include?(verbosity)
      end

      def trace?
        verbosity == "trace"
      end

      def with_verbosity(level)
        previous = @verbosity_override
        @verbosity_override = normalize_verbosity(level)
        yield
      ensure
        @verbosity_override = previous
      end

      def cfg
        @cfg ||= begin
          data = Master.load_yaml(Master.limits_path, default: {}) || {}
          data["dmesg"].is_a?(Hash) ? data["dmesg"] : { "enabled" => true }
        rescue StandardError
          { "enabled" => true }
        end
      end

      def reload!
        @cfg = nil
        cfg
      end

      def normalize_verbosity(value)
        value = value.to_s.downcase
        value = "normal" if value == "1" || value.empty?
        LEVELS.include?(value) ? value : "normal"
      end

      def attach(unit, parent, detail = nil, io: $stdout)
        line = detail.to_s.empty? ? "#{unit} at #{parent}" : "#{unit} at #{parent}: #{detail}"
        emit(line, io:)
      end

      def status(unit, msg, io: $stdout)
        emit("#{unit}: #{msg}", io:)
      end

      # Finished command and stage reports use the same grammar as live events.
      # Existing dmesg lines pass through unchanged; plain lines attach to one
      # unit instead of inventing headings, gutters or column alignment.
      module Report
        COMMAND_UNITS = {
          "fix" => "fix0", "review" => "review0", "critique" => "crit0",
          "status" => "status0", "help" => "help0", "model" => "model0",
          "plugin" => "plugin0", "device" => "device0", "voice" => "voice0",
          "pair" => "pair0", "owner" => "owner0", "wake" => "wake0",
          "doctor" => "doctor0", "rules" => "rules0", "snapshot" => "snapshot0",
          "why" => "why0", "session" => "session0", "undo" => "undo0",
          "clear" => "cli0", "orders" => "orders0", "soul" => "soul0",
        }.freeze

        UNIT_RE = /\A[a-z][a-z0-9_]*\d+(?: at [a-z][a-z0-9_]*\d+)?:/

        module_function

        def command(command, text, parent: "master0")
          word = command.to_s.strip.split(/\s+/, 2).first.to_s.delete_prefix("/").downcase
          unit = COMMAND_UNITS.fetch(word) { safe_unit(word) }
          render(unit:, parent:, text:)
        end

        def render(unit:, parent:, text:)
          source = text.to_s.scrub.gsub(ANSI, "").delete("\r")
          return "" if source.strip.empty?

          lines = []
          attached = false
          source.lines.each do |raw|
            line = raw.chomp.strip
            if line.empty?
              lines << "" unless lines.empty? || lines.last.empty?
              attached = false
              next
            end

            if UNIT_RE.match?(line)
              lines << line
              attached = true
            elsif attached
              lines << "#{unit}: #{line}"
            else
              lines << "#{unit} at #{parent}: #{line}"
              attached = true
            end
          end
          lines.join("\n").strip
        end

        def print(command, text, parent: "master0", io: $stdout)
          rendered = render(unit: command_unit(command), parent:, text:)
          rendered.lines.each do |line|
            line = line.chomp
            if line.empty?
              io.puts if enabled?
            else
              Dmesg.emit(line, io:, force: true)
            end
          end
          io.flush if io.respond_to?(:flush)
          rendered
        end

        def command_unit(command)
          word = command.to_s.strip.split(/\s+/, 2).first.to_s.delete_prefix("/").downcase
          return word if word.match?(/\A[a-z][a-z0-9_]*\d+\z/)

          COMMAND_UNITS.fetch(word) { safe_unit(word) }
        end

        def safe_unit(word)
          word = word.gsub(/[^a-z0-9_]+/, "_").sub(/\A\d+/, "")
          word = "cli" if word.empty?
          "#{word}0"
        end
      end

      # Work that calls a model names itself, and the calls attach under it.
      # Fiber storage reaches the threads the work spawns, and is put back after.
      def under(unit)
        previous = Fiber[:master_unit]
        Fiber[:master_unit] = unit
        yield
      ensure
        Fiber[:master_unit] = previous
      end

      # Once per process, for a fact every lane would otherwise repeat.
      def once(unit, msg, io: $stdout)
        @once ||= {}
        line = "#{unit}: #{msg}"
        return if @once[line]

        @once[line] = true
        emit(line, io:)
      end

      def emit(line, io: $stdout, force: false)
        return unless enabled? || force

        # Normal mode keeps conversational turns quiet. Explicit command reports
        # force their already-rendered lines through the same presenter.
        if !force && verbosity == "normal" && Fiber[:master_unit] == "master0" && line.match?(/at \w+0|llm\d+:/)
          return
        end

        text = line.to_s.gsub(/\s+/, " ").strip
        io.print "\r\e[K" if io.respond_to?(:tty?) && io.tty?
        io.puts(io.respond_to?(:tty?) && io.tty? ? style(text) : text)
        io.flush if io.respond_to?(:flush)
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.emit")
        nil
      end

      def style(text)
        return text unless $stdout.tty?

        match = text.match(/\A([a-z][a-z0-9_]*\d+)(?: at ([a-z][a-z0-9_]*\d+))?:\s*(.*)\z/)
        return pastel.dim(text) unless match

        unit, parent, detail = match.values_at(1, 2, 3)
        relation = parent ? " at #{parent}" : ""
        "#{pastel.bold(unit)}#{pastel.dim(relation)}: #{detail}"
      rescue StandardError
        text
      end

      ANSI = /\e\[[0-9;?]*[A-Za-z]/
      VERDICT = /\b(?:fail(?:ed|ures?)?|errors?|offen[cs]es?|violations?|exceed(?:s|ed)?|missing|expected|refused)\b/i
      FINDING = Regexp.union(/:\d+\b/, VERDICT)
      FINDING_LIMIT = 8

      def line(unit, parent, detail) = "#{unit} at #{parent}: #{detail}"

      def plain(text) = text.to_s.scrub.gsub(ANSI, "").delete("\r")

      def collapse(lines)
        lines.map(&:chomp).chunk_while { |a, b| a == b }.map do |run|
          run.size > 1 ? "#{run.first} ×#{run.size}" : run.first
        end
      end

      def findings(text, limit: FINDING_LIMIT)
        lines = collapse(plain(text).lines).reject { |candidate| candidate.strip.empty? }
        hits = lines.grep(FINDING)
        picked = hits.empty? ? lines.last(limit) : hits.first(limit)
        picked.map { |finding| finding.strip[0, 200] }
      end

      def duration(seconds)
        return format("%.1fs", seconds) if seconds < 60

        minutes, rest = seconds.round.divmod(60)
        "#{minutes}m #{rest}s"
      end

      def counted(number, noun) = "#{number} #{noun}#{"s" unless number == 1}"

      def pastel
        require "pastel"
        @pastel ||= Pastel.new
      end

      # A turn as the kernel would print it. Every model call, file, command
      # and request attaches as a numbered unit under its parent, the way sd1 is
      # the second disk, then reports once on what it did. A parent attaches
      # before its first child. An event with no unit renders nothing and stays
      # in the event log.
      class Console
        TOOL_UNITS = {
          "read_file" => %w[read io0], "list_dir" => %w[list io0], "search_files" => %w[grep io0],
          "search_knowledge" => %w[grep io0], "symbol_lookup" => %w[grep io0], "write_file" => %w[write io0],
          "str_replace" => %w[edit io0], "replace" => %w[edit io0], "ast_edit" => %w[edit io0],
          "zsh" => %w[exec io0], "git_context" => %w[git io0], "web_fetch" => %w[fetch net0],
          "web_search" => %w[search net0], "dynamic_http" => %w[http net0], "ask_llm" => %w[ask io0]
        }.freeze
        FOLD_UNITS = { "read" => "read", "write" => "write", "exec" => "exec", "git" => "git",
                       "ask" => "ask", "critique" => "crit" }.freeze
        PARENT_DETAIL = { "io0" => "files and commands", "net0" => "network", "fold0" => "coding loop" }.freeze
        DETAIL_CHARS = 96
        MS_PER_SECOND = 1000.0
        CENTS_PER_DOLLAR = 100

        def initialize
          @count = Hash.new(0)
          @open = {}
          @attached = {}
          @usage = nil
          @llm = {}
          @llm_parent = {}
          @ledger = Hash.new(0)
        end

        def lines(payload)
          track(payload)
          case payload[:event].to_s
          when "llm:send" then llm_send(payload)
          when "llm:call_complete" then remember_usage(payload)
          when "llm:provider_outcome" then llm_outcome(payload)
          when "tool:call" then tool_call(payload)
          when "tool:return" then tool_return(payload)
          when "fold:risk" then parent("fold0", "master0", "risk #{payload[:risk]}")
          when "core:reason" then ["fold0: #{clip(payload[:why])}"]
          when "core:turn" then fold_turn(payload)
          when "fix_loop:terminal" then terminal(payload)
          when "wishlist:done" then ["wish0: drafted #{payload[:drafted]} proposal(s)"]
          when "wishlist:error" then ["wish0: failed — #{clip(payload[:error])}"]
          else
            verbose_event(payload)
          end
        end

        private

        # Lanes ask in parallel, often of one model, so a call is its model on
        # its thread: the bus publishes in the caller's thread, and a call's
        # send and outcome happen on the same one. A call attaches to the unit
        # that asked for it, fold0 or scan0, named by Dmesg.under; anything else
        # asks from master0.
        #
        # A burst is not a conversation. A scan asks a model per file per rule,
        # and a line for each send and each outcome buried the operator: the
        # 2026-09-16 /fix printed some two thousand llm lines, every one of them
        # a lane failing over to the next, and no report at the end. The first
        # calls under a unit still attach, as devices do; past that the unit
        # speaks in rollups — how many were asked, how many failed, how many
        # lanes it walked — and a failure the chain recovered from is not news.
        # Every call is still in runtime/events/activity.jsonl.
        BURST_AFTER = 3
        ROLLUP_EVERY = 25
        ROLLUP_SECONDS = 20

        def llm_send(payload)
          parent = Fiber[:master_unit] || "master0"
          unit = open_unit("llm", llm_key(payload))
          @llm_parent[llm_key(payload)] = parent
          tally = llm_tally(parent)
          tally[:calls] += 1
          tally[:models] << model_name(payload[:model])
          return ["#{unit} at #{parent}: #{model_name(payload[:model])}"] if Dmesg.verbose? || tally[:calls] <= BURST_AFTER

          rollup(parent, tally)
        end

        def llm_outcome(payload)
          key = llm_key(payload)
          unit = @open.delete(key) || "llm0"
          # The outcome is published on the thread that sent, so the unit that
          # asked is still in fiber storage when the send's key does not match.
          parent = @llm_parent.delete(key) || Fiber[:master_unit] || "master0"
          usage, @usage = @usage, nil
          tally = llm_tally(parent)
          tally[:failed] += 1 unless payload[:status].to_s == "success"
          return rollup(parent, tally) if !Dmesg.verbose? && tally[:calls] > BURST_AFTER

          return ["#{unit}: #{payload[:status]}, #{clip(payload[:error])}"] unless payload[:status].to_s == "success"

          ["#{unit}: #{[tokens(usage), seconds(payload[:latency_ms]), cents(usage)].compact.join(', ')}"]
        end

        def llm_tally(parent)
          @llm[parent] ||= { calls: 0, failed: 0, models: Set.new, said: 0, at: monotonic }
        end

        # One line per ROLLUP_SECONDS or ROLLUP_EVERY calls, whichever comes
        # first, and never one that repeats the last.
        def rollup(parent, tally)
          since = tally[:calls] - tally[:said]
          return [] if since < ROLLUP_EVERY && monotonic - tally[:at] < ROLLUP_SECONDS
          return [] if since.zero?

          tally[:said] = tally[:calls]
          tally[:at] = monotonic
          failed = tally[:failed].positive? ? ", #{tally[:failed]} failed" : ""
          ["#{parent}: #{counted(tally[:calls], "model call")}#{failed}, #{counted(tally[:models].size, "lane")}"]
        end

        def track(payload)
          event = payload[:event].to_s
          event.start_with?("llm:") ? track_model(event, payload) : track_repair(event, payload)
        end

        def track_model(event, payload)
          case event
          when "llm:send"
            @ledger[:model_calls] += 1
          when "llm:provider_outcome"
            @ledger[:model_failures] += 1 unless payload[:status].to_s == "success"
          end
        end

        def track_repair(event, payload)
          case event
          when "fix_loop:pass_start"
            @ledger[:passes] = [@ledger[:passes].to_i, payload[:pass].to_i].max
            @ledger[:files] = [@ledger[:files].to_i, payload[:file_count].to_i].max
          when "fix_loop:scan_progress" then @ledger[:finding_files] += 1
          when "fix_loop:rule_result", "rule_loop:pass"
            @ledger[:rules] += 1
            @ledger[:violations] += payload[:violations].to_i
            @ledger[:fixed] += payload[:fixed].to_i
          when "rule_loop:fix_applied", "fix_loop:ast_fixed" then @ledger[:changes] += 1
          when "fix_loop:improvement_fix", "fix_loop:opportunity_fix", "fix_loop:visual_fix"
            @ledger[:model_fixes] += payload[:fixed].to_i
          when "fix_loop:improvement_council" then @ledger[:council] += 1
          when "fix_loop:human_decision_required" then @ledger[:human_decisions] += 1
          end
        end

        # Per-item churn: one line for each file a scan reads, passes or finishes,
        # each finding a hook sees, each cognition tick. A chat turn that set off
        # a background self-scan printed 2,657 of these ahead of a one-line
        # reply. Verbose shows the work; trace shows every item of it.
        CHURN = %w[scan:file_read scan:pass scan:complete scan:semantic_skipped scan:progress
                   hook:on_violation_found cognition:tick homeostat:observe conflict:resolved].freeze

        def verbose_event(payload)
          return [] unless Dmesg.verbose? || Dmesg.trace?

          event = payload[:event].to_s
          return [] if event.empty?
          return [] if CHURN.include?(event) && !Dmesg.trace?

          [event_line(payload)]
        end

        def event_line(payload)
          event = payload[:event].to_s
          component, action = event.split(":", 2)
          unit = DmesgUnit.unit_name(component)
          detail = event_detail(payload, action:)
          detail = trace_detail(payload) if Dmesg.trace?
          detail.empty? ? "#{unit}: #{action || "event"}" : "#{unit}: #{action || "event"}, #{detail}"
        end

        EVENT_FIELDS = %i[target path file pass file_count count rule status state fixed violations changes stage reason category ms bytes critiques files].freeze

        def trace_detail(payload)
          data = payload.reject { |key, _| %i[event ts].include?(key.to_sym) }
          rendered = Master::Ground::Redactor.payload(data).to_s
          clip(rendered, DETAIL_CHARS)
        rescue StandardError
          event_detail(payload)
        end

        def event_detail(payload, action: nil)
          values = EVENT_FIELDS.filter_map do |key|
            next if key.to_s == action.to_s
            value = payload[key]
            next if value.nil? || value == ""

            label = key.to_s.tr("_", " ")
            rendered = case value
                       when Array then value.first(3).map(&:to_s).join(", ")
                       else value.to_s
                       end
            next if rendered.empty?

            "#{label} #{clip(rendered, 72)}"
          end
          values.join(", ")
        end

        def terminal(payload)
          state = payload[:state].to_s
          message = clip(payload[:message], 80)
          lines = ["fix0: terminal #{state}"]
          lines[0] = "#{lines[0]}, #{message}" unless message.empty?
          return lines unless Dmesg.verbose? || Dmesg.trace?

          ledger = []
          ledger << counted(@ledger[:files].to_i, "file in scope") if @ledger[:files].to_i.positive?
          ledger << counted(@ledger[:rules].to_i, "rule pass") if @ledger[:rules].to_i.positive?
          ledger << counted(@ledger[:violations].to_i, "rule finding") if @ledger[:violations].to_i.positive?
          ledger << counted(@ledger[:fixed].to_i, "fix") if @ledger[:fixed].to_i.positive?
          ledger << counted(@ledger[:changes].to_i, "change") if @ledger[:changes].to_i.positive?
          ledger << counted(@ledger[:model_calls].to_i, "model call") if @ledger[:model_calls].to_i.positive?
          ledger << counted(@ledger[:model_failures].to_i, "model failure") if @ledger[:model_failures].to_i.positive?
          ledger << counted(@ledger[:council].to_i, "council review") if @ledger[:council].to_i.positive?
          ledger << counted(@ledger[:human_decisions].to_i, "human decision") if @ledger[:human_decisions].to_i.positive?
          lines << "fix0: ledger, #{ledger.join(", ")}" unless ledger.empty?
          @ledger = Hash.new(0)
          lines
        end

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Tokens and cost arrive inside the call; the outcome that closes the
        # unit arrives after it.
        def remember_usage(payload)
          @usage = payload
          []
        end

        def tool_call(payload)
          kind, parent_unit = TOOL_UNITS.fetch(payload[:tool].to_s, [payload[:tool].to_s, "io0"])
          unit = open_unit(kind, "tool:#{payload[:tool]}")
          [*parent(parent_unit, "master0"), "#{unit} at #{parent_unit}: #{clip(payload[:subject])}"]
        end

        def tool_return(payload)
          unit = @open.delete("tool:#{payload[:tool]}")
          return [] unless unit
          return ["#{unit}: #{clip(payload[:error])}"] unless payload[:ok]

          ["#{unit}: #{[size(payload[:bytes]), seconds(payload[:ms])].compact.join(', ')}"]
        end

        def fold_turn(payload)
          verb = payload[:verb].to_s
          lines = parent("fold0", "master0")
          return lines << "fold0: done, #{counted(payload[:turn].to_i + 1, "turn")}" if verb == "done"
          return lines << "fold0: #{verb}, #{clip(payload[:subject])}" unless FOLD_UNITS.key?(verb)

          unit = next_unit(FOLD_UNITS[verb])
          lines << "#{unit} at fold0: #{clip(payload[:subject])}"
          lines << "#{unit}: #{fold_result(verb, payload)}"
        end

        def fold_result(verb, payload)
          detail = payload[:detail].to_s
          lines = detail.lines
          return clip(lines.last) unless payload[:ok]
          return "#{size(detail.bytesize)}, #{counted(lines.size, "line")}" if verb == "read"
          return "ok, #{counted(lines.size, "line")}" if verb == "exec"

          clip(lines.first || "ok")
        end

        def parent(unit, grandparent, detail = PARENT_DETAIL[unit])
          return [] if @attached[unit]

          @attached[unit] = true
          ["#{unit} at #{grandparent}: #{detail}"]
        end

        def open_unit(kind, key)
          @open[key] = next_unit(kind)
        end

        def next_unit(kind)
          number = @count[kind]
          @count[kind] += 1
          "#{kind}#{number}"
        end

        def llm_key(payload) = "llm:#{Thread.current.object_id}:#{payload[:model]}"

        def model_name(model) = model.to_s.delete_suffix(":free")

        def tokens(usage)
          return unless usage

          return "#{usage[:tokens_out].to_i} tokens out" if usage[:tokens_in].to_i.zero?

          "#{usage[:tokens_in].to_i} tokens in, #{usage[:tokens_out].to_i} out"
        end

        def cents(usage)
          cost = usage && usage[:cost_usd].to_f
          cost&.positive? ? format("%.2f cents", cost * CENTS_PER_DOLLAR) : nil
        end

        def seconds(ms) = ms ? format("%.1fs", ms.to_f / MS_PER_SECOND) : nil

        def size(bytes) = bytes ? counted(bytes.to_i, "byte") : nil

        def counted(number, noun) = Dmesg.counted(number, noun)

        def clip(text, limit = DETAIL_CHARS)
          flat = text.to_s.gsub(/\s+/, " ").strip
          flat.length > limit ? "#{flat[0, limit - 1]}…" : flat
        end
      end
    end
  end
end
