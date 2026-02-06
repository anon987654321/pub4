# frozen_string_literal: true

require 'optparse'
require 'json'
require_relative 'unified/mood_indicator'
require_relative 'unified/personas'
require_relative 'unified/bug_hunting'
require_relative 'unified/resilience'
require_relative 'unified/systematic'

# Unified CLI v226 - Interactive + Batch modes
module MASTER
  class CLIv226
    attr_reader :mode, :options

    # ANSI colors - reuse MASTER conventions
    C_RESET  = "\e[0m"
    C_RED    = "\e[31m"
    C_GREEN  = "\e[32m"
    C_YELLOW = "\e[33m"
    C_CYAN   = "\e[36m"
    C_DIM    = "\e[2m"

    ICONS = {
      ok: "✓",
      err: "✗",
      warn: "!",
      item: "·",
      flow: "→"
    }.freeze

    def initialize(args = ARGV)
      @args = args
      @options = parse_options
      @mode = detect_mode
      @mood = Unified::MoodIndicator.new
      @persona = Unified::PersonaMode.new(mode: @options[:persona] || :verbose)
      @output_buffer = []
    end

    def run
      case @mode
      when :interactive
        run_interactive
      when :batch
        run_batch
      else
        show_help
        exit 1
      end
    end

    private

    # Dual mode detection
    def detect_mode
      if @args.empty? || @options[:interactive]
        :interactive
      elsif @options[:file]
        :batch
      else
        :unknown
      end
    end

    def parse_options
      options = {
        debug: false,
        json: false,
        persona: :verbose,
        interactive: false,
        file: nil
      }

      OptionParser.new do |opts|
        opts.banner = "Usage: ruby cli_v226.rb [file] [options]"

        opts.on("-d", "--debug", "Enable bug hunting mode") do
          options[:debug] = true
        end

        opts.on("-j", "--json", "Output in JSON format") do
          options[:json] = true
        end

        opts.on("-p PERSONA", "--persona=PERSONA", "Set persona mode (ronin, verbose, hacker, poet, detective)") do |p|
          options[:persona] = p.to_sym
        end

        opts.on("-i", "--interactive", "Force interactive mode") do
          options[:interactive] = true
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end
      end.parse!(@args)

      # First non-option argument is the file
      options[:file] = @args.first if @args.any?

      options
    end

    # Interactive REPL mode
    def run_interactive
      show_banner
      load_tty_lazy

      loop do
        @mood.set(:idle)
        print_prompt
        
        input = $stdin.gets
        break if input.nil? || input.strip.downcase == 'exit'
        
        input = input.strip
        next if input.empty?
        
        @mood.set(:thinking)
        @mood.display("Processing...")
        
        handle_command(input)
        
        @mood.clear
      end
      
      puts "\n#{C_GREEN}#{ICONS[:ok]}#{C_RESET} Goodbye!"
    end

    # Batch analysis mode
    def run_batch
      file = @options[:file]
      
      unless File.exist?(file)
        error_exit("File not found: #{file}")
      end
      
      @mood.set(:working) unless @options[:json]
      
      result = analyze_file(file)
      
      if @options[:json]
        output_json(result)
      else
        output_text(result)
      end
    end

    def analyze_file(file)
      results = {
        file: file,
        timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
        analysis: {}
      }
      
      # Basic analysis
      @mood.display("Reading file...") unless @options[:json]
      results[:analysis][:basic] = basic_analysis(file)
      
      # Bug hunting if --debug flag
      if @options[:debug]
        @mood.display("Running bug hunting protocol...") unless @options[:json]
        results[:analysis][:bug_hunting] = Unified::BugHunting.analyze_file(file)
      end
      
      # Systematic protocol check
      @mood.display("Checking systematic protocols...") unless @options[:json]
      results[:analysis][:systematic] = Unified::Systematic.before_edit(file)
      
      results
    end

    def basic_analysis(file)
      content = File.read(file)
      lines = content.lines
      
      {
        lines: lines.length,
        size: File.size(file),
        methods: content.scan(/def\s+\w+/).length,
        classes: content.scan(/class\s+\w+/).length,
        modules: content.scan(/module\s+\w+/).length,
        comments: lines.count { |l| l.strip.start_with?('#') }
      }
    end

    def handle_command(input)
      case input.downcase
      when 'help'
        show_help_interactive
      when 'persona'
        show_personas
      when /^persona\s+(\w+)$/
        switch_persona($1)
      when 'status'
        show_status
      when 'mood'
        test_moods
      else
        # Echo with persona formatting
        output = @persona.format_output("You said: #{input}")
        puts output
      end
    end

    def show_banner
      puts <<~BANNER
        #{C_CYAN}╔══════════════════════════════════════════╗#{C_RESET}
        #{C_CYAN}║#{C_RESET}  MASTER v226 - Unified Deep Debug    #{C_CYAN}║#{C_RESET}
        #{C_CYAN}╚══════════════════════════════════════════╝#{C_RESET}
        
        Type 'help' for commands, 'exit' to quit
        Current persona: #{C_YELLOW}#{@persona.current_mode}#{C_RESET}
        
      BANNER
    end

    def print_prompt
      mode_icon = @mood.current_mood == :idle ? "○" : "●"
      print "#{C_CYAN}#{mode_icon}#{C_RESET} #{C_DIM}master#{C_RESET} #{C_CYAN}›#{C_RESET} "
    end

    def show_help_interactive
      puts <<~HELP
        #{C_CYAN}Interactive Commands:#{C_RESET}
          help                Show this help
          persona             List available personas
          persona <mode>      Switch persona mode
          status              Show system status
          mood                Test mood indicators
          exit                Exit the CLI
      HELP
    end

    def show_help
      puts <<~HELP
        #{C_CYAN}MASTER v226 - Unified Deep Debug CLI#{C_RESET}
        
        #{C_YELLOW}Interactive Mode:#{C_RESET}
          ruby cli_v226.rb
          ruby cli_v226.rb --interactive
        
        #{C_YELLOW}Batch Analysis Mode:#{C_RESET}
          ruby cli_v226.rb file.rb
          ruby cli_v226.rb file.rb --debug     # Enable bug hunting
          ruby cli_v226.rb file.rb --json      # JSON output
        
        #{C_YELLOW}Options:#{C_RESET}
          -d, --debug          Enable 8-phase bug hunting protocol
          -j, --json           Output results in JSON format
          -p, --persona=MODE   Set persona mode (ronin, verbose, hacker, poet, detective)
          -i, --interactive    Force interactive mode
          -h, --help           Show this help
        
        #{C_YELLOW}Examples:#{C_RESET}
          ruby cli_v226.rb                           # Interactive REPL
          ruby cli_v226.rb lib/postpro.rb            # Analyze file
          ruby cli_v226.rb lib/postpro.rb --debug    # Deep bug hunting
          ruby cli_v226.rb lib/postpro.rb --json     # JSON output
      HELP
    end

    def show_personas
      puts "\n#{C_CYAN}Available Personas:#{C_RESET}"
      Unified::PersonaMode::MODES.each do |name, config|
        current = name == @persona.current_mode ? " #{C_GREEN}(current)#{C_RESET}" : ""
        puts "  #{C_YELLOW}#{name}#{C_RESET}: #{config[:description]}#{current}"
      end
      puts
    end

    def switch_persona(mode)
      if @persona.switch(mode)
        puts "#{C_GREEN}#{ICONS[:ok]}#{C_RESET} Switched to persona: #{C_YELLOW}#{mode}#{C_RESET}"
      else
        puts "#{C_RED}#{ICONS[:err]}#{C_RESET} Unknown persona: #{mode}"
      end
    end

    def show_status
      puts "\n#{C_CYAN}System Status:#{C_RESET}"
      puts "  Mode: #{@mode}"
      puts "  Persona: #{@persona.current_mode}"
      puts "  Current mood: #{@mood.current_mood}"
      puts
    end

    def test_moods
      puts "\n#{C_CYAN}Testing mood indicators:#{C_RESET}"
      
      Unified::MoodIndicator::MOODS.each do |mood, data|
        @mood.set(mood)
        @mood.display("#{data[:description]}...")
        sleep(0.5)
      end
      
      @mood.clear
      puts "#{C_GREEN}#{ICONS[:ok]}#{C_RESET} Mood test complete\n"
    end

    def output_json(result)
      puts JSON.pretty_generate(result)
    end

    def output_text(result)
      @mood.clear
      
      puts "\n#{C_CYAN}╔══════════════════════════════════════════╗#{C_RESET}"
      puts "#{C_CYAN}║#{C_RESET}  Analysis Results                      #{C_CYAN}║#{C_RESET}"
      puts "#{C_CYAN}╚══════════════════════════════════════════╝#{C_RESET}\n"
      
      puts "#{C_YELLOW}File:#{C_RESET} #{result[:file]}"
      puts "#{C_YELLOW}Time:#{C_RESET} #{result[:timestamp]}\n"
      
      if result[:analysis][:basic]
        basic = result[:analysis][:basic]
        puts "\n#{C_CYAN}Basic Metrics:#{C_RESET}"
        puts "  Lines: #{basic[:lines]}"
        puts "  Size: #{basic[:size]} bytes"
        puts "  Methods: #{basic[:methods]}"
        puts "  Classes: #{basic[:classes]}"
        puts "  Modules: #{basic[:modules]}"
        puts "  Comments: #{basic[:comments]}"
      end
      
      if result[:analysis][:bug_hunting]
        bug = result[:analysis][:bug_hunting]
        puts "\n#{C_CYAN}Bug Hunting Results:#{C_RESET}"
        puts "  Total issues: #{bug[:total_issues]}"
        puts "  Severity: #{bug[:severity]}"
        
        if bug[:total_issues] > 0
          puts "\n#{C_YELLOW}Issues by phase:#{C_RESET}"
          bug[:phases].each do |phase_name, phase_data|
            if phase_data[:issues]&.any?
              puts "  #{phase_name}: #{phase_data[:issues].length} issues"
            end
          end
        else
          puts "  #{C_GREEN}#{ICONS[:ok]} No issues found#{C_RESET}"
        end
      end
      
      if result[:analysis][:systematic]
        sys = result[:analysis][:systematic]
        puts "\n#{C_CYAN}Systematic Protocol:#{C_RESET}"
        puts "  Pattern: #{sys[:pattern]}"
        puts "  Lines: #{sys[:lines]}"
        puts "  #{C_GREEN}#{ICONS[:ok]} #{sys[:message]}#{C_RESET}"
      end
      
      puts
    end

    def error_exit(message)
      puts "#{C_RED}#{ICONS[:err]} Error:#{C_RESET} #{message}"
      exit 1
    end

    def load_tty_lazy
      # Lazy load TTY gems for interactive mode
      begin
        require 'tty-prompt'
        @prompt = TTY::Prompt.new(symbols: { marker: '›' })
      rescue LoadError
        # TTY not available, use basic prompts
        @prompt = nil
      end
    end
  end
end

# Run if called directly
if __FILE__ == $0
  cli = MASTER::CLIv226.new(ARGV)
  cli.run
end
