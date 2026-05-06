# frozen_string_literal: true

module Master
  module Stages
    # Route — attach the correct handler to the context.
    # :command looks up registered command. :llm uses the agent.
    class Route
      def initialize(commands:, agent:)
        @commands = commands
        @agent    = agent
      end

      def add_command(name, handler) = @commands[name.to_s] = handler

      def call(ctx)
        case ctx[:intent]
        when :command  then route_command(ctx)
        when :llm      then Result.ok(ctx.merge(handler: @agent))
        when :clarify  then Result.ok(ctx.merge(handler: ->(_c) { ctx[:clarifying_question] }))
        else                Result.err("route: unknown intent #{ctx[:intent].inspect}", category: :validation)
        end
      end

      private

      def route_command(ctx)
        cmd = @commands[ctx[:command]]
        unless cmd
          suggestion = closest_command(ctx[:command])
          msg = "unknown command: /#{ctx[:command]}"
          msg += " -- did you mean /#{suggestion}?" if suggestion
          return Result.err(msg, category: :validation)
        end
        Result.ok(ctx.merge(handler: cmd))
      end

      def closest_command(name)
        best = @commands.keys.min_by { |k| levenshtein(k, name) }
        return unless best && levenshtein(best, name) <= [name.length, 3].min

        best
      end

      def levenshtein(a, b)
        m = a.length
        n = b.length
        dp = Array.new(m + 1) { |i| Array.new(n + 1) { |j| i.zero? ? j : (j.zero? ? i : 0) } }
        (1..m).each do |i|
          (1..n).each do |j|
            dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].min
          end
        end
        dp[m][n]
      end
    end
  end
end
