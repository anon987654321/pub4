# frozen_string_literal: true

# EventsController — SSE stream of EventBus events to the orb visualizer, at
# GET /events/stream. It subscribes to every bus topic and writes each event
# as an anonymous `data:` line; the orb reads them with
# `new EventSource("/events/stream")` and `onmessage`.
#
# Topics the orb reacts to, each with a publisher in lib/: llm:request,
# llm:escalation, tool:before and tool:after, scan:complete and
# pipeline:rollback. A visitor sees only VISITOR_SAFE_PREFIX, and tts and
# stage events only for their own conversation.
class EventsController < ApplicationController
  include ActionController::Live

  QUEUE_CAP          = 256
  KEEPALIVE_EVERY_S  = 15.0  # SSE comment cadence — long enough to be silent, short enough to keep proxies happy
  MAX_STREAM_S       = 600   # hard cap — 10 minute stream ceiling
  VISITOR_SAFE_PREFIX = %r{\A(?:tts:|pipeline:stage|pressure:updated|council:start|link)}i.freeze

  def stream
    visitor_tier = request.env["master.tier"].to_s == "visitor"

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"  # nginx passthrough
    trace_id = SecureRandom.hex(8)
    response.stream.write(": connected\n\n")
    response.stream.write("event: trace\ndata: #{JSON.generate(trace_id:)}\n\n")

    bus      = container[:bus]
    mine     = conversation_id
    received = SizedQueue.new(QUEUE_CAP)
    sub      = bus.subscribe("*") { |ev| offer(received, ev, visitor_tier:, mine:) }
    deadline       = Time.now + MAX_STREAM_S
    next_keepalive = Time.now + KEEPALIVE_EVERY_S

    while Time.now < deadline
      event = received.pop(timeout: [next_keepalive - Time.now, 0].max)
      if event
        payload = visitor_tier ? visitor_safe_payload(event) : event
        response.stream.write("data: #{payload.to_json}\n\n")
      elsif Time.now >= next_keepalive
        response.stream.write(": keepalive\n\n")  # SSE comment, prevents proxy timeout
        response.stream.write("event: link\ndata: {\"state\":\"quiet\"}\n\n") rescue nil
        next_keepalive = Time.now + KEEPALIVE_EVERY_S
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client went away — normal. Stop streaming.
  ensure
    sub&.call
    response.stream.close rescue nil
  end

  private

  # Runs on the publisher's thread, so it never blocks: the visitor filter
  # applies before the queue, and a full queue drops the event. A slow client
  # loses frames of the orb rather than growing memory on a 1 GB box or
  # stalling whoever published.
  def offer(queue, ev, visitor_tier:, mine:)
    event = { t: Time.now.to_f, type: ev[:event], data: ev }
    return false if visitor_tier && !visitor_safe_event?(event, mine)

    queue.push(event, true)
    true
  rescue ThreadError
    false
  end

  def visitor_safe_event?(event, mine)
    type = event[:type].to_s
    return false unless type.match?(VISITOR_SAFE_PREFIX)
    return true unless type.match?(/\A(?:tts:|pipeline:stage)/i)

    data = event[:data]
    conv = data.is_a?(Hash) ? (data[:conversation] || data["conversation"]) : nil
    conv.present? && conv == mine
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
