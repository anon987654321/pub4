# frozen_string_literal: true

module MASTER
  # ContextWindow - Track and display token usage
  module ContextWindow
    # Rough estimates for different models
    LIMITS = {
      "deepseek/deepseek-r1" => 64_000,
      "anthropic/claude-sonnet-4" => 200_000,
      "deepseek/deepseek-chat" => 64_000,
      "openai/gpt-4.1-mini" => 128_000,
      "openai/gpt-4.1-nano" => 128_000,
    }.freeze

    DEFAULT_LIMIT = 32_000

    class << self
      def estimate_tokens(char_count)
        # Rough estimate: ~4 chars per token for English
        (char_count.to_i / 4.0).ceil
      end

      def limit_for(model)
        LIMITS[model] || DEFAULT_LIMIT
      end

      def usage(session, model: nil)
        model ||= LLM::MODEL_TIERS[:strong]&.first
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

        color = if u[:percent] > 90
                  :red
                elsif u[:percent] > 70
                  :yellow
                else
                  :green
                end

        bar_str = "█" * filled + "░" * empty
        "#{bar_str} #{u[:percent]}%"
      end

      def status(session, model: nil)
        u = usage(session, model: model)
        "Context: #{format_tokens(u[:used])}/#{format_tokens(u[:limit])} (#{u[:percent]}%)"
      end

      private

      def format_tokens(n)
        if n >= 1000
          "#{(n / 1000.0).round(1)}k"
        else
          n.to_s
        end
      end
    end
  end
end
