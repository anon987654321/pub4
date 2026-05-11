# frozen_string_literal: true

# Live agent-controlled canvas. Spec: data/canvas.yml.
# Reads from EventBus, streams to browser via SSE.
class CanvasController < ApplicationController
  include ActionController::Live

  def show
    @session_id = session[:canvas_id] ||= SecureRandom.hex(8)
    render layout: false
  end

  def stream
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    sse = SSE.new(response.stream, retry: 1500)
    bus = Master::EventBus.instance rescue nil
    sub = bus&.subscribe { |topic, payload| sse.write({topic:, payload:}, event: "bus") }

    keepalive = Thread.new { loop { sleep 15; sse.write({}, event: "ping") rescue break } }
    sleep
  rescue IOError, ActionController::Live::ClientDisconnected
    # client gone
  ensure
    keepalive&.kill
    bus&.unsubscribe(sub) if sub
    sse&.close
  end

  def post_event
    topic   = params.require(:topic)
    payload = params.fetch(:payload, {}).permit!.to_h
    Master::EventBus.instance.publish(topic, **payload.transform_keys(&:to_sym)) rescue nil
    head :accepted
  end

  # canvas/state — closed-loop UI → MASTER. Client posts mood/mode/idle/etc.;
  # bus broadcasts so prompt-builder can include user state context.
  def state
    payload = {
      mood:       params[:mood].to_s,
      mode:       params[:mode].to_s,
      idle_s:     params[:idle].to_i,
      palette:    params[:palette].to_i,
      confidence: params[:confidence].to_f,
      tilt_x:     params[:tilt_x].to_f,
      tilt_y:     params[:tilt_y].to_f
    }
    Master::EventBus.instance.publish(:canvas_state, **payload) rescue nil
    head :accepted
  end

  class SSE
    def initialize(io, retry: nil)
      @io = io
      @io.write("retry: #{binding.local_variable_get(:retry)}\n\n") if binding.local_variable_get(:retry)
    end

    def write(data, event: nil)
      @io.write("event: #{event}\n") if event
      @io.write("data: #{data.to_json}\n\n")
    end

    def close
      @io.close rescue nil
    end
  end
end
