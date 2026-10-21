# frozen_string_literal: true

require "tmpdir"
require "securerandom"
require "fileutils"
require_relative "../../io/exec"

module Master
  module Voice
    class Stt
      # Batch STT via whisper.cpp CLI after the utterance ends.
      # Soft-loads when binary + model exist. Not streaming — feed() buffers only.
      class WhisperCppBackend
        def self.try_load(config = {})
          bin = binary_path(config)
          model = model_path(config)
          return nil unless bin && model

          new(binary: bin, model: model, config: config)
        rescue StandardError
          nil
        end

        def self.binary_path(config = {})
          candidates = [
            ENV["MASTER_WHISPER_BINARY"].to_s,
            config[:whisper_binary].to_s,
            "whisper-cli",
            "whisper-cpp",
            "main", # older whisper.cpp binary name
          ].reject(&:empty?)
          candidates.each do |c|
            return c if c.include?("/") && File.executable?(c)

            path = which(c)
            return path if path
          end
          nil
        end

        def self.model_path(config = {})
          env = ENV["MASTER_WHISPER_MODEL"].to_s
          return env if !env.empty? && File.file?(env)

          configured = config[:whisper_model_path].to_s
          return configured if !configured.empty? && File.file?(configured)

          candidates = [
            File.expand_path("../../../../vendor/whisper/ggml-base.en.bin", __dir__),
            File.expand_path("~/.local/share/master/ggml-base.en.bin", __dir__),
          ]
          candidates.find { |p| File.file?(p) }
        end

        def self.which(cmd)
          exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
          ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
            exts.each do |ext|
              path = File.join(dir, "#{cmd}#{ext}")
              return path if File.executable?(path) && !File.directory?(path)
            end
          end
          nil
        end

        def initialize(binary:, model:, config: {})
          @binary = binary
          @model = model
          @sample_rate = (config[:sample_rate] || Stt::SAMPLE_RATE).to_i
          @timeout_s = (config[:whisper_timeout_s] || 60).to_i
          @language = (config[:language] || "en").to_s
        end

        def name = :whisper_cpp

        def start_utterance; end

        def feed(_floats) = nil

        def finish(floats)
          return ["", nil, nil] if floats.nil? || floats.empty?

          wav = write_wav(floats)
          text, raw = run_whisper(wav)
          [text, nil, raw]
        ensure
          FileUtils.rm_f(wav) if wav
        end

        def reset!; end

        private

        def write_wav(floats)
          path = File.join(Dir.tmpdir, "master-stt-#{Process.pid}-#{SecureRandom.hex(4)}.wav")
          pcm = floats.map { |f| (f * 32_767).round.clamp(-32_768, 32_767) }
          data = pcm.pack("s<*")
          # Minimal PCM16 mono WAV header
          byte_rate = @sample_rate * 2
          header = [
            "RIFF",
            [36 + data.bytesize].pack("V"),
            "WAVE",
            "fmt ",
            [16].pack("V"),
            [1].pack("v"), # PCM
            [1].pack("v"), # mono
            [@sample_rate].pack("V"),
            [byte_rate].pack("V"),
            [2].pack("v"), # block align
            [16].pack("v"), # bits
            "data",
            [data.bytesize].pack("V"),
          ].join
          File.binwrite(path, header + data)
          path
        end

        def run_whisper(wav_path)
          # Common whisper.cpp CLI flags (whisper-cli / main)
          cmd = [
            @binary,
            "-m", @model,
            "-f", wav_path,
            "-l", @language,
            "-nt", # no timestamps in stdout
            "-np", # no prints progress noise when supported
          ]
          out, err, status = Master::Io::Exec.capture3(
            *cmd, timeout: @timeout_s, raise_on_timeout: true
          )
          text = out.to_s.gsub(/\[.*?\]/, "").lines.map(&:strip).reject(&:empty?).join(" ").strip
          [text, { stdout: out, stderr: err, status: status&.exitstatus }]
        rescue StandardError => e
          ["", { error: e.message }]
        end
      end
    end
  end
end
