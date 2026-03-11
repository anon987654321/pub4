# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"

module Master3
  class CLI
    COMMANDS = %w[clear save tokens undo diff tree model mode task autotest dmesg cost config help exit].freeze

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
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      run_prescan if @config.prescan?

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
        print @renderer.prompt_line(@agent.model, @session.phase)
        line = @reader.read_line("", echo: true).chomp rescue nil
        break if line.nil?
        process(line)
      end
      @session.save!
    end

    def process(input)
      return if input.strip.empty?

      result = @pipeline.call(Result.ok(user_message: input))

      case result
      in Master3::Result::Ok => ok
        val = ok.value
        if val.is_a?(Hash) && val[:rendered]
          puts val[:rendered]
        else
          puts @renderer.render(val.inspect, mode: :dim)
        end
      in Master3::Result::Err => err
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
          puts "\n(^C again to quit)"
        end
      }
    end

    def history_path
      dir = File.join(Dir.pwd, ".master3")
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.join(dir, "history")
    end

    def help_text
      COMMANDS.map { |c| "  /#{c}" }.join("\n")
    end
  end
end
