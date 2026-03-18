# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts]

  @@container = nil
  @@mutex     = Mutex.new
  @@start_ms  = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i

  def index
    @model = container[:agent].model.to_s.split("/").last
    render layout: false
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
      streamed = false
      on_chunk = ->(token) {
        streamed = true
        sse.write("data: #{token.to_s.gsub("\n", " ")}\n\n")
      }

      result = container[:pipeline].call(
        Master::Result.ok(user_message: input, on_chunk: on_chunk)
      )

      # Commands / cache hits didn't stream — send full text as one event
      unless streamed
        text = case result
               when Master::Result::Ok
                 val = result.value
                 val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
               when Master::Result::Err
                 "ERROR: #{result.message}"
               end
        sse.write("data: #{text.to_s.gsub("\n", " ")}\n\n") unless text.to_s.strip.empty?
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

    bytes = Master::Speech.synthesize_bytes(text)
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

  def container
    @@mutex.synchronize do
      @@container ||= Master.build(root: Rails.root.join("..").to_s)
    end
  end
end
