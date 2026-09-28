# frozen_string_literal: true

require_relative "list_dir"

module Master
  module Io
    # Tree is the agent-facing deep listing. ListDir owns the filesystem walk;
    # keeping one implementation prevents the overview tool and the runtime tool
    # from disagreeing about what a directory contains.
    class Tree
      MAX_DEPTH = ListDir::MAX_DEPTH

      def initialize(root:, event_bus: nil)
        @list_dir = ListDir.new(root:, event_bus:)
      end

      def call(path: nil)
        @list_dir.call(path: path || ".", depth: MAX_DEPTH)
      end
    end
  end
end
