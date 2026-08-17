# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Infer — promote natural-language messages to :command intent via data/patterns.yml (infer namespace).
      class Infer
        PRESSURE_PATTERN = /\b(?:urgent|asap|immediately|critical|now|hurry|fast|quick(?:ly)?|emergency|sos)\b/i.freeze

        TASK_TYPE_PATTERNS = {
          architecture: Regexp.new(
            '\b(?:restructur|reorganiz|hierarch|layout|folder|director|module\s+boundar|' \
            'decouple|extract\s+(?:a\s+)?(?:module|class|layer|service)|where\s+should|' \
            'how\s+should\s+(?:we|i)\s+organiz|split\s+(?:this\s+)?(?:into|across)|consolidat)',
            Regexp::IGNORECASE,
          ),
          coding: Regexp.new(
            '\b(?:def |class |module |require |\.rb\b|fix\s+(?:the\s+)?(?:bug|error|issue)|' \
            'refactor|implement|write\s+(?:a\s+)?(?:method|class|function|test)|' \
            'add\s+(?:a\s+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))',
            Regexp::IGNORECASE,
          ),
          research: Regexp.new(
            '\b(?:search|find\s+(?:all|every|info)|research|look\s+up|what\s+is|' \
            'explain\s+(?:how|what|why)|tell\s+me\s+about)\b', Regexp::IGNORECASE
          ),
          qa: /\?(?:\s*$|\s+[A-Z])/m,
        }.freeze

        PATTERNS_PATH = Master.data_path("patterns.yml").freeze
        REPEAT_BIAS = /\A(?:again|same|repeat|once\s+more|do\s+that|one\s+more\s+time)\b/i.freeze
        NB_LOCALE = /[æøåÆØÅ]|\b(?:ikke|jeg|deg|eller|dette|skal|vil|kan|hva|hvor|nå|gjør|kjør|fiks|rydd)\b/i.freeze

        INFER_ALIASES = {
          "restart" => "rebuild",
          "principles" => "axioms",
        }.freeze

        INFER_DESTRUCTIVE = %w[clear rebuild resync shell rollback].freeze

        def initialize(bus: nil, session: nil)
          @bus = bus
          @session = session
          @patterns, @negatives, @destructive = load_patterns
        end

        def call(ctx)
          return Result.ok(ctx) unless ctx.intent == :llm

          msg = ctx.message.to_s.strip
          locale = detect_locale(msg)

          biased = bias_repeat_command(msg)
          return promote(ctx, biased, locale) if biased

          best = find_best_match(msg, locale)
          return pass_through(ctx, msg, locale) unless best

          if blocked_by_negative?(msg, best[:command])
            publish_rejected(best[:command], msg, "negative_pattern")
            return pass_through(ctx, msg, locale)
          end

          apply_inference(ctx, best, msg, locale)
        end

        def apply_inference(ctx, best, msg, locale)
          resolved = INFER_ALIASES.fetch(best[:command], best[:command])
          args = extract_args(cmd: best[:command], capture: best[:capture], match: best[:match], msg:)
          guard = constitutional_guard(resolved, args, msg)
          return guard if guard.is_a?(Master::Result::Err)

          publish_infer(resolved, args, msg, best[:confidence], locale)
          remember_inference(resolved, args)
          Result.ok(ctx.merge(
            intent: :command, command: resolved, args:, inferred_command: resolved,
            locale:, infer_confidence: best[:confidence], task_type: infer_task_type(msg)
          ))
        end

        private

        def pass_through(ctx, msg, locale)
          pressure = msg.match?(PRESSURE_PATTERN)
          task_type = infer_task_type(msg)
          Result.ok(ctx.merge(task_type:, pressure: pressure || ctx.pressure, locale:))
        end

        def promote(ctx, hit, locale)
          publish_infer(hit[:command], hit[:args], hit[:msg], hit[:confidence], locale)
          remember_inference(hit[:command], hit[:args])
          Result.ok(ctx.merge(
            intent: :command, command: hit[:command], args: hit[:args], inferred_command: hit[:command],
            locale:, infer_confidence: hit[:confidence], task_type: infer_task_type(hit[:msg])
          ))
        end

        def bias_repeat_command(msg)
          return unless @session && msg.match?(REPEAT_BIAS)
          cmd = @session.last_inferred_command.to_s
          return if cmd.empty?

          { command: cmd, args: @session.last_inferred_args.to_s, msg:, confidence: 0.92, match: nil, capture: "" }
        end

        def find_best_match(msg, locale)
          best = nil
          @patterns.each do |cmd, entry|
            entry[:regexes].each_with_index do |pattern, index|
              next unless (m = msg.match(pattern))
              score = match_confidence(pattern, m, msg, locale, index)
              candidate = { command: cmd, match: m, capture: entry[:capture], confidence: score }
              best = candidate if best.nil? || score > best[:confidence]
            end
          end
          best
        end

        def match_confidence(pattern, match, msg, locale, index)
          base = 0.55
          base += 0.15 if match[0].length >= msg.length * 0.4
          base += 0.1 if match.captures.compact.any?
          base += 0.05 if pattern.source.length > 40
          base += 0.08 if locale == :nb && pattern.source.match?(/[æøå]|ikke|jeg/i)
          base += 0.03 if index.zero?
          base -= 0.1 if msg.length > 200 && match[0].length < 12
          [[base, 0.35].max, 0.98].min
        end

        def blocked_by_negative?(msg, command)
          @negatives.any? do |row|
            next false unless row[:blocks].empty? || row[:blocks].include?(command)
            msg.match?(row[:pattern])
          end
        end

        def constitutional_guard(command, _args, msg)
          return unless @destructive.include?(command)
          return if explicit_destructive_consent?(msg)

          publish_rejected(command, msg, "destructive_guard")
          Master::Result.err(
            "infer: /#{command} requires explicit /#{command} — natural language blocked",
            category: :policy,
          )
        end

        def explicit_destructive_consent?(msg)
          msg.match?(/\b(?:yes|confirm|i\s+mean\s+it|explicitly|go\s+ahead)\b/i)
        end

        def detect_locale(msg)
          msg.match?(NB_LOCALE) ? :nb : :en
        end

        def infer_task_type(msg)
          TASK_TYPE_PATTERNS.each { |type, pat| return type if msg.match?(pat) }
          :general
        end

        def remember_inference(command, args)
          return unless @session.respond_to?(:last_inferred_command=)

          @session.last_inferred_command = command
          @session.last_inferred_args = args.to_s
        end

        def publish_infer(command, args, msg, confidence, locale)
          payload = { command:, args:, preview: msg[0, 80], confidence:, locale: }
          @bus&.publish("infer:resolved", **payload)
          @bus&.publish("infer:confidence", **payload)
        end

        def publish_rejected(command, msg, reason)
          @bus&.publish("infer:rejected", command:, preview: msg[0, 80], reason:)
        end

        def load_patterns
          return [{}, [], INFER_DESTRUCTIVE] unless File.exist?(PATTERNS_PATH)
          data = Master.load_yaml(PATTERNS_PATH) || {}
          infer = data["infer"] || {}
          commands = infer["commands"] || {}
          patterns = commands.each_with_object({}) do |(name, spec), out|
            regexes = (spec["patterns"] || []).map { |src| Regexp.new(src, Regexp::IGNORECASE | Regexp::EXTENDED) }
            out[name.to_s] = { regexes:, capture: spec["capture"].to_s }
          end
          negatives = Array(infer["negative"]).filter_map do |row|
            src = row["pattern"].to_s
            next if src.empty?
            { pattern: Regexp.new(src, Regexp::IGNORECASE), blocks: Array(row["blocks"]).map(&:to_s) }
          end
          destructive = Array(infer["destructive"]).map(&:to_s)
          destructive = INFER_DESTRUCTIVE if destructive.empty?
          [patterns, negatives, destructive]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "infer.load_patterns")
          [{}, [], INFER_DESTRUCTIVE]
        end

        def extract_args(cmd:, capture:, match:, msg:)
          case capture
          when "path", "cycles", "on_off", "first_group", "music_sub"
            extract_args_group1(capture, match, msg)
          else
            extract_args_group2(capture, match, msg)
          end
        end

        def extract_args_group1(capture, match, msg)
          case capture
          when "path"
            path = match&.[](1)&.strip
            path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
            path.to_s
          when "cycles"
            (match&.[](1) || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
          when "on_off"
            msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
          when "first_group"
            match&.captures&.compact&.first.to_s.strip
          when "music_sub"
            msg.match?(/\b(?:radio\s+bergen|warp\s+tunnel|flying\s+lotus|madlib)\b/i) ? "radio" : ""
          end
        end

        def extract_args_group2(capture, match, msg)
          case capture
          when "persona_name"
            (match&.[](1) || match&.[](2) || match&.[](3)).to_s.strip
          when "soul_subcmd"
            msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
          when "orders_subcmd"
            msg.match?(/\blist|show\b/i) ? "list" : ""
          when "scan_profile", "scan_depth"
            match&.[](1)&.strip.to_s
          else
            ""
          end
        end
      end
    end
  end
end
