# frozen_string_literal: true

require 'json'
require 'fileutils'

module MASTER
  module Audio
    OUTPUT_DIR = File.join(MASTER::ROOT, 'var', 'audio')
    VOICE = 'Casual_Guy'
    WORDS_PER_CHUNK = 22
    WORDS_PER_MINUTE = 150

    class << self
      # Main entry: generate and play/stream text
      def say(text, voice: VOICE, chunk_words: WORDS_PER_CHUNK)
        files = generate_chunks(text, voice: voice, chunk_words: chunk_words)
        play(files)
        cleanup(files)
        files.size
      end

      # Generate audio chunks from text
      def generate_chunks(text, voice: VOICE, chunk_words: WORDS_PER_CHUNK)
        FileUtils.mkdir_p(OUTPUT_DIR)
        chunks = smart_chunk(text, chunk_words)
        files = []

        chunks.each_with_index do |chunk, i|
          result = Replicate.speak_turbo(chunk.strip, voice: voice)
          files << result if result && File.exist?(result.to_s)
        end

        files
      end

      # Estimate duration in ms from word count
      def estimate_duration_ms(text)
        words = text.split.size
        (words.to_f / WORDS_PER_MINUTE * 60 * 1000).round
      end

      # Smart chunking at natural boundaries
      def smart_chunk(text, target_words)
        words = text.split
        chunks = []
        current = []

        words.each do |word|
          current << word
          if current.size >= target_words ||
             word.match?(/[.!?;]$/) ||
             (current.size >= target_words / 2 && word.match?(/[,:]$/))
            chunks << current.join(' ')
            current = []
          end
        end

        chunks << current.join(' ') unless current.empty?
        chunks.reject(&:empty?)
      end

      # Play audio files (platform-specific)
      def play(files)
        case platform
        when :cygwin, :windows
          play_windows(files)
        when :macos
          play_macos(files)
        when :openbsd, :linux
          play_unix(files)
        else
          broadcast_websocket(files)
        end
      end

      # Cygwin/Windows: PowerShell MediaPlayer
      def play_windows(files)
        return if files.empty?

        script = <<~PS
          Add-Type -AssemblyName PresentationCore
          $p = New-Object System.Windows.Media.MediaPlayer
          $files = @(#{files.map { |f| "'#{f.gsub('/', '\\\\')}'" }.join(', ')})
          foreach ($f in $files) {
            $p.Open([Uri]$f)
            Start-Sleep -Milliseconds 200
            $d = $p.NaturalDuration.TimeSpan.TotalMilliseconds
            if ($d -lt 1000) { $d = 8000 }
            $p.Play()
            Start-Sleep -Milliseconds ($d + 500)
          }
        PS
        system("powershell", "-Command", script)
      end

      # macOS: afplay
      def play_macos(files)
        files.each { |f| system("afplay", f) }
      end

      # Unix/OpenBSD: mpv or ffplay
      def play_unix(files)
        player = %w[mpv ffplay aplay].find { |p| system("which #{p} > /dev/null 2>&1") }
        return broadcast_websocket(files) unless player

        case player
        when 'mpv'
          files.each { |f| system("mpv", "--no-video", "--really-quiet", f) }
        when 'ffplay'
          files.each { |f| system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", f) }
        end
      end

      # WebSocket broadcast for web UI (OpenBSD server)
      def broadcast_websocket(files)
        return unless defined?(MASTER::Server) && MASTER::Server.running?

        files.each do |file|
          # Convert to base64 for web transport
          data = File.binread(file)
          encoded = Base64.strict_encode64(data)
          duration_ms = estimate_duration_ms_from_file(file)

          message = {
            type: 'audio',
            format: 'mp3',
            data: encoded,
            duration_ms: duration_ms
          }.to_json

          MASTER::Server.broadcast(message)
          sleep(duration_ms / 1000.0 + 0.3) # Wait for playback
        end
      end

      # Estimate duration from file size (~16kbps for speech)
      def estimate_duration_ms_from_file(file)
        size = File.size(file) rescue 0
        # ~16kbps = 2KB/sec for compressed speech
        (size / 2000.0 * 1000).round.clamp(1000, 30000)
      end

      # Cleanup temp files
      def cleanup(files)
        files.each { |f| File.delete(f) rescue nil }
      end

      # Detect platform
      def platform
        case RUBY_PLATFORM
        when /cygwin/ then :cygwin
        when /mingw|mswin/ then :windows
        when /darwin/ then :macos
        when /openbsd/ then :openbsd
        when /linux/ then :linux
        else :unknown
        end
      end
    end
  end
end
