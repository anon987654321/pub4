# frozen_string_literal: true

module Master
  module Ground
  # Central helper for intentional rescue-and-continue sites.
  # Keeps tolerated failures visible, greppable, and event-bus observable.
    module Swallow
      module_function

      def log(error, context:, event_bus: nil, **metadata)
        payload = {
          context: context.to_s,
          error_class: error.class.name,
          error: error.message.to_s,
          backtrace: Array(error.backtrace).first(5),
        }.merge(metadata)

        if event_bus
          event_bus.publish("swallow:error", payload)
        else
          warn("swallow:error #{payload.inspect}")
        end
        nil
      rescue StandardError => e
        # Last resort: the logger itself failed. Cannot use the bus or recurse
        # into Swallow — write straight to stderr so the failure is not lost.
        Kernel.warn("swallow:meta_error #{e.class}: #{e.message}")
        nil
      end

      def safe_call(context:, event_bus: nil, **meta)
        yield
      rescue StandardError => e
        log(e, context: context, event_bus: event_bus, **meta)
        nil
      end
    end
  end
end
