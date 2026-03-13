# frozen_string_literal: true

module Master
  module Stages
    class Route
      def initialize(commands:, agent:)
        @commands = commands
        @agent    = agent
      end

      def call(ctx)
        case ctx[:intent]
        when :command
          cmd = @commands[ctx[:command]]
          return Result.err("unknown command: /#{ctx[:command]}", category: :validation) unless cmd
          Result.ok(ctx.merge(handler: cmd))
        when :llm
          Result.ok(ctx.merge(handler: @agent))
        else
          Result.err("route: unknown intent #{ctx[:intent]}", category: :validation)
        end
      end
    end
  end
end
