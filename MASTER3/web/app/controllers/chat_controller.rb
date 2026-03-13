# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master3"

class ChatController < ApplicationController
  include ActionController::Live
  skip_before_action :verify_authenticity_token, only: [:message, :tts]

  @@container = nil
  @@mutex     = Mutex.new
  @@start_ms  = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@event_mutex = Mutex.new
  @@event_id = 0
  @@event_text = nil

  def index
    @model = container[:agent].model.to_s.split("/").last
    render file: Rails.root.join("public/cli.html"), layout: false
  end


  # MASTER2-compatible endpoint: queue a reply for SSE consumers.
  def chat
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    text = run_pipeline(input)
    @@event_mutex.synchronize do
      @@event_id += 1
      @@event_text = text
    end

    render json: { ok: true }
  rescue => e
    logger.error "Chat failed: #{e.message}"
    render json: { ok: false, error: e.message }, status: :service_unavailable
  end

  # MASTER2-compatible SSE stream consumed by cli.html EventSource('/sse').
  def sse
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    stream = response.stream
    seen = 0

    begin
      240.times do
        payload = nil
        @@event_mutex.synchronize do
          if @@event_id > seen && @@event_text
            seen = @@event_id
            payload = { text: @@event_text }.to_json
          end
        end

        stream.write("data: #{payload}\n\n") if payload
        sleep 0.25
      end
    rescue IOError, ActionController::Live::ClientDisconnected
      # client disconnected
    ensure
      stream.close
    end
  end

  def dmesg
    lines = `dmesg 2>/dev/null`.lines.first(20).map(&:chomp)
    render json: { lines: lines }
  end

  def metrics
    c = container
    render json: {
      model:  c[:agent].model.to_s.split("/").last,
      tokens: c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:   "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - @@start_ms)
    }
  end

  def message
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    sse = response.stream
    begin
      text = run_pipeline(input)
      text.to_s.split(" ").each do |word|
        sse.write("data: #{word} \n\n")
        sleep 0.03
      end
      sse.write("data: [DONE]\n\n")
    rescue => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      sse.close
    end
  end

  def tts
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    bytes = Master3::Speech.synthesize_bytes(text)
    if bytes && bytes.bytesize > 0
      send_data bytes, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  rescue => e
    logger.error "TTS failed: #{e.message}"
    head :service_unavailable
  end

  private

  def run_pipeline(input)
    result = container[:pipeline].call(Master3::Result.ok(user_message: input))
    case result
    when Master3::Result::Ok
      val = result.value
      val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
    when Master3::Result::Err
      "ERROR: #{result.message}"
    else
      result.to_s
    end
  end

  def container
    @@mutex.synchronize do
      @@container ||= Master3.build(root: Rails.root.join("..").to_s)
    end
  end
end
