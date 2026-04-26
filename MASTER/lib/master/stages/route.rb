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
        when :command then route_command(ctx)
        when :llm     then Result.ok(ctx.merge(handler: @agent))
        else               Result.err("route: unknown intent #{ctx[:intent].inspect}", category: :validation)
        end
      end

      private

      def route_command(ctx)
        key = ctx[:command].to_s
        cmd = @commands[key]
        return Result.err("unknown command: /#{ctx[:command].inspect}", category: :validation) unless cmd

        Result.ok(ctx.merge(handler: cmd))
      end
    end
  end
end