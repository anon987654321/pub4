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
      @bus        = container[:bus]
      @reader      = TTY::Reader.new(track_history: true)
      @running     = false
      @interrupt_at   = 0
      @last_ok     = true
      @tts_on      = Speech.available? && @config["tts"] != false
      @violations  = 0
      @scan_thread = nil
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
      cmd, *args = s.split
      dispatch_command(cmd, args) || run_input(s)
    end

    def run_input(input)
      return if input.strip.empty?

      accumulated    = +""
      streamed       = false
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
        tokens = @session.respond_to?(:token_est) ? @session.token_est : nil
        print @renderer.prompt_line(
          @agent.model, @session.phase,
          last_ok: @last_ok, violations: @violations, tokens: tokens
        )
        line = begin
          @reader.read_line("", echo: true).chomp
        rescue StandardError
          nil
        end
        break if line.nil?
        next if line.strip.empty?
        handle_command(line) || run_input(line)
      end
      @scan_thread&.kill
      @session.save!
    end

    def handle_command(line)
      return false unless line.start_with?("/")
      cmd, *args = line[1..].split
      dispatch_command(cmd, args)
    end

    def dispatch_command(cmd, args)
      case cmd
      when "help"    then puts help_text
      when "clear"   then clear_screen
      when "exit"    then @session.save!; @running = false
      when "model"   then puts @renderer.render(@agent.model.to_s, mode: :dim)
      when "tokens"  then puts @renderer.render("session tokens: #{safe_token_est}", mode: :dim)
      when "save"    then @session.save!; puts @renderer.render("saved", mode: :success)
      when "dmesg"   then puts format_dmesg_lines
      when "scan"    then run_scan_command(args)
      when "stage"   then run_stage_command
      when "apply"   then run_apply_command(args)
      when "discard" then run_discard_command(args)
      when "staging" then toggle_staging(args)
      when "tts"     then toggle_tts(args)
      when "profile" then puts format_profile
      else           return false
      end
      true
    end

    def clear_screen
      print "\e[2J\e[H"
      puts @renderer.splash(@agent.model)
    end

    def safe_token_est
      @session.token_est
    rescue StandardError
      "n/a"
    end

    def format_profile
      t = @pipeline.last_timings
      return @renderer.render("(no profile -- run a query first)", mode: :dim) if t.nil? || t.empty?
      total = t.values.sum
      lines = t.map { |stage, ms| "  %-22s %dms" % [stage, ms] }
      (["last request:"] + lines + ["  " + "-" * 26, "  %-22s %dms" % ["total", total]]).join("\n")
    end

    def format_dmesg_lines
      @logging.dmesg(50).split("\n").map { |log_line| @renderer.format_dmesg(log_line) }.join("\n")
    end

    def toggle_staging(args)
      case args.first
      when "on"
        @config["staging_enabled"] = true
        @config.save!
        puts @renderer.render("staging: on", mode: :dim)
      when "off"
        @config["staging_enabled"] = false
        @config.save!
        puts @renderer.render("staging: off", mode: :dim)
      else
        status = @config["staging_enabled"] ? "on" : "off"
        puts @renderer.render("staging: #{status} -- /staging on|off", mode: :dim)
      end
    end

    def toggle_tts(args)
      case args.first
      when "on"
        @tts_on = Speech.available?
        puts @renderer.render("tts: #{@tts_on ? "on" : "unavailable"}", mode: :dim)
      when "off"
        @tts_on = false
        puts @renderer.render("tts: off", mode: :dim)
      else
        puts @renderer.render("tts: #{@tts_on ? "on" : "off"} -- /tts on|off", mode: :dim)
      end
    end

    def run_scan_command(args)
      depth  = args.include?("deep") ? :deep : :standard
      target = File.join(@root, "lib")
      puts @renderer.render("scanning #{target} (#{depth})...", mode: :dim)

      result = @scanner.scan_dir(target, depth:)
      unless result.respond_to?(:ok?) && result.ok?
        puts @renderer.render("scan failed", mode: :error)
        return
      end

      by_rule = group_violations_by_rule(result.value!)
      total   = by_rule.values.sum(&:size)
      @violations = total

      if total.zero?
        puts @renderer.render("clean -- no violations", mode: :success)
        return
      end

      render_violations_by_rule(by_rule)
      puts @renderer.render("#{total} total violations", mode: :warning)
    end

    def group_violations_by_rule(scan_results)
      by_rule = Hash.new { |hash, key| hash[key] = [] }
      scan_results.each do |_file, file_result|
        next unless file_result.respond_to?(:ok?) && file_result.ok?
        file_result.value!.each { |violation| by_rule[violation[:rule].to_s] << violation }
      end
      by_rule
    end

    def render_violations_by_rule(by_rule)
      by_rule.sort_by { |_, violations| -violations.size }.each do |rule, violations|
        puts @renderer.render("[#{rule}] #{violations.size}", mode: :dim)
        violations.first(3).each { |violation| puts "  L#{violation[:line]}: #{violation[:message][0, 90]}" }
        puts "  ... +#{violations.size - 3} more" if violations.size > 3
      end
    end

    def scan_in_background
      @scan_thread = Thread.new do
        lib_dir = File.join(@root, "lib")
        changed = begin
          out = `git -C \"#{@root}" diff --name-only HEAD 2>/dev/null`.strip
          out.empty? ? [] : out.lines.map { |l| File.join(@root, l.strip) }.select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
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

        next unless count > 0

        puts "\n#{@renderer.render("boot scan: #{count} violation(s) -- /scan for details", mode: :dim)}"
        print @renderer.prompt_line(
          @agent.model, @session.phase,
          last_ok: @last_ok, violations: @violations
        )
      rescue StandardError => scan_error
        @bus&.publish("cli:warn", message: scan_error.message)
      end
    end

    def build_chunk_handler(accumulated_buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?
        yield text
        accumulated_buffer << text
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
        text  = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
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
      rescue StandardError => tts_error
        @bus&.publish("tts:error", message: tts_error.message)
      ensure
        File.unlink(audio_path) rescue StandardError if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain = plain.gsub(/```.*?```/m, "")
      plain[0..400]
    end

    def try_paplay(audio_path)
      paplay = PAPLAY_CANDIDATES.find { |candidate| File.executable?(candidate) }
      return false unless paplay

      ffmpeg = FFMPEG_CANDIDATES.find { |candidate| File.executable?(candidate) }
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
      File.unlink(wav_path) rescue StandardError
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
        "--daemonize", "--exit-idle-time=60",
        out: File::NULL, err: File::NULL
      )
      sleep 0.6
      File.exist?(PULSE_SOCKET) ? PULSE_SOCKET : nil
    end

    def try_direct(audio_path)
      player = %w[aucat mpv ffplay aplay].find { |candidate| system("command -v #{candidate} > /dev/null 2>&1") }
      case player
      when "aucat"  then system("aucat",  "-i", audio_path, out: File::NULL, err: File::NULL)
      when "mpv"    then system("mpv",    "--no-video", "--really-quiet", audio_path, out: File::NULL, err: File::NULL)
      when "ffplay" then system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audio_path, out: File::NULL, err: File::NULL)
      when "aplay"  then system("aplay",  "-q", audio_path, out: File::NULL, err: File::NULL)
      else false
      end
    end

    def run_stage_command
      pastel = Pastel.new
      unless @diff_stager
        puts @renderer.render("staging not enabled -- /staging on to enable", mode: :dim)
        return
      end
      if @diff_stager.empty?
        puts pastel.dim("  no staged changes")
      else
        puts pastel.bold.cyan(" staged changes (#{@diff_stager.size}) ")
        puts @diff_stager.summary(pastel)
        puts pastel.dim("  /apply [n|all]   /discard [n|all]")
      end
    end

    def run_apply_command(args)
      unless @diff_stager
        puts @renderer.render("staging not enabled", mode: :dim)
        return
      end
      id    = (args.first.nil? || args.first == "all") ? :all : args.first.to_i
      paths = @diff_stager.apply(id:)
      if paths.empty?
        puts @renderer.render("nothing to apply", mode: :dim)
      else
        paths.each { |applied_path| puts @renderer.render("applied: #{applied_path.sub(@root + "/", "")}", mode: :success) }
      end
    end

    def run_discard_command(args)
      unless @diff_stager
        puts @renderer.render("staging not enabled", mode: :dim)
        return
      end
      id    = (args.first.nil? || args.first == "all") ? :all : args.first.to_i
      paths = @diff_stager.discard(id:)
      if paths.empty?
        puts @renderer.render("nothing to discard", mode: :dim)
      else
        paths.each { |discarded_path| puts @renderer.render("discarded: #{discarded_path.sub(@root + "/", "")}", mode: :warning) }
      end
    end

    def setup_signals
      trap("USR1") do
        begin
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@renderer.render('reloaded', mode: :success)}"
        rescue => reload_err
          puts "\n#{@renderer.render("reload failed: #{reload_err.message}", mode: :error)}"
        end
      end
      trap("INT") {
        now = Time.now.to_f
        if now - @interrupt_at < 1.0
          @scan_thread&.kill
          @session.save!
          exit(0)
        else
          @interrupt_at = now
          puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
        end
      }
    end

    def help_text
      pastel = Pastel.new
      lines = [
        "",
        pastel.bold.cyan(" what I can do "),
        "",
        "  #{pastel.cyan("refactor")} #{pastel.white("lib/")}              -- sweep and rewrite every file",
        "  #{pastel.cyan("fix all violations")}            -- autoloop until scan is clean",
        "  #{pastel.cyan("use multiple perspectives")}     -- council deliberation on the next response",
        "  #{pastel.cyan("how many tokens have I used")}  -- show context size and estimated cost",
        "  #{pastel.cyan("undo that")}                     -- revert the last file change",
        "  #{pastel.cyan("save")} / #{pastel.cyan("clear")} / #{pastel.cyan("exit")}         -- session management",
        "",
        "  #{pastel.dim("or just talk -- intent is inferred automatically.")}",
        "  #{pastel.dim("explicit: /scan /scan deep /explain /persona /sweep /autoloop /council /tts /tokens /undo /save /clear /exit")}",
        "",
      ]
      lines.join("\n")
    end
  end
end
