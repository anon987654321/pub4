# frozen_string_literal: true

# The web tier's logger publishes onto the bus as web:log rather than writing a
# file, so its lines reach Trace::Log and the face with every other event;
# Ground::Swallow's JSONL is the separate record of errors that were caught.
class WebEventLogger
  def initialize(bus)
    @bus = bus
  end

  %i[debug info warn error].each do |level|
    define_method(level) { |message| publish(level, message) }
  end

  private

  def publish(level, message)
    @bus&.publish("web:log", level: level.to_s, message: message.to_s)
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "WebEventLogger.publish", event_bus: @bus)
  end
end
