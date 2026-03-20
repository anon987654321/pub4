# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI

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
      @reader      = TTY::Reader.new(track_history: true)
      @running     = false
      @ctrl_c_ts   = 0
      @last_ok     = true
      @tts_on      = Speech.available? && @config["tts"] != false
      @violations  = 0
      @scan_thread = nil
      @diff_stager = container[:diff_stager]
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      start_background_scan

      puts @renderer.splash(@agent.model)

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
        tokens = @session.respond_to?(:token_est) ? @session.token_est : nil
        print @renderer.prompt_line(
          @agent.model, @session.phase,
          last_ok: @last_ok, violations: @violations, tokens: tokens
        )
        line = @reader.read_line("", echo: true).chomp rescue nil
        break if line.nil?
        next if line.strip.empty?
        handle_command(line) || process(line)
      end
      @scan_thread&.kill
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
      when "scan"    then run_scan_command(args)
      when "stage"   then run_stage_command
      when "apply"   then run_apply_command(args)
      when "discard" then run_discard_command(args)
      when "staging"
        case args.first
        when "on"  then @config["staging_enabled"] = true;  @config.save!; puts @renderer.render("staging: on",  mode: :dim)
        when "off" then @config["staging_enabled"] = false; @config.save!; puts @renderer.render("staging: off", mode: :dim)
        else             puts @renderer.render("staging: #{@config["staging_enabled"] ? "on" : "off"} -- /staging on|off", mode: :dim)
        end
      when "tts"
        case args.first
        when "on"  then @tts_on = Speech.available?; puts @renderer.render("tts: #{@tts_on ? "on" : "unavailable"}", mode: :dim)
        when "off" then @tts_on = false;             puts @renderer.render("tts: off", mode: :dim)
        else            puts @renderer.render("tts: #{@tts_on ? "on" : "off"} -- /tts on|off", mode: :dim)
        end
      else          return false
      end
      true
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

      by_rule = Hash.new { |h, k| h[k] = [] }
      result.value!.each do |_file, r|
        next unless r.respond_to?(:ok?) && r.ok?
        r.value!.each { |v| by_rule[v[:rule].to_s] << v }
      end

      total = by_rule.values.sum(&:size)
      @violations = total

      if total.zero?
        puts @renderer.render("clean -- no violations", mode: :success)
        return
      end

      by_rule.sort_by { |_, vs| -vs.size }.each do |rule, vs|
        puts @renderer.render("[#{rule}] #{vs.size}", mode: :dim)
        vs.first(3).each { |v| puts "  L#{v[:line]}: #{v[:message][0, 90]}" }
        puts "  ... +#{vs.size - 3} more" if vs.size > 3
      end
      puts @renderer.render("#{total} total violations", mode: :warning)
    end

    def start_background_scan
      @scan_thread = Thread.new do
        result = @scanner.scan_dir(File.join(@root, "lib"), depth: :standard)
        next unless result.respond_to?(:ok?) && result.ok?

        count = result.value!.sum { |_, r| r.respond_to?(:ok?) && r.ok? ? r.value!.size : 0 }
        @violations = count

        if count > 0
          puts "\n#{@renderer.render("boot scan: #{count} violation(s) -- /scan for details", mode: :dim)}"
          print @renderer.prompt_line(
            @agent.model, @session.phase,
            last_ok: @last_ok, violations: @violations
          )
        end
      rescue StandardError => e
        @bus&.publish("cli:warn", message: )
      end
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
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        File.unlink(mp3) rescue nil if defined?(mp3) && mp3
      end
    end

    PULSE_SOCKET = "/tmp/pulse/native"
    PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio"

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


def run_stage_command
  p = Pastel.new
  unless @diff_stager
    puts @renderer.render("staging not enabled -- /staging on to enable", mode: :dim)
    return
  end
  if @diff_stager.empty?
    puts p.dim("  no staged changes")
  else
    puts p.bold.cyan(" staged changes (#{@diff_stager.size}) ")
    puts @diff_stager.summary(p)
    puts p.dim("  /apply [n|all]   /discard [n|all]")
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
    paths.each { |ap| puts @renderer.render("applied: #{ap.sub(@root + "/", "")}", mode: :success) }
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
    paths.each { |dp| puts @renderer.render("discarded: #{dp.sub(@root + "/", "")}", mode: :warning) }
  end
end

    def setup_signals
      trap("INT") {
        now = Time.now.to_f
        if now - @ctrl_c_ts < 1.0
          @scan_thread&.kill
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
        "  #{p.dim("explicit: /scan /scan deep /explain /persona /sweep /autoloop /council /tts /tokens /undo /save /clear /exit")}",
        "",
      ]
      lines.join("\n")
    end
  end
end
