# frozen_string_literal: true

require "set"
# DmesgUnit names each event component's unit. It lives in logging.rb, and no
# autoload reaches it by that name.
require_relative "logging"

module Master
  module Trace
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

      def with_log_voice
        previous = @log_voice_active
        @log_voice_active = true
        yield
      ensure
        @log_voice_active = previous
      end

      def log_voice_active?
        @log_voice_active == true
      end

      def log_voice_spoken_recently?(text, window: 8.0)
        clean = text.to_s.gsub(/\s+/, " ").strip
        return false if clean.empty?

        recent = @recent_log_voice
        return false unless recent

        timestamp, spoken = recent
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - timestamp) <= window && spoken == clean
      rescue StandardError
        false
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

      module Report
        COMMAND_UNITS = {
          "fix" => "fix0", "review" => "review0", "critique" => "crit0",
          "status" => "status0", "help" => "help0", "model" => "model0",
          "plugin" => "plugin0", "android" => "android0", "ios" => "ios0",
          "device" => "device0", "voice" => "voice0",
          "pair" => "pair0", "owner" => "owner0", "wake" => "wake0",
          "doctor" => "doctor0", "rules" => "rules0", "snapshot" => "snapshot0",
          "why" => "why0", "session" => "session0", "undo" => "undo0",
          "clear" => "cli0", "orders" => "orders0", "soul" => "soul0",
        }.freeze

        UNIT_RE = /\A[a-z][a-z0-9_]*\d+(?: at [a-z][a-z0-9_]*\d+)?:/

        module_function

        def command(command, text, parent: "master0")
          word = command.to_s.strip.split(/\s+/, 2).first.to_s.delete_prefix("/").downcase
          render(unit: COMMAND_UNITS.fetch(word) { safe_unit(word) }, parent:, text:)
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
              io.puts
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

      def under(unit)
        previous = Fiber[:master_unit]
        Fiber[:master_unit] = unit
        yield
      ensure
        Fiber[:master_unit] = previous
      end

      def once(unit, msg, io: $stdout)
        @once ||= {}
        line = "#{unit}: #{msg}"
        return if @once[line]

        @once[line] = true
        emit(line, io:)
      end

      def emit(line, io: $stdout, force: false)
        return unless enabled? || force

        if !force && verbosity == "normal" && Fiber[:master_unit] == "master0" && line.match?(/at \w+0|llm\d+:/)
          return
        end

        text = line.to_s.gsub(/\s+/, " ").strip
        emit_mutex.synchronize do
          io.puts(text)
          io.flush if io.respond_to?(:flush)
        end
        speak_log_line(text) if log_voice_active?
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.emit")
        nil
      end

      def emit_mutex
        @emit_mutex ||= Mutex.new
      end

      def forward(line, io: $stdout)
        text = line.to_s.scrub.gsub(ANSI, "").delete("\r").chomp
        return if text.strip.empty?

        emit_mutex.synchronize do
          io.puts(text)
          io.flush if io.respond_to?(:flush)
        end
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.forward")
        nil
      end

      def speak_log_line(text)
        return if Thread.current[:master_dmesg_tts]
        return if text.match?(/\A(?:voice|tts)\d+(?: at [^:]+)?:/i)

        require_relative "../voice/playback"
        return unless Master::Voice::Playback.enabled?
        return unless Master::Voice::Playback.available?

        speech = Master::Voice::Speech
        clean = speech.clean_text(text)
        return if clean.empty?

        Thread.current[:master_dmesg_tts] = true
        accepted = Master::Voice::Playback.enqueue(
          clean,
          voice: Master::Voice::Policy.operator_log_voice,
          style: :neutral,
          rate: Master::Voice::Policy.operator_log_rate,
          pitch: Master::Voice::Policy.operator_log_pitch,
          last: true,
        )
        @recent_log_voice = [Process.clock_gettime(Process::CLOCK_MONOTONIC), clean] if accepted
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.log_voice")
      ensure
        Thread.current[:master_dmesg_tts] = false
      end

      def style(text, io: $stdout)
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
        nil
      end

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
          when "llm:send" then @ledger[:model_calls] += 1
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
          when "fix_loop:rule_result", "law_loop:pass"
            @ledger[:rules] += 1
            @ledger[:violations] += payload[:violations].to_i
            @ledger[:fixed] += payload[:fixed].to_i
          when "law_loop:fix_applied", "fix_loop:ast_fixed" then @ledger[:changes] += 1
          when "fix_loop:improvement_fix", "fix_loop:opportunity_fix", "fix_loop:visual_fix"
            @ledger[:model_fixes] += payload[:fixed].to_i
          when "fix_loop:improvement_council" then @ledger[:council] += 1
          when "fix_loop:human_decision_required" then @ledger[:human_decisions] += 1
          end
        end

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
          EVENT_FIELDS.filter_map do |key|
            next if key.to_s == action.to_s
            value = payload[key]
            next if value.nil? || value.to_s.empty?

            "#{key}=#{clip(value)}"
          end.join(", ")
        end

        def terminal(payload)
          status = payload[:status] || payload[:state] || "unknown"
          detail = [payload[:reason], payload[:summary]].compact.map { |v| clip(v) }.reject(&:empty?).join(", ")
          ["fix0: #{status}#{detail.empty? ? "" : ", #{detail}"}"]
        end

        def parent(unit, parent, detail)
          ["#{unit} at #{parent}: #{clip(detail)}"]
        end

        def tool_call(payload)
          name = payload[:tool].to_s
          unit, parent = tool_unit(name, payload)
          @attached[tool_key(payload)] = true
          @count[unit] += 1
          ["#{unit} at #{parent}: #{tool_detail(name, payload)}"]
        end

        def tool_return(payload)
          name = payload[:tool].to_s
          unit, _parent = tool_unit(name, payload)
          ["#{unit}: #{tool_return_detail(payload)}"]
        end

        def tool_unit(name, payload)
          configured = TOOL_UNITS[name]
          return [configured.first, configured.last] if configured

          unit = DmesgUnit.unit_name(name)
          [unit, payload[:parent].to_s.empty? ? "io0" : payload[:parent].to_s]
        end

        def tool_key(payload)
          [payload[:tool], payload[:id], payload[:ts]].map(&:to_s).join(":")
        end

        def open_unit(prefix, key)
          @count[prefix] += 1
          "#{prefix}#{@count[prefix]}"
        end

        def model_name(model)
          model.to_s.empty? ? "unknown" : model.to_s
        end

        def tokens(usage)
          value = usage && (usage[:total_tokens] || usage["total_tokens"])
          value ? "#{value} tokens" : nil
        end

        def seconds(milliseconds)
          value = milliseconds.to_f
          value.positive? ? format("%.1fs", value / MS_PER_SECOND) : nil
        end

        def cents(usage)
          value = usage && (usage[:cost] || usage["cost"])
          return nil unless value
          format("$%.2f", value.to_f / CENTS_PER_DOLLAR)
        end

        def llm_key(payload)
          [payload[:id], payload[:model], payload[:ts]].map(&:to_s).join(":")
        end

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def clip(value, max = DETAIL_CHARS)
          value.to_s.gsub(/s+/, " ").strip[0, max].to_s
        end

        def remember_usage(payload)
          @usage = payload[:usage]
        end

        def fold_turn(payload)
          detail = clip(payload[:summary] || payload[:goal] || payload[:state])
          detail.empty? ? [] : ["fold0: #{detail}"]
        end
      end

      def self.test_reset!
        @cfg = nil
        @pastel = nil
        @recent_log_voice = nil
        @log_voice_active = false
        @verbosity_override = nil
        @once = nil
      end
    end
  end
end
