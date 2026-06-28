# frozen_string_literal: true

module Master
  module Reach
    # Post-processing pipeline via MASTER/tools/postpro.rb dispatch.
    class Postpro
      def initialize(root:, governor: nil, event_bus: nil)
        @root = root
      end

      def call(args: nil)
        ScriptDispatch.run(root: @root, tool: "postpro", arg: args.to_s)
      end
    end
  end
end
