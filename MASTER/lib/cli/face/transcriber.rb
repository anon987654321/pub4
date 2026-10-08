# frozen_string_literal: true

require "open3"
require "tempfile"

module Master
  module CLI
    module Face
      # Words from the ear's 16 kHz mono samples. whisper.cpp on this machine
      # comes first: live words want about one transcription a second, and a
      # free Gemini key allows twenty a day. Gemini answers only where no
      # whisper is installed, and with neither the ear hears nothing rather
      # than guessing.
      #
      # The language stays on auto because the operator speaks Norwegian and
      # English, sometimes in one sentence.
      class Transcriber
        # MASTER_WHISPER_MODEL names the model file; otherwise the first of
        # MODELS found in MODEL_DIR, which is where bin/doctor and the Termux
        # setup look too.
        MODEL_ENV = "MASTER_WHISPER_MODEL"
        MODEL_DIR = File.expand_path("~/.local/share/whisper")
        MODELS = %w[ggml-small.bin ggml-base.bin].freeze
        # Interims are thrown away a second later, so they take the fast model
        # when it sits beside the accurate one: on an M2, base reads 5 s of
        # speech in 1.2 s and small in 3.2 s.
        INTERIM_MODEL = "ggml-base.bin"
        # Smaller than the smallest multilingual model means a download cut short.
        MIN_MODEL_BYTES = 70_000_000
        WHISPER = "whisper-cli"
        RATE_HZ = 16_000
        # whisper names silence and noise in brackets rather than leaving it empty.
        NON_SPEECH = /\[[^\]]*\]|\([^)]*\)/

        def initialize(env: ENV, which: ->(cmd) { Master::Voice::Playback.which(cmd) }, run: Open3.method(:capture3),
                       gemini_key: -> { Talk.gemini_key })
          @env = env
          @which = which
          @run = run
          @gemini_key = gemini_key
        end

        # :whisper, :gemini, or nil when nothing here can transcribe.
        def lane
          return :whisper if model && @which.call(WHISPER)
          return :gemini if @gemini_key.call

          nil
        end

        # The model the final transcript uses, or nil when none is on disk.
        def model
          named = @env[MODEL_ENV].to_s
          return (whole?(named) ? named : nil) unless named.empty?

          MODELS.map { |name| File.join(MODEL_DIR, name) }.find { |path| whole?(path) }
        end

        def interim_model
          fast = File.join(File.dirname(model.to_s), INTERIM_MODEL)
          whole?(fast) ? fast : model
        end

        # One line for bin/doctor and the ear's refusal.
        def describe
          case lane
          when :whisper then "whisper #{File.basename(model)}, interims #{File.basename(interim_model)}"
          when :gemini then "Gemini, twenty requests a day on a free key; install whisper-cpp for live words"
          else "no whisper-cli with a model in #{MODEL_DIR}, and no GEMINI_API_KEY"
          end
        end

        def final(pcm) = words(pcm, model)

        def interim(pcm) = words(pcm, interim_model)

        private

        def words(pcm, path)
          case lane
          when :whisper then whisper(pcm, path)
          when :gemini then gemini(pcm)
          end
        end

        def whisper(pcm, path)
          Tempfile.create(["ear", ".wav"], binmode: true) do |file|
            file.write(wav_bytes(pcm))
            file.flush
            out, _err, status = @run.call(WHISPER, "-m", path, "-f", file.path, "-nt", "-np", "-l", "auto")
            status.success? ? out.gsub(NON_SPEECH, " ").split.join(" ") : nil
          end
        rescue SystemCallError
          nil
        end

        def gemini(pcm)
          require "net/http"
          require "json"
          require "base64"
          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{@gemini_key.call}")
          body = {
            contents: [{ parts: [
              { text: 'Transcribe the speech. Reply as JSON: {"heard":"..."} . Empty heard when there is no speech.' },
              { inline_data: { mime_type: "audio/wav", data: Base64.strict_encode64(wav_bytes(pcm)) } },
            ] }],
            generationConfig: { responseMimeType: "application/json", thinkingConfig: { thinkingBudget: 0 } },
          }
          res = Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
          text = JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text")
          JSON.parse(text.to_s)["heard"].to_s.strip
        rescue StandardError
          nil
        end

        def whole?(path) = File.file?(path) && File.size(path) >= MIN_MODEL_BYTES

        # A 16 kHz mono 16-bit wav around raw samples.
        def wav_bytes(pcm)
          ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE_HZ, RATE_HZ * 2, 2, 16, "data", pcm.bytesize]
            .pack("a4Va4a4VvvVVvva4V") + pcm
        end
      end
    end
  end
end
