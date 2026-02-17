# frozen_string_literal: true

module MASTER
  # ContextWindow - Track and display token usage
  # Uses LLM.context_limits as single source of truth
  module ContextWindow
    DEFAULT_LIMIT = 32_000

    class << self
      def estimate_tokens(char_count)
        (char_count.to_i / 4.0).ceil
      end

      def limit_for(model)
        LLM.context_limits[model] || DEFAULT_LIMIT
      end

      def usage(session, model: nil)
        model ||= LLM.model_tiers[:strong]&.first
        limit = limit_for(model)

        total_chars = session.history.sum { |h| h[:content].to_s.length }
        used = estimate_tokens(total_chars)
        percent = ((used.to_f / limit) * 100).round(1)

        {
          used: used,
          limit: limit,
          percent: percent,
          remaining: limit - used,
        }
      end

      def bar(session, model: nil, width: 20)
        u = usage(session, model: model)
        filled = ((u[:percent] / 100.0) * width).round
        empty = width - filled

        bar_str = "#" * filled + "." * empty
        "#{bar_str} #{u[:percent]}%"
      end

      def status(session, model: nil)
        u = usage(session, model: model)
        "Context: #{format_tokens(u[:used])}/#{format_tokens(u[:limit])} (#{u[:percent]}%)"
      end

      private

      def format_tokens(n)
        MASTER::Utils.format_tokens(n)
      end
    end
  end
end
