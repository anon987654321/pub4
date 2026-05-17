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
        backtrace: Array(error.backtrace).first(5)
      }.merge(metadata)

      if event_bus
        event_bus.publish("swallow:error", payload)
      else
        warn("swallow:error #{payload.inspect}")
      end
      nil
    rescue StandardError => _e; nil
    end
  end
  end
end
