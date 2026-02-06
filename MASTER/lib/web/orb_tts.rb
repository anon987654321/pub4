# frozen_string_literal: true

# OrbTTS: SSE streaming TTS for web UI orbs
# Streams audio chunks to browser via Server-Sent Events
# Works with HTMX hx-sse or vanilla EventSource

module MASTER
  module Web
    class OrbTTS
      # TTS engine priority: local first, then free cloud, then paid
      ENGINES = %i[piper edge kokoro minimax].freeze

      # Default voices per engine
      VOICES = {
        piper:   'en_US-lessac-medium',
        edge:    'en-US-AriaNeural',
        kokoro:  'af_bella',
        minimax: 'Casual_Guy'
      }.freeze

      class << self
        # Generate SSE stream of audio chunks
        # Returns Enumerator for Rack streaming response
        def stream(text, engine: :auto, voice: nil, preset: nil)
          engine = select_engine if engine == :auto
          voice ||= VOICES[engine]

          Enumerator.new do |yielder|
            yielder << sse_event('start', { engine: engine, voice: voice })

            chunks = smart_chunk(text, 150)
            chunks.each_with_index do |chunk, i|
              audio = generate_chunk(chunk, engine: engine, voice: voice, preset: preset)
              
              if audio
                yielder << sse_event('audio', {
                  index: i,
                  total: chunks.size,
                  data: audio,
                  text: chunk
                })
              else
                yielder << sse_event('error', { index: i, message: 'Generation failed' })
              end
            end

            yielder << sse_event('done', { chunks: chunks.size })
          end
        end

        # Single audio generation (returns base64 data URL)
        def generate(text, engine: :auto, voice: nil, preset: nil)
          engine = select_engine if engine == :auto
          voice ||= VOICES[engine]
          generate_chunk(text, engine: engine, voice: voice, preset: preset)
        end

        # Rack middleware for SSE endpoint
        # Mount at /tts/stream in Rails/Sinatra
        def rack_app
          lambda do |env|
            request = Rack::Request.new(env)
            text = request.params['text'] || request.params['t']
            engine = (request.params['engine'] || 'auto').to_sym
            voice = request.params['voice']
            preset = request.params['preset']&.to_sym

            return [400, {}, ['Missing text parameter']] unless text

            headers = {
              'Content-Type' => 'text/event-stream',
              'Cache-Control' => 'no-cache',
              'Connection' => 'keep-alive',
              'X-Accel-Buffering' => 'no'  # Disable nginx buffering
            }

            body = stream(text, engine: engine, voice: voice, preset: preset)
            [200, headers, body]
          end
        end

        private

        def select_engine
          # Priority: local Piper > free edge-tts > paid Replicate
          return :piper if piper_available?
          return :edge if edge_available?
          return :kokoro if replicate_available?
          :minimax
        end

        def piper_available?
          defined?(MASTER::PiperTTS) && 
            File.exist?(File.join(MASTER::Paths.var, 'piper_voices', 'en_US-lessac-medium.onnx'))
        end

        def edge_available?
          defined?(MASTER::EdgeTTS) && MASTER::EdgeTTS.installed?
        end

        def replicate_available?
          ENV['REPLICATE_API_TOKEN'] && !ENV['REPLICATE_API_TOKEN'].empty?
        end

        def generate_chunk(text, engine:, voice:, preset:)
          case engine
          when :piper
            MASTER::PiperTTS.new.generate_base64(text, preset: preset)
          when :edge
            MASTER::EdgeTTS.generate_base64(text, voice: voice.to_sym)
          when :kokoro
            file = MASTER::Replicate.speak_kokoro(text, voice: voice)
            file_to_base64(file, 'audio/wav')
          when :minimax
            file = MASTER::Replicate.speak_turbo(text, voice: voice)
            file_to_base64(file, 'audio/mp3')
          else
            nil
          end
        rescue => e
          nil
        end

        def file_to_base64(path, mime)
          return nil unless path && File.exist?(path.to_s)
          require 'base64'
          data = Base64.strict_encode64(File.binread(path))
          "data:#{mime};base64,#{data}"
        end

        def smart_chunk(text, max_chars)
          sentences = text.split(/(?<=[.!?])\s+/)
          chunks = []
          current = ''

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

# JavaScript client for browser:
# 
# const orb = document.getElementById('orb');
# const es = new EventSource('/tts/stream?text=' + encodeURIComponent(text));
# const audioQueue = [];
# let playing = false;
# 
# es.addEventListener('audio', (e) => {
#   const { data, text, index, total } = JSON.parse(e.data);
#   audioQueue.push(data);
#   orb.classList.add('speaking');
#   playNext();
# });
# 
# es.addEventListener('done', () => es.close());
# 
# function playNext() {
#   if (playing || !audioQueue.length) return;
#   playing = true;
#   const audio = new Audio(audioQueue.shift());
#   audio.onended = () => { playing = false; playNext(); };
#   audio.play();
# }
