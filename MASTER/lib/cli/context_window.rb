# frozen_string_literal: true

require "fileutils"

module Master
  module CLI
    class ContextWindow
      SOFT_THRESHOLD = 0.65
      HARD_THRESHOLD = 0.90
      KEEP_TAIL = 4
      CONTEXT_SCHEMA = 1
      STRUCTURED_KEYS = %w[goal decisions facts files open_work constraints uncertainty].freeze
      private_constant :SOFT_THRESHOLD, :HARD_THRESHOLD, :KEEP_TAIL, :CONTEXT_SCHEMA, :STRUCTURED_KEYS

      attr_reader :session, :agent, :model_context

      def initialize(session:, agent: nil, model_context: 200_000, event_bus: nil, root: Master::ROOT)
        @session = session
        @agent = agent
        @model_context = model_context
        @bus = event_bus
        @root = root
        @soft_mutex = Mutex.new
        @soft_running = false
      end

      def check_and_compact!
        return Result.ok(:ok) unless agent

        ratio = pressure_ratio
        return Result.ok(:ok) if ratio < SOFT_THRESHOLD
        return compact!(:hard) if ratio >= HARD_THRESHOLD

        schedule_soft_compaction!
        Result.ok(:soft_scheduled)
      end

      private

      def pressure_ratio
        est = session.respond_to?(:token_pressure) ? session.token_pressure : session.token_est
        return 0.0 unless est.is_a?(Numeric) && model_context.positive?

        est.to_f / model_context
      end

      def schedule_soft_compaction!
        @soft_mutex.synchronize do
          return if @soft_running

          @soft_running = true
        end
        Thread.new do
          compact!(:soft)
        ensure
          @soft_mutex.synchronize { @soft_running = false }
        end
      end

      # The summary covers a snapshot minus its last KEEP_TAIL messages. Sending
      # the whole transcript at 90% of the window leaves no room for the reply,
      # and the recent turns read better verbatim. The session then swaps only
      # the summarised prefix, so a soft compaction running beside a turn keeps
      # whatever that turn appended.
      def compact!(tier)
        est = session.token_est
        threshold = tier == :hard ? HARD_THRESHOLD : SOFT_THRESHOLD
        @bus&.publish("compaction:start", token_est: est, threshold:, tier:, model_context:)
        snapshot = session.messages.dup
        head = snapshot.size > KEEP_TAIL ? snapshot[0...-KEEP_TAIL] : snapshot
        summary = agent.ask(
          structured_summary_prompt,
          context: head,
        )
        body, structured = render_compacted_context(summary, tier:)
        session.compact_prefix!(head.size, body)
        @bus&.publish("compaction:done", summary: body, structured:, token_est: session.token_est, tier:)
        append_daily_log(body, tier:)
        Result.ok(:compacted)
      rescue StandardError => e
        @bus&.publish("compaction:error", error: e.message, tier:)
        Result.err("context compaction failed: #{e.message}", category: :infrastructure)
      end

      def structured_summary_prompt
        <<~PROMPT
          Compress the supplied conversation into JSON only. Preserve facts, decisions,
          file paths, open work and constraints. Do not invent anything. Use exactly these
          keys: goal, decisions, facts, files, open_work, constraints, uncertainty.
          Every value except goal must be an array of short strings. Use [] when there is
          no evidence. Keep concrete paths and commands verbatim. Do not include Markdown.
        PROMPT
      end

      def render_compacted_context(raw, tier:)
        data = parse_structured_summary(raw)
        return [structured_body(data, tier:), true] if data

        ["[Context compacted — #{tier}]\n\n#{raw}", false]
      end

      def parse_structured_summary(raw)
        data = JSON.parse(raw.to_s)
        return unless data.is_a?(Hash)

        normalized = {}
        STRUCTURED_KEYS.each do |key|
          value = data[key] || data[key.to_sym]
          if key == "goal"
            normalized[key] = value.to_s.strip
          else
            return unless value.is_a?(Array)
            normalized[key] = value.map { |item| item.to_s.strip }.reject(&:empty?).first(12)
          end
        end
        normalized["goal"] = normalized["goal"][0, 320]
        normalized
      rescue JSON::ParserError, TypeError
        nil
      end

      def structured_body(data, tier:)
        lines = ["[Context compacted — #{tier}; schema #{CONTEXT_SCHEMA}]"]
        STRUCTURED_KEYS.each do |key|
          value = key == "goal" ? data[key] : data[key]
          next if value.respond_to?(:empty?) && value.empty?

          lines << "#{key}:"
          Array(value).each { |item| lines << "- #{item}" }
        end
        lines.join("\\n")
      end

      def append_daily_log(summary, tier:)
        day = Time.now.strftime("%Y-%m-%d")
        path = File.join(@root, ".master", "daily", "#{day}.md")
        FileUtils.mkdir_p(File.dirname(path))
        stamp = Time.now.utc.iso8601
        bullets = summary.to_s.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line.delete_prefix("- ").strip}" }
        entry = "\n## Compaction #{tier} #{stamp}\n#{bullets.join("\n")}\n"
        File.open(path, "a") { |io| io.write(entry) }
        @bus&.publish("compaction:logged", path:, tier:)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "context_window.daily_log", event_bus: @bus)
      end
    end
  end
end
