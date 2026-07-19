# frozen_string_literal: true

# Mirror EventBus traffic to ActionCable for SSE fallback clients.
Rails.application.config.after_initialize do
  next if defined?(MASTER_CABLE_BRIDGE_STARTED) && MASTER_CABLE_BRIDGE_STARTED

  MASTER_CABLE_BRIDGE_STARTED = true
  Thread.new do
    3.times do
      container = MasterContainerLoader.ensure!
      break if container&.[](:bus)

      sleep 0.5
    end
    bus = MasterContainerLoader.ensure!&.[](:bus)
    next unless bus

    bus.subscribe("*") do |ev|
      type = ev[:event].to_s
      next if type.empty?

      ActionCable.server.broadcast(
        "master:events",
        ev.merge(event: type, type: type)
      )
    rescue StandardError => e
      Rails.logger.debug("cable_bridge: #{e.class}: #{e.message}")
    end
  end
end
