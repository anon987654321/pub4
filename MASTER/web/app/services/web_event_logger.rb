# frozen_string_literal: true

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
