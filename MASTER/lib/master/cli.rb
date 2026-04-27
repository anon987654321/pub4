# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
    PULSE_SOCKET = "/tmp/pulse/native".freeze
    PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze

    PAPLAY_CANDIDATES = %w[
      /data/data/com.termux/files/usr/bin/paplay
      /usr/bin/paplay
      /usr/local/bin/paplay
    ].freeze

    FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze

    DMESG_LINES = 50

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    attr_reader :container

    def initialize(container:)
      @container   = container
      @session     = container[:session]
      @agent       = container[:agent]
      @renderer    = container[:renderer]
      @logging     = container[:logging]
      @undo        = container[:undo]
      @config      = container[:config]
      @pipeline    = container[:pipeline]
      @scanner     = container[:scanner]
      @root        = container[:root] || Dir.pwd
      @diff_stager = container[:diff_stager]
      @bus         = container[:bus]
      @reader      = TTY::Reader.new(track_history: true)
      @running     = false
      @interrupt_at = Time.now
      @last_ok     = true
      @tts_on      = Speech.available? && @config["tts"] != false
      @violations  = 0
      @scan_thread = nil
      @seen_violations = {}
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      scan_in_background
      puts @renderer.splash(@agent.model)
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      s = input.strip
      return if s.empty?

      run_input(s)
    end

    def run_input(input)
      return if input.strip.empty?

      accumulated = +""
      streamed = false
      thinking_shown = true

      on_chunk = build_chunk_handler(accumulated) do |text|
        if thinking_shown && $stdout.isatty
          print "\r\e[K"
          thinking_shown = false
        end
        print text
        $stdout.flush
        streamed = true
      end

      print_thinking_indicator
      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      handle_pipeline_result(result, accumulated, streamed)
    end

    private

    def repl_loop
      while @running
        tokens = @session.token_est
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations,
          tokens: tokens
        )
        line = begin
          @reader.read_line("", echo: true).chomp
        rescue StandardError
          nil
        end
        break if line.nil?
        next if line.strip.empty?

        if line.strip == "/exit"
          exit_cli
        else
          run_input(line)
        end
      end
      @scan_thread&.kill
      @session.save!
    end

    def exit_cli
      @session.save!
      @running = false
    end

    def scan_in_background
      @scan_thread = Thread.new do
        lib_dir = File.join(@root, "lib")
        changed = begin
          out = `git -C "#{@root}" diff --name-only HEAD 2>/dev/null`.strip
          out.empty? ? [] : out.lines.map { |l| File.join(@root, l.strip) }
                 .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
        rescue StandardError
          []
        end

        result = if changed.any?
                   Result.ok(changed.map { |p| [p, @scanner.scan(p, depth: :standard)] })
                 else
                   @scanner.scan_dir(lib_dir, depth: :standard)
                 end

        next unless result.respond_to?(:ok?) && result.ok?

        count = result.value!.sum do |_file, file_result|
          file_result.respond_to?(:ok?) && file_result.ok? ? file_result.value!.size : 0
        end
        @violations = count

        next if count.zero?

        puts "\n#{@renderer.render("boot scan: #{count} violation(s)", mode: :dim)}"
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations
        )
      rescue StandardError => e
        @bus&.publish("cli:warn", message: e.message)
      end
    end

    def build_chunk_handler(buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?

        yield text
        buffer << text
      end
    end

    def print_thinking_indicator
      return unless $stdout.isatty

      print @renderer.render("thinking...", mode: :dim)
      $stdout.flush
    rescue StandardError
      print "thinking..."
    end

    def handle_pipeline_result(result, accumulated, streamed)
      case result
      in Master::Result::Ok => ok
        @last_ok = true
        handle_ok_result(ok, accumulated, streamed)
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def handle_ok_result(ok, accumulated, streamed)
      if streamed
        puts
        speak_async(accumulated) if @tts_on
      else
        print "\r\e[K" if $stdout.isatty
        value = ok.value
        text = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
        puts text
        speak_async(text) if @tts_on
      end
    end

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?

        audio_path = Speech.synthesize(plain)
        next unless audio_path

        played = try_paplay(audio_path) || try_direct(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        File.unlink(audio_path) rescue nil if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain = plain.gsub(/```.*?```/m, "")
      plain[0..400]
    end

    def try_paplay(audio_path)
      paplay = PAPLAY_CANDIDATES.find { |c| File.executable?(c) }
      return false unless paplay

      ffmpeg = FFMPEG_CANDIDATES.find { |c| File.executable?(c) }
      return false unless ffmpeg

      socket = ensure_pulse_socket
      return false unless socket

      convert_and_play_via_pulse(audio_path, paplay, ffmpeg, socket)
    end

    def convert_and_play_via_pulse(audio_path, paplay, ffmpeg, socket)
      wav_path = audio_path.sub(/\.mp3$/, ".wav")
      converted = system(
        ffmpeg, "-y", "-i", audio_path, wav_path, "-loglevel", "quiet",
        out: File::NULL, err: File::NULL
      )
      return false unless converted && File.exist?(wav_path)

      ENV["PULSE_SERVER"] = "unix:#{socket}"
      played = system(paplay, wav_path, out: File::NULL, err: File::NULL)
      File.unlink(wav_path) rescue nil
      played
    end

    def ensure_pulse_socket
      return PULSE_SOCKET if File.exist?(PULSE_SOCKET)
      return nil unless File.executable?(PULSE_DAEMON)

      FileUtils.mkdir_p(File.dirname(PULSE_SOCKET))
      system(
        PULSE_DAEMON,
        "--load=module-alsa-sink device=default",
        "--load=module-native-protocol-unix auth-anonymous=1 socket=#{PULSE_SOCKET}",
        "--daemonize",
        "--exit-idle-time=60",
        out: File::NULL,
        err: File::NULL
      )
      sleep 0.6
      File.exist?(PULSE_SOCKET) ? PULSE_SOCKET : nil
    end

    def try_direct(audio_path)
      player = %w[aucat mpv ffplay aplay].find { |c| system("command -v #{c} > /dev/null 2>&1") }
      case player
      when "aucat"
        system("aucat", "-i", audio_path, out: File::NULL, err: File::NULL)
      when "mpv"
        system("mpv", "--no-video", "--really-quiet", audio_path, out: File::NULL, err: File::NULL)
      when "ffplay"
        system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audio_path, out: File::NULL, err: File::NULL)
      when "aplay"
        system("aplay", "-q", audio_path, out: File::NULL, err: File::NULL)
      else
        false
      end
    end

    def setup_signals
      trap("USR1") do
        begin
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@renderer.render('reloaded', mode: :success)}"
        rescue StandardError => e
          puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
        end
      end
      trap("INT") do
        if Time.now - @interrupt_at < 1
          @scan_thread&.kill
          @session.save!
          exit(0)
        else
          @interrupt_at = Time.now
          puts "\n#{@renderer.render('^C again to quit', mode: :warning)}"
        end
      end
    end
  end
end
