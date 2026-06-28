# frozen_string_literal: true

module Master
  module Reach
    # Replicate image/video generation via MASTER/tools/repligen.rb dispatch.
    class Repligen
      attr_writer :agent

      def initialize(root:, governor: nil, event_bus: nil, agent: nil)
        @root = root
        @agent = agent
      end

      def call(args: nil, ctx: nil)
        arg = args.to_s
        arg = RepligenArg.refine_generate(arg, agent: @agent, ctx: ctx) if @agent
        ScriptDispatch.run(root: @root, tool: "repligen", arg: arg)
      end
    end
  end
end