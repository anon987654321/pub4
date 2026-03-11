# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master3"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts]

  @@container = nil
  @@mutex     = Mutex.new
  @@start_ms  = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i

  def index
    @model = container[:agent].model.to_s.split("/").last
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
      result = container[:pipeline].call(Master3::Result.ok(user_message: input))
      text = case result
             when Master3::Result::Ok
               val = result.value
               val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
             when Master3::Result::Err
               "ERROR: #{result.message}"
             end

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

    tmp_mp3 = "/tmp/tts_#{SecureRandom.hex(8)}.mp3"
    system("edge-tts",
      "--voice", "ms-MY-OsmanNeural",
      "--rate",  "-35%",
      "--pitch", "-150Hz",
      "--text",  text,
      "--write-media", tmp_mp3)

    if File.exist?(tmp_mp3) && File.size(tmp_mp3) > 0
      send_file tmp_mp3, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  ensure
    File.unlink(tmp_mp3) rescue nil
  end

  private

  def container
    @@mutex.synchronize do
      @@container ||= Master3.build(root: Rails.root.join("..").to_s)
    end
  end
end
