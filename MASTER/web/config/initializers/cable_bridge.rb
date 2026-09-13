# frozen_string_literal: true

# Mirror EventBus traffic to ActionCable for SSE fallback clients.
#
# Everything published on the bus goes out on this channel, unfiltered, and
# that is deliberate rather than an oversight. ActionCable::Connection rejects
# any connection without the operator token (ApplicationCable::Connection), so
# /cable is not reachable by a visitor at all — which is why this carries no
# copy of EventsController's VISITOR_SAFE_PREFIX. The SSE stream needs that
# allow-list because it serves untokened visitors; this does not, and adding
# one here would hide council and fix_loop traffic from the only audience that
# can see it.
#
# A started flag rather than a constant. Assigning a constant inside
# after_initialize warns on every development reload and, worse, makes the
# guard survive a reload that should have re-run the block.
module MasterCableBridge
  @started = false

  class << self
    attr_accessor :started
  end
end

Rails.application.config.after_initialize do
  next if MasterCableBridge.started

  MasterCableBridge.started = true
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
        ev.merge(event: type, type:),
      )
      # warn, not debug. A broadcast that fails is the operator console going
      # quiet, and production runs at info — logging it at debug meant the one
      # symptom anybody would notice had no line in the log explaining it.
    rescue StandardError => e
      Rails.logger.warn("cable_bridge: #{e.class}: #{e.message}")
    end
  end
end
