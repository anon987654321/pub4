# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"
require "timeout"

module Master
  module Voice
    # The subprocess and socket half of Speech: the Edge worker over its Unix
    # socket or as a one-shot process, espeak and say, and the timeout they
    # share. Speech extends this, so every method runs with Speech as self and
    # keeps its name there (Speech.synthesize_edge_socket, Speech.worker_timeout);
    # what to say, in which voice and style, stays in speech.rb.
    module SpeechWorker
      def synthesize_edge_oneshot(text:, voice_name:, style_config:, audio_path:)
        timeout = worker_timeout(text.to_s.length)
        err, status = run_edge_worker(text, voice_name, style_config, audio_path, timeout)
        unless status.success?
          warn_tts("edge worker failed: #{err.to_s.strip}") unless err.to_s.strip.empty?
          return cleanup_failed_audio(audio_path)
        end

        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge worker produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge worker timed out after #{timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge worker error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def run_edge_worker(text, voice_name, style_config, audio_path, timeout)
        # Delegate the timeout to Exec.capture3, which spawns in its own process
        # group and TERM/KILLs it on expiry. A previous outer Timeout.timeout
        # here fired first and bypassed that kill, orphaning a hung tts-worker
        # (and a retry then spawned a duplicate on the same output file).
        _out, err, status = Master::Io::Exec.capture3(
          TtsSupervisor.daemon_env(Master::ROOT),
          Gem.ruby, Speech::WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
          stdin_data: text.to_s,
          chdir: Master::ROOT,
          timeout:
        )
        [err, status]
      end

      def synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:, on_chunk: nil)
        sock_path = resolve_socket_path
        return unless sock_path

        req = build_socket_request(voice_name, style_config, text)
        timeout = worker_timeout(text.to_s.length)
        stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge socket produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge socket timed out after #{timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge socket failed: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def build_socket_request(voice_name, style_config, text)
        JSON.generate(
          voice: voice_name,
          rate: style_config[:rate],
          pitch: style_config[:pitch],
          text: text.to_s,
        )
      end

      def resolve_socket_path
        sock_path = TtsSupervisor.next_socket
        unless File.socket?(sock_path)
          TtsSupervisor.ensure_daemon!
          sock_path = TtsSupervisor.next_socket
        end
        File.socket?(sock_path) ? sock_path : nil
      end

      def stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        Timeout.timeout(timeout) do
          UNIXSocket.open(sock_path) do |s|
            s.write("#{req}\n")
            File.open(audio_path, "wb") do |f|
              loop do
                begin
                  chunk = s.readpartial(8192)
                rescue EOFError
                  break
                end
                f.write(chunk)
                on_chunk&.call(f.pos)
              end
            end
          end
        end
      end

      def synthesize_espeak(text)
        audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
        ok = system(
          espeak_path, "-s", "162", "-p", "42", "-a", "125",
          "-w", audio_path, text.to_s,
          out: File::NULL, err: File::NULL
        )
        return audio_path if ok && File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("espeak failed or produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("espeak error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      # Classic path used to die after espeak. Engines.synth_say is the Mac
      # fallback Transcendent already had, and a workstation without Edge or
      # espeak was silent for no reason of its own.
      def synthesize_say(text)
        audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
        return audio_path if Engines.synth_say(text, audio_path) && File.size?(audio_path)

        warn_tts("say failed or produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("say error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def cleanup_failed_audio(path)
        File.unlink(path) rescue nil if path
        nil
      end

      def worker_timeout(text_length = 0)
        return Integer(ENV.fetch("MASTER_TTS_TIMEOUT")) if ENV.key?("MASTER_TTS_TIMEOUT")

        [Speech::WORKER_TIMEOUT + (text_length * Speech::WORKER_TIMEOUT_PER_CHAR).ceil, Speech::WORKER_TIMEOUT_MAX].min
      rescue ArgumentError
        Speech::WORKER_TIMEOUT
      end
    end
  end
end
