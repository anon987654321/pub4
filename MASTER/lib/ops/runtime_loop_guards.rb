# frozen_string_literal: true

module Master
  module Ops
    module RuntimeLoopGuards
      module_function

      # Three long-running loops, each behind its own switch. The guard is one
      # move — alias the real entry point, then refuse to reach it unless the
      # environment asks for the loop — so what separates the three is data:
      # the class, the entry point, and the switch.
      GUARDS = {
        "Master::Fix::Heartbeat" => [:start!, "MASTER_HEARTBEAT"],
        "Master::Fix::Watcher" => [:run_forever, "MASTER_WATCHER"],
        "Master::Fix::WatchLoop" => [:run, "MASTER_WATCH"],
      }.freeze

      def install!
        GUARDS.each { |name, (entry, switch)| guard(name, entry, switch) }
        true
      end

      def guard_subprocess_context!
        if defined?(Falcon) && Fiber.scheduler
          raise Master::SecurityError,
                "Process.fork inside Falcon fibers induces closing scheduler panics. Shell out via Open3 or exe workers."
        end
        true
      end

      def guard(name, entry, switch)
        return unless Object.const_defined?(name)

        klass = Object.const_get(name)
        unguarded = :"#{entry.to_s.delete_suffix("!")}_without_runtime_guard!"
        return if klass.method_defined?(unguarded)

        klass.class_eval do
          alias_method unguarded, entry
          define_method(entry) do |*args, **kwargs, &block|
            return unless ENV[switch] == "1"

            send(unguarded, *args, **kwargs, &block)
          end
        end
      end
    end
  end
end
