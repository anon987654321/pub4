# frozen_string_literal: true

require "fileutils"

module Master
  module Now
    class ContextWindow
      COMPACT_THRESHOLD = 0.70
      private_constant :COMPACT_THRESHOLD

      attr_reader :session, :agent, :model_context

      def initialize(session:, agent: nil, model_context: 200_000, event_bus: nil, root: Master::ROOT)
        @session = session
        @agent = agent
        @model_context = model_context
        @bus = event_bus
        @root = root
      end

      def check_and_compact!
        return Result.ok(:ok) unless agent
        return Result.ok(:ok) unless safe_to_compact?

        compact!
      end

      private

      def safe_to_compact?
        est = session.token_est
        return false unless est.is_a?(Numeric)

        est >= model_context * COMPACT_THRESHOLD
      end

      def compact!
        est = session.token_est
        @bus&.publish("compaction:start", token_est: est, threshold: COMPACT_THRESHOLD, model_context: model_context)
        summary = agent.ask(
          "Summarize our progress as bullet points. Preserve all file paths, decisions, and remaining tasks.",
          context: session.messages
        )
        session.clear!
        body = "[Context compacted]\n\n#{summary}"
        session.add_message(role: :assistant, content: body)
        @bus&.publish("compaction:done", summary: summary.to_s, token_est: session.token_est)
        append_daily_log(summary)
        Result.ok(:compacted)
      rescue StandardError => e
        @bus&.publish("compaction:error", error: e.message)
        Result.err("context compaction failed: #{e.message}", category: :infrastructure)
      end

      def append_daily_log(summary)
        day = Time.now.strftime("%Y-%m-%d")
        path = File.join(@root, ".master", "daily", "#{day}.md")
        FileUtils.mkdir_p(File.dirname(path))
        stamp = Time.now.utc.iso8601
        bullets = summary.to_s.lines.map(&:strip).reject(&:empty?).map { |line| "- #{line.delete_prefix("- ").strip}" }
        entry = "\n## Compaction #{stamp}\n#{bullets.join("\n")}\n"
        File.open(path, "a") { |io| io.write(entry) }
        @bus&.publish("compaction:logged", path: path)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "context_window.daily_log", event_bus: @bus)
      end
    end
  end
end