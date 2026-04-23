# frozen_string_literal: true

# EventsController — SSE stream of EventBus events to the orb visualizer.
#
# The orb already exists (web/app/views/chat/index.html.erb). What it lacked
# was a real signal. This controller subscribes to the container's EventBus,
# serializes each event as Server-Sent Event, and streams them.
#
# Wire into routes:
#   get "/events/stream" => "events#stream"
#
# Consume from the orb JS:
#   const es = new EventSource("/events/stream");
#   es.onmessage = e => handleEvent(JSON.parse(e.data));
#
# Event types the orb can react to (emitted by existing pipeline stages):
#   llm:request           → burst pulse
#   llm:escalation        → color shift
#   tool:used             → ripple
#   scan:complete         → stabilization flash
#   autoloop:cycle        → rotation increment
#   sweep:cycle           → slow rotation
#   pipeline:rollback     → red glitch (from new Pipeline rollback)
class EventsController < ApplicationController
  include ActionController::Live

  POLL_INTERVAL_S = 0.1
  MAX_STREAM_S    = 600   # hard cap — 10 minute stream ceiling

  def stream
    response.headers["Content-Type"]  = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"  # nginx passthrough

    bus      = Master::Container[:bus]
    received = Queue.new
    sub      = bus.subscribe("*") { |type, payload|
      received << { t: Time.now.to_f, type: type, data: payload }
    }
    deadline = Time.now + MAX_STREAM_S

    loop do
      break if Time.now > deadline
      if received.empty?
        response.stream.write(": keepalive\n\n")  # SSE comment, prevents proxy timeout
        sleep POLL_INTERVAL_S
      else
        event = received.pop(true) rescue nil
        next unless event
        response.stream.write("data: #{event.to_json}\n\n")
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client went away — normal. Stop streaming.
  ensure
    bus&.unsubscribe(sub) if sub && bus.respond_to?(:unsubscribe)
    response.stream.close rescue nil
  end
end
