# frozen_string_literal: true

require "fileutils"

module Master
  module CLI
    class ContextWindow
      SOFT_THRESHOLD = 0.65
      HARD_THRESHOLD = 0.90
      private_constant :SOFT_THRESHOLD, :HARD_THRESHOLD

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
        est = session.token_est
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

      def compact!(tier)
        est = session.token_est
        threshold = tier == :hard ? HARD_THRESHOLD : SOFT_THRESHOLD
        @bus&.publish("compaction:start", token_est: est, threshold:, tier:, model_context: model_context)
        summary = agent.ask(
          "Summarize our progress as bullet points. Preserve all file paths, decisions, and remaining tasks.",
          context: session.messages
        )
        session.clear!
        body = "[Context compacted — #{tier}]\n\n#{summary}"
        session.add_message(role: :assistant, content: body)
        @bus&.publish("compaction:done", summary: summary.to_s, token_est: session.token_est, tier:)
        append_daily_log(summary, tier:)
        Result.ok(:compacted)
      rescue StandardError => e
        @bus&.publish("compaction:error", error: e.message, tier:)
        Result.err("context compaction failed: #{e.message}", category: :infrastructure)
      end

      def append_daily_log(summary, tier:)
        day = Time.now.strftime("%Y-%m-%d")
        path = File.join(@root, ".master", "daily", "#{day}.md")
        FileUtils.mkdir_p(File.dirname(path))
        stamp = Time.now.utc.iso8601
        bullets = summary.to_s.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line.delete_prefix("- ").strip}" }
        entry = "\n## Compaction #{tier} #{stamp}\n#{bullets.join("\n")}\n"
        File.open(path, "a") { |io| io.write(entry) }
        @bus&.publish("compaction:logged", path: path, tier:)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "context_window.daily_log", event_bus: @bus)
      end
    end
  end
end
