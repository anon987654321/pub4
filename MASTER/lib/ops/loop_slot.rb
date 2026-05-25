# frozen_string_literal: true

module Master
  module Ops
    module LoopSlot
      LOOP_FLAGS = {
        "autofix" => "MASTER_AUTOFIX",
        "watch" => "MASTER_WATCH",
        "watcher" => "MASTER_WATCHER"
      }.freeze

      module_function

      def enabled
        LOOP_FLAGS.select { |_name, env| ENV[env] == "1" }.keys
      end

      def validate!
        active = enabled
        return true if active.size <= 1

        raise ArgumentError,
              "only one MASTER loop may run at a time; enabled=#{active.join(', ')}. " \
              "Set exactly one of MASTER_AUTOFIX=1, MASTER_WATCH=1, MASTER_WATCHER=1."
      end

      def selected
        enabled.first
      end
    end
  end
end
