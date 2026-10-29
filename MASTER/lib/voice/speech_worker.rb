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
      def synthesize_edge_oneshot(text:, voice_name:, style_config:, audio_path:, timeout: nil)
        timeout ||= worker_timeout(text.to_s.length)
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
        missing = []
        missing << "voice" if voice_name.to_s.strip.empty?
        missing << "rate" if style_config[:rate].to_s.strip.empty?
        missing << "pitch" if style_config[:pitch].to_s.strip.empty?
        missing << "output_path" if audio_path.to_s.strip.empty?
        raise ArgumentError, "edge worker inputs missing: #{missing.join(", ")}" unless missing.empty?

        # Delegate the timeout to Exec.capture3, which spawns in its own process
        # group and TERM/KILLs it on expiry. A previous outer Timeout.timeout
        # here fired first and bypassed that kill, orphaning a hung tts-worker
        # (and a retry then spawned a duplicate on the same output file).
        _out, err, status = Master::Io::Exec.capture3(
          TtsSupervisor.daemon_env(Master::ROOT),
          RbConfig.ruby, Speech::WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
          stdin_data: text.to_s,
          chdir: Master::ROOT,
          timeout:
        )
        [err, status]
      end

      def synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:, on_chunk: nil, retried: false)
        sock_path = resolve_socket_path
        unless sock_path
          warn_tts("edge socket unavailable after worker retry") if retried
          return
        end

        req = build_socket_request(voice_name, style_config, text)
        timeout = stream_timeout(text.to_s.length)
        stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        # Say so only when the retry on the next worker has failed too; the first miss is handled.
        warn_tts("edge socket produced empty audio") if retried
        cleanup_failed_audio(audio_path)
        # A worker can answer its health ping and still synthesise nothing; it then wins
        # every other round-robin turn, and each of its turns fell through to the older
        # voices. Retire it and ask the next worker once before giving up.
        TtsSupervisor.retire_socket(sock_path)
        return if retried

        synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:, on_chunk:, retried: true)
      rescue Timeout::Error
        warn_tts("edge socket timed out after #{timeout}s")
        cleanup_failed_audio(audio_path)
        TtsSupervisor.retire_socket(sock_path) if sock_path
      rescue StandardError => e
        warn_tts("edge socket failed: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
        TtsSupervisor.retire_socket(sock_path) if sock_path
      end

      def build_socket_request(voice_name, style_config, text)
        JSON.generate(
          voice: voice_name,
          rate: style_config[:rate],
          pitch: style_config[:pitch],
          text: text.to_s,
          stream: stream_wire_enabled?,
        )
      end

      def resolve_socket_path
        sock_path = TtsSupervisor.next_socket
        return unless sock_path
        return sock_path if File.socket?(sock_path)

        TtsSupervisor.ensure_daemon!
        sock_path = TtsSupervisor.next_socket
        File.socket?(sock_path) ? sock_path : nil
      end

      # Wire v2: 8-byte length-prefixed audio chunks, zero-length frame = clean
      # end. EOF without the zero frame means the daemon truncated mid-synthesis;
      # discard those bytes so the caller falls back to whole-file synthesis
      # instead of speaking a severed sentence. A legacy daemon ignores "stream"
      # and answers with raw mp3, which looks like an absurd frame header —
      # detect that form and consume the response as raw.
      FRAME_HEADER_S = 8
      FRAME_MAX_S = 1 << 23 # 8 MiB; an Edge chunk is kilobytes

      # One framed edge response, whatever consumes it — a temp file for the
      # whole-file path, a player's stdin for live playback. on_chunk fires
      # per frame with the bytes written so far; stale_test is checked between
      # frames so an interrupted reply stops pulling audio off the wire.
      StreamResult = Data.define(:ok, :bytes)

      StreamTarget = Data.define(:io, :on_chunk, :stale_test) do
        # Data fields init as keywords, so the sinks that only observe or only
        # test staleness pass nil for the rest through here instead.
        def self.build(io:, on_chunk: nil, stale_test: nil)
          new(io:, on_chunk:, stale_test:)
        end
      end

      def stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        Timeout.timeout(timeout) do
          UNIXSocket.open(sock_path) do |s|
            s.write("#{req}\n")
            File.open(audio_path, "wb") do |f|
              result = pump_socket_stream(s, StreamTarget.build(io: f, on_chunk:))
              File.unlink(audio_path) rescue nil unless result.ok
              result
            end
          end
        end
      end

      def stream_socket_to_io(sock_path, req, timeout, target)
        Timeout.timeout(timeout) do
          UNIXSocket.open(sock_path) do |s|
            s.write("#{req}\n")
            pump_socket_stream(s, target)
          end
        end
      end

      # Live playback facade: one utterance into io, framed and chunk-clocked.
      # Returns StreamResult so playback can distinguish a clean stream from a
      # failed stream that already emitted audio.
      def stream_edge_to_io(text:, voice_name:, style_config:, io:, stale_test: nil)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        first_chunk = false
        written_bytes = 0
        sock_path = resolve_socket_path
        return StreamResult.new(ok: false, bytes: 0) unless sock_path

        req = build_socket_request(voice_name, style_config, text)
        progress = lambda do |written|
          written_bytes = [written_bytes, written.to_i].max
          next if first_chunk

          log_timing("first_audio_chunk", started_at, text_length: text.to_s.length)
          first_chunk = true
        end
        target = StreamTarget.build(io:, on_chunk: progress, stale_test:)
        result = stream_socket_to_io(sock_path, req, stream_timeout(text.to_s.length), target)
        bytes = [result.bytes.to_i, written_bytes].max
        return StreamResult.new(ok: true, bytes:) if result.ok && bytes.positive?

        # A failed or empty stream retires its worker. Keep bytes already sent to
        # the player: playback must never restart a sentence that may be audible.
        TtsSupervisor.retire_socket(sock_path)
        StreamResult.new(ok: false, bytes:)
      rescue Timeout::Error, StandardError => e
        warn_tts("edge stream error: #{e.class}: #{e.message}")
        TtsSupervisor.retire_socket(sock_path) if sock_path
        StreamResult.new(ok: false, bytes: written_bytes.to_i)
      ensure
        log_timing("live_stream_total", started_at, text_length: text.to_s.length) if started_at
      end

      # Wire v2 ("stream":true) is the default; MASTER_TTS_WIRE=raw restores
      # the v1 contract save_sync-and-copy against a daemon that predates it.
      def stream_wire_enabled?
        ENV.fetch("MASTER_TTS_WIRE", "stream") != "raw"
      end

      def pump_socket_stream(sock, target)
        sink = target.io
        written = 0
        loop do
          frame = read_frame(sock, target)
          return StreamResult.new(ok: false, bytes: written) if frame == :eof
          return StreamResult.new(ok: true, bytes: written) if frame == :clean

          if frame.is_a?(Array) && frame.first == :raw
            written += frame.last.to_i
            target.on_chunk&.call(written)
            return StreamResult.new(ok: true, bytes: written)
          end

          sink.write(frame[1])
          written += frame[1].bytesize
          target.on_chunk&.call(written)
          return StreamResult.new(ok: false, bytes: written) if target.stale_test&.call
        end
      rescue Errno::EPIPE, Errno::ENOTCONN, Errno::ECONNRESET
        StreamResult.new(ok: false, bytes: written)
      end

      # The next frame from the wire: an integer-length body for the common
      # audio case, :clean for the zero terminator, :eof when the daemon hung
      # up without one (a truncated stream), :raw when the bytes form a legacy
      # daemon's whole-file answer — consume_raw_response has already
      # forwarded them untouched.
      def read_frame(sock, target)
        header = read_socket_fill(sock, FRAME_HEADER_S)
        return :eof unless header

        size = header.unpack1("Q>")
        return :clean if size.zero?
        return consume_raw_response(header, sock, target) if size > FRAME_MAX_S

        body = read_socket_fill(sock, size)
        return :eof unless body

        [:audio, body]
      end

      # A legacy daemon ignores "stream" and answers with raw mp3 — the length
      # prefix misreads as an absurd header. Forward in chunks so timeouts still
      # preserve the byte count and never replay an already-heard sentence.
      def consume_raw_response(header, sock, target)
        sink = target.io
        written = sink.write(header)
        target.on_chunk&.call(written)
        loop do
          chunk = sock.readpartial(16 * 1024)
          written += sink.write(chunk)
          target.on_chunk&.call(written)
        end
      rescue EOFError
        [:raw, written]
      end

      def read_socket_fill(sock, want)
        buf = +"".b
        while buf.bytesize < want
          buf << sock.readpartial(want - buf.bytesize)
        end
        buf
      rescue EOFError
        buf.empty? ? nil : buf
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
        audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.m4a"
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

      FAST_WORKER_TIMEOUT_S = Integer(ENV.fetch("MASTER_TTS_FAST_TIMEOUT", "4"))
      FAST_WORKER_TIMEOUT_MAX = Integer(ENV.fetch("MASTER_TTS_FAST_TIMEOUT_MAX", "6"))

      def worker_timeout(text_length = 0)
        return Integer(ENV.fetch("MASTER_TTS_TIMEOUT")) if ENV.key?("MASTER_TTS_TIMEOUT")

        if respond_to?(:fast_tts_mode?) && fast_tts_mode?
          return [FAST_WORKER_TIMEOUT_S + (text_length * 0.01).ceil, FAST_WORKER_TIMEOUT_MAX].min
        end

        normal_worker_timeout(text_length)
      rescue ArgumentError
        Speech::WORKER_TIMEOUT
      end

      # One-shot retry follows the ordinary worker budget even when the warm
      # socket policy is fast. Its caller supplies a smaller explicit ceiling
      # for recovery, so this never makes ordinary speech less bounded.
      def normal_worker_timeout(text_length = 0)
        [Speech::WORKER_TIMEOUT + (text_length * Speech::WORKER_TIMEOUT_PER_CHAR).ceil, Speech::WORKER_TIMEOUT_MAX].min
      end

      # A socket timeout covers the whole utterance, unlike the one-shot worker
      # deadline. Give streamed speech a length-aware budget so fast mode cannot
      # cut a normal sentence off at the six-second worker cap.
      FAST_STREAM_TIMEOUT_S = Integer(ENV.fetch("MASTER_TTS_FAST_STREAM_TIMEOUT", "12"))
      FAST_STREAM_TIMEOUT_PER_CHAR = Float(ENV.fetch("MASTER_TTS_FAST_STREAM_TIMEOUT_PER_CHAR", "0.08"))
      FAST_STREAM_TIMEOUT_MAX = Integer(ENV.fetch("MASTER_TTS_FAST_STREAM_TIMEOUT_MAX", "90"))

      def stream_timeout(text_length = 0)
        return Integer(ENV.fetch("MASTER_TTS_STREAM_TIMEOUT")) if ENV.key?("MASTER_TTS_STREAM_TIMEOUT")
        return worker_timeout(text_length) unless respond_to?(:fast_tts_mode?) && fast_tts_mode?

        [FAST_STREAM_TIMEOUT_S + (text_length * FAST_STREAM_TIMEOUT_PER_CHAR).ceil, FAST_STREAM_TIMEOUT_MAX].min
      rescue ArgumentError, TypeError
        worker_timeout(text_length)
      end
    end
  end
end
