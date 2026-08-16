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
#   pipeline:rollback     → red glitch (from Pipeline rollback)
class EventsController < ApplicationController
  include ActionController::Live

  POLL_INTERVAL_S    = 0.1
  KEEPALIVE_EVERY_S  = 15.0  # SSE comment cadence — long enough to be silent, short enough to keep proxies happy
  MAX_STREAM_S       = 600   # hard cap — 10 minute stream ceiling
  VISITOR_SAFE_PREFIX = %r{\A(?:tts:|pipeline:stage|pressure:updated|council:deliberation|link)}i.freeze

  def stream
    visitor_tier = request.env["master.tier"].to_s == "visitor"

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"  # nginx passthrough
    trace_id = SecureRandom.hex(8)
    response.stream.write(": connected\n\n")
    response.stream.write("event: trace\ndata: #{JSON.generate(trace_id:)}\n\n")

    bus      = container[:bus]
    received = Queue.new
    sub      = bus.subscribe("*") do |ev|
      received << { t: Time.now.to_f, type: ev[:event], data: ev }
    end
    deadline       = Time.now + MAX_STREAM_S
    next_keepalive = Time.now + KEEPALIVE_EVERY_S

    loop do
      break if Time.now > deadline
      if received.empty?
        if Time.now >= next_keepalive
          response.stream.write(": keepalive\n\n")  # SSE comment, prevents proxy timeout
          response.stream.write("event: link\ndata: {\"state\":\"quiet\"}\n\n") rescue nil
          next_keepalive = Time.now + KEEPALIVE_EVERY_S
        end
        sleep POLL_INTERVAL_S
      else
        event = received.pop(true) rescue nil
        next unless event
        next if visitor_tier && !visitor_safe_event?(event)

        payload = visitor_tier ? visitor_safe_payload(event) : event
        response.stream.write("data: #{payload.to_json}\n\n")
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client went away — normal. Stop streaming.
  ensure
    sub&.call
    response.stream.close rescue nil
  end

  private

  def visitor_safe_event?(event)
    type = event[:type].to_s
    type.match?(VISITOR_SAFE_PREFIX)
  end

  # tts:* is on the visitor-safe prefix so the orb can pulse, but the job id
  # is a capability: GET /chat/tts/stream?job= plays the utterance, and
  # DELETE /chat/tts/status?job= cancels it. Strip it from the public SSE.
  def visitor_safe_payload(event)
    data = event[:data]
    return event unless data.is_a?(Hash)

    event.merge(data: data.except(:job_id, "job_id", :conversation, "conversation"))
  end
end
