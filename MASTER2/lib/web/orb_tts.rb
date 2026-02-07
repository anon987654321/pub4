# frozen_string_literal: true

require "json"

module MASTER
  module Web
    # OrbTTS: SSE streaming TTS for web UI orbs
    class OrbTTS
      ENGINES = %i[piper edge replicate].freeze

      VOICES = {
        piper: "en_US-lessac-medium",
        edge: "en-US-AriaNeural",
        replicate: "Casual_Guy",
      }.freeze

      class << self
        # Generate SSE stream of audio chunks
        def stream(text, engine: :auto, voice: nil, style: nil)
          engine = select_engine if engine == :auto
          voice ||= VOICES[engine]

          Enumerator.new do |yielder|
            yielder << sse_event("start", { engine: engine, voice: voice })

            chunks = smart_chunk(text, 150)
            chunks.each_with_index do |chunk, i|
              audio = generate_chunk(chunk, engine: engine, voice: voice, style: style)

              if audio
                yielder << sse_event("audio", {
                  index: i,
                  total: chunks.size,
                  data: audio,
                  text: chunk,
                })
              else
                yielder << sse_event("error", { index: i, message: "Generation failed" })
              end
            end

            yielder << sse_event("done", { chunks: chunks.size })
          end
        end

        # Single audio generation (returns base64 data URL)
        def generate(text, engine: :auto, voice: nil, style: nil)
          engine = select_engine if engine == :auto
          voice ||= VOICES[engine]
          generate_chunk(text, engine: engine, voice: voice, style: style)
        end

        # Rack middleware for SSE endpoint
        def rack_app
          lambda do |env|
            request = Rack::Request.new(env)
            text = request.params["text"] || request.params["t"]
            engine = (request.params["engine"] || "auto").to_sym
            voice = request.params["voice"]
            style = request.params["style"]&.to_sym

            return [400, {}, ["Missing text parameter"]] unless text

            headers = {
              "Content-Type" => "text/event-stream",
              "Cache-Control" => "no-cache",
              "Connection" => "keep-alive",
              "X-Accel-Buffering" => "no",
            }

            body = stream(text, engine: engine, voice: voice, style: style)
            [200, headers, body]
          end
        end

        private

        def select_engine
          return :piper if piper_available?
          return :edge if edge_available?
          return :replicate if replicate_available?
          :edge
        end

        def piper_available?
          defined?(MASTER::PiperTTS) && PiperTTS.available?
        rescue StandardError
          false
        end

        def edge_available?
          defined?(MASTER::EdgeTTS) && EdgeTTS.installed?
        end

        def replicate_available?
          ENV["REPLICATE_API_TOKEN"] && !ENV["REPLICATE_API_TOKEN"].empty?
        end

        def generate_chunk(text, engine:, voice:, style:)
          case engine
          when :piper
            PiperTTS.new.generate_base64(text, preset: style)
          when :edge
            EdgeTTS.generate_base64(text, voice: voice&.to_sym || :aria, style: style || :normal)
          when :replicate
            tts = TTS.new
            # Would need to implement generate_base64 for TTS class
            nil
          else
            nil
          end
        rescue StandardError
          nil
        end

        def smart_chunk(text, max_chars)
          sentences = text.split(/(?<=[.!?])\s+/)
          chunks = []
          current = ""

          sentences.each do |s|
            if (current.length + s.length) > max_chars
              chunks << current.strip unless current.empty?
              current = s
            else
              current = current.empty? ? s : "#{current} #{s}"
            end
          end
          chunks << current.strip unless current.empty?
          chunks.reject(&:empty?)
        end

        def sse_event(event, data)
          "event: #{event}\ndata: #{data.to_json}\n\n"
        end
      end
    end
  end
end
