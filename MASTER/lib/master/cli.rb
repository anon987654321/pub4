# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI

    attr_reader :container

    def initialize(container:)
      @container = container
      @session   = container[:session]
      @agent     = container[:agent]
      @renderer  = container[:renderer]
      @logging   = container[:logging]
      @undo      = container[:undo]
      @config    = container[:config]
      @pipeline  = container[:pipeline]
      @scanner   = container[:scanner]
      @root      = container[:root] || Dir.pwd
      @reader    = TTY::Reader.new(track_history: true)
      @running   = false
      @ctrl_c_ts = 0
      @last_ok   = true
      @tts_on    = Speech.available? && @config["tts"] != false
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      run_prescan if @config.prescan?

      puts @renderer.splash(@agent.model)
      report_violations

      process(initial_message) if initial_message

      @running = true
      repl_loop
    end

    def pipe(input)
      process(input.strip)
    end

    private

    def repl_loop
      while @running
        print @renderer.prompt_line(@agent.model, @session.phase, last_ok: @last_ok)
        line = @reader.read_line("", echo: true).chomp rescue nil
        break if line.nil?
        next if line.strip.empty?
        handle_command(line) || process(line)
      end
      @session.save!
    end

    def handle_command(line)
      return false unless line.start_with?("/")
      cmd, *args = line[1..].split
      case cmd
      when "help"   then puts help_text
      when "clear"  then print "\e[2J\e[H"; puts @renderer.splash(@agent.model)
      when "exit"   then @session.save!; @running = false
      when "model"  then puts @renderer.render(@agent.model.to_s, mode: :dim)
      when "tokens" then puts @renderer.render("session tokens: #{@session.token_est rescue "n/a"}", mode: :dim)
      when "save"   then @session.save!; puts @renderer.render("saved", mode: :success)
      when "dmesg"  then puts @logging.dmesg(50).split("\n").map { |l| @renderer.format_dmesg(l) }.join("\n")
      when "tts"
        case args.first
        when "on"  then @tts_on = Speech.available?; puts @renderer.render("tts: #{@tts_on ? "on" : "unavailable"}", mode: :dim)
        when "off" then @tts_on = false;             puts @renderer.render("tts: off", mode: :dim)
        else            puts @renderer.render("tts: #{@tts_on ? "on" : "off"} -- /tts on|off", mode: :dim)
        end
      else          return false  # falls through to pipeline -- Infer stage handles natural language
      end
      true
    end

    def process(input)
      return if input.strip.empty?

      accumulated = +""
      streamed    = false

      on_chunk = ->(chunk) {
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?
        print text
        $stdout.flush
        accumulated << text
        streamed = true
      }

      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))

      case result
      in Master::Result::Ok => ok
        @last_ok = true
        if streamed
          puts
          speak_async(accumulated) if @tts_on
        else
          val  = ok.value
          text = val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
          puts text
          speak_async(text) if @tts_on
        end
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def speak_async(text)
      Thread.new do
        plain = text.gsub(/\e\[[0-9;]*m/, "").strip
        plain = plain.gsub(/```.*?```/m, "")
        plain = plain[0..400]
        next if plain.empty?

        mp3 = Speech.synthesize(plain)
        next unless mp3

        played = try_paplay(mp3) || try_direct(mp3)
        @logging&.warn("tts: no audio output found") unless played
      rescue => e
        @logging&.warn("tts: #{e.message}")
      ensure
        File.unlink(mp3) rescue nil if defined?(mp3) && mp3
      end
    end

    PULSE_SOCKET = "/tmp/pulse/native"
    PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio"

    # PulseAudio path: works on Termux/proot (Android) and Linux desktops.
    # Converts mp3 to wav, auto-starts a pulse daemon if the socket is missing.
    def try_paplay(mp3)
      paplay = %w[
        /data/data/com.termux/files/usr/bin/paplay
        /usr/bin/paplay
        /usr/local/bin/paplay
      ].find { |p| File.executable?(p) }
      return false unless paplay

      ffmpeg = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].find { |p| File.executable?(p) }
      return false unless ffmpeg

      socket = ensure_pulse_socket
      return false unless socket

      wav = mp3.sub(/\.mp3$/, ".wav")
      ok  = system(ffmpeg, "-y", "-i", mp3, wav, "-loglevel", "quiet",
                   out: File::NULL, err: File::NULL)
      return false unless ok && File.exist?(wav)

      ENV["PULSE_SERVER"] = "unix:#{socket}"
      result = system(paplay, wav, out: File::NULL, err: File::NULL)
      File.unlink(wav) rescue nil
      result
    end

    def ensure_pulse_socket
      return PULSE_SOCKET if File.exist?(PULSE_SOCKET)
      return nil unless File.executable?(PULSE_DAEMON)

      FileUtils.mkdir_p(File.dirname(PULSE_SOCKET))
      system(
        PULSE_DAEMON,
        "--load=module-alsa-sink device=default",
        "--load=module-native-protocol-unix auth-anonymous=1 socket=#{PULSE_SOCKET}",
        "--daemonize", "--exit-idle-time=60",
        out: File::NULL, err: File::NULL
      )
      sleep 0.6
      File.exist?(PULSE_SOCKET) ? PULSE_SOCKET : nil
    end

    # Direct players: OpenBSD aucat, mpv, ffplay, aplay
    def try_direct(mp3)
      player = %w[aucat mpv ffplay aplay].find { |p| system("command -v #{p} > /dev/null 2>&1") }
      case player
      when "aucat"  then system("aucat",  "-i", mp3, out: File::NULL, err: File::NULL)
      when "mpv"    then system("mpv",    "--no-video", "--really-quiet", mp3, out: File::NULL, err: File::NULL)
      when "ffplay" then system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", mp3, out: File::NULL, err: File::NULL)
      when "aplay"  then system("aplay",  "-q", mp3, out: File::NULL, err: File::NULL)
      else; false
      end
    end

    def run_prescan
      return if ENV["MASTER_PRESCAN"] == "false"
    end

    def report_violations
      return unless @scanner

      result = @scanner.scan_dir(@root, depth: :quick)
      return unless result.respond_to?(:value!)

      count = result.value!.sum { |_, r| r.respond_to?(:value!) ? r.value!.size : 0 }
      return if count.zero?

      puts @renderer.render(
        "#{count} violation(s) in lib/ -- say 'fix all violations' to clean up",
        mode: :dim
      )
    end

    def setup_signals
      trap("INT") {
        now = Time.now.to_f
        if now - @ctrl_c_ts < 1.0
          @session.save!
          exit(0)
        else
          @ctrl_c_ts = now
          puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
        end
      }
    end

    def help_text
      p = Pastel.new
      lines = [
        "",
        p.bold.cyan(" what I can do "),
        "",
        "  #{p.cyan("refactor")} #{p.white("lib/")}              -- sweep and rewrite every file",
        "  #{p.cyan("fix all violations")}            -- autoloop until scan is clean",
        "  #{p.cyan("use multiple perspectives")}     -- council deliberation on the next response",
        "  #{p.cyan("how many tokens have I used")}  -- show context size and estimated cost",
        "  #{p.cyan("undo that")}                     -- revert the last file change",
        "  #{p.cyan("save")} / #{p.cyan("clear")} / #{p.cyan("exit")}         -- session management",
        "",
        "  #{p.dim("or just talk -- intent is inferred automatically.")}",
        "  #{p.dim("explicit: /explain /persona /sweep /autoloop /council /tokens /undo /save /clear /exit")}",
        "",
      ]
      lines.join("\n")
    end
  end
end
