# frozen_string_literal: true

module Master
  module Ops
    module RuntimeLoopGuards
      module_function

      def install!
        guard_heartbeat
        guard_watcher
        guard_watch_loop
        true
      end

      def guard_subprocess_context!
        if defined?(Falcon) && Fiber.scheduler
          raise Master::SecurityError,
                "Process.fork inside Falcon fibers induces closing scheduler panics. Shell out via Open3 or exe workers."
        end
        true
      end

      def guard_heartbeat
        return unless defined?(Master::Loop::Heartbeat)

        Master::Loop::Heartbeat.class_eval do
          alias_method :start_without_runtime_guard!, :start!

          def start!
            return unless ENV["MASTER_HEARTBEAT"] == "1"
          end
        end
      end

      def guard_watcher
        return unless defined?(Master::Loop::Watcher)

        Master::Loop::Watcher.class_eval do
          alias_method :run_forever_without_runtime_guard!, :run_forever

          def run_forever
            return unless ENV["MASTER_WATCHER"] == "1"
          end
        end
      end

      def guard_watch_loop
        return unless defined?(Master::Loop::WatchLoop)

        Master::Loop::WatchLoop.class_eval do
          alias_method :run_without_runtime_guard!, :run

          def run(*args, **kwargs, &block)
            return unless ENV["MASTER_WATCH"] == "1"
          end
        end
      end
    end
  end
end
