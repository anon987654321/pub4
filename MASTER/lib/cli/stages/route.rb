# frozen_string_literal: true

require_relative "../destructive_routes"

module Master
  module CLI
    module Stages
      # Route — attach the correct handler to the context.
      # :command looks up registered command. :llm uses the agent.
      class Route
        # The two words help lists. A one-letter alias ends the session on a typo
        # of any verb that starts with q.
        EXIT_ALIASES = %w[exit quit].freeze

        def initialize(commands:, agent:, bus: nil)
          @commands = commands
          @agent = agent
          @bus = bus
        end

        def call(ctx)
          case ctx.intent
          when :command then route_command(ctx)
          when :llm then Result.ok(ctx.merge(handler: @agent))
          else Result.err("route: unknown intent #{ctx.intent.inspect}", category: :validation)
          end
        end

        private

        def route_command(ctx)
          return Result.err("bye", category: :shutdown) if EXIT_ALIASES.include?(ctx.command)

          cmd = @commands[ctx.command]
          unless cmd
            suggestion = closest_command(ctx.command)
            error_message = "unknown command: /#{ctx.command}"
            error_message += " -- did you mean /#{suggestion}?" if suggestion
            return Result.err(error_message, category: :validation)
          end
          destructive = DestructiveRoutes.destructive_command?(ctx.command)
          @bus&.publish("route:resolved", command: ctx.command, handler: cmd.class.name, destructive:)
          Result.ok(ctx.merge(handler: cmd, destructive_route: destructive))
        end

        # A Levenshtein matrix rather than DidYouMean::SpellChecker. The two
        # disagree on one-edit typos of the command list: SpellChecker catches
        # transpositions this misses, and misses the first-letter slips and short
        # commands this catches. That is a trade, not a fold.
        def closest_command(name)
          best = @commands.keys.min_by { |k| levenshtein(k, name) }
          return unless best && levenshtein(best, name) <= [name.length, 3].min

          best
        end

        def levenshtein(a, b)
          m = a.length
          n = b.length
          dp = Array.new(m + 1) { Array.new(n + 1, 0) }
          (0..m).each { |i| dp[i][0] = i }
          (0..n).each { |j| dp[0][j] = j }
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
end
