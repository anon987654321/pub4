# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"

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
        else            puts @renderer.render("tts: #{@tts_on ? "on" : "off"} — /tts on|off", mode: :dim)
        end
      else          return false  # falls through to pipeline — Infer stage handles natural language
      end
      true
    end

    def process(input)
      return if input.strip.empty?

      result = @pipeline.call(Result.ok(user_message: input))

      case result
      in Master::Result::Ok => ok
        @last_ok = true
        val  = ok.value
        text = val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
        puts text
        speak_async(text) if @tts_on
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def speak_async(text)
      Thread.new do
        plain = text.gsub(/\e\[[0-9;]*m/, "").strip   # strip ANSI
        plain = plain.gsub(/```.*?```/m, "")           # strip code blocks
        plain = plain[0..400]                          # cap length
        next if plain.empty?

        path = Speech.synthesize(plain)
        next unless path

        # OpenBSD: aucat; Linux fallback: mpv or aplay
        player = %w[mpv aucat aplay].find { |p| system("command -v #{p} > /dev/null 2>&1") }
        case player
        when "mpv"   then system("mpv", "--no-video", "--really-quiet", path, out: File::NULL, err: File::NULL)
        when "aucat" then system("aucat", "-i", path, out: File::NULL, err: File::NULL)
        when "aplay" then system("aplay", "-q", path, out: File::NULL, err: File::NULL)
        end
      rescue => e
        @logging&.warn("tts: #{e.message}")
      ensure
        File.unlink(path) rescue nil if path
      end
    end

    def run_prescan
      return if ENV["MASTER_PRESCAN"] == "false"
      # prescan deferred
    end

def report_violations
  return unless @scanner

  result = @scanner.scan_dir(@root, depth: :quick)
  return unless result.respond_to?(:value!)

  count = result.value!.sum { |_, r| r.respond_to?(:value!) ? r.value!.size : 0 }
  return if count.zero?

  puts @renderer.render(
    "#{count} violation(s) in lib/ — say 'fix all violations' to clean up",
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
    "  #{p.cyan("refactor")} #{p.white("lib/")}              — sweep and rewrite every file (all axioms + prose rules)",
    "  #{p.cyan("fix all violations")}            — autoloop until scan is clean",
    "  #{p.cyan("use multiple perspectives")}     — council deliberation on the next response",
    "  #{p.cyan("how many tokens have I used")}  — show context size and estimated cost",
    "  #{p.cyan("undo that")}                     — revert the last file change",
    "  #{p.cyan("save")} / #{p.cyan("clear")} / #{p.cyan("exit")}         — session management",
    "",
    "  #{p.dim("or just talk — intent is inferred automatically.")}",
    "  #{p.dim("explicit: /explain /persona /sweep /autoloop /council /tokens /undo /save /clear /exit")}",
    "",
  ]
  lines.join("\n")
end
  end
end
