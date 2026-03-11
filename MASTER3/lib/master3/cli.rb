# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"

module Master3
  class CLI
    COMMANDS = %w[clear save tokens undo diff tree model mode task autotest dmesg cost config help exit].freeze

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
      @reader    = TTY::Reader.new(track_history: true)
      @running   = false
      @ctrl_c_ts = 0
      @last_ok   = true
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      run_prescan if @config.prescan?

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
      when "tokens" then puts @renderer.render("session tokens: #{@session.token_count rescue "n/a"}", mode: :dim)
      when "save"   then @session.save!; puts @renderer.render("saved", mode: :success)
      when "dmesg"  then puts @logging.dmesg(50).split("\n").map { |l| @renderer.format_dmesg(l) }.join("\n")
      else               puts @renderer.render("unknown command: /#{cmd}", mode: :warning)
      end
      true
    end

    def process(input)
      return if input.strip.empty?

      result = @pipeline.call(Result.ok(user_message: input))

      case result
      in Master3::Result::Ok => ok
        @last_ok = true
        val = ok.value
        if val.is_a?(Hash) && val[:rendered]
          puts val[:rendered]
        else
          puts @renderer.render(val.inspect, mode: :dim)
        end
      in Master3::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def run_prescan
      return if ENV["MASTER_PRESCAN"] == "false"
      # prescan deferred
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
      header = p.bold.cyan(" commands ")
      cmds   = COMMANDS.map { |c| "  #{p.cyan("/")}#{p.white(c)}" }.join("\n")
      "\n#{header}\n#{cmds}\n"
    end
  end
end
