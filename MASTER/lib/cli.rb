# frozen_string_literal: true

require 'readline'
require 'fileutils'
require 'io/console'
require 'securerandom'
require 'json'
require 'shellwords'

# Optional rich terminal UI
begin
  require 'tty-prompt'
  require 'tty-spinner'
  require 'tty-table'
  require 'tty-box'
  require 'pastel'
  TTY_AVAILABLE = true
rescue LoadError
  TTY_AVAILABLE = false
end

require_relative 'cli/commands/openbsd' if RUBY_PLATFORM.include?('openbsd')

module MASTER
  class CLI
    include Commands::OpenBSD if RUBY_PLATFORM.include?('openbsd')

    attr_reader :llm, :verbosity, :root

    # ANSI colors - one meaning per color, never reuse
    C_RESET  = "\e[0m"
    C_RED    = "\e[31m"    # Error only
    C_GREEN  = "\e[32m"    # Success only
    C_YELLOW = "\e[33m"    # Warning only
    C_CYAN   = "\e[36m"    # Accent (sparingly)
    C_DIM    = "\e[2m"     # Secondary/metadata
    C_BOLD   = "\e[1m"     # Primary emphasis
    C_ITALIC = "\e[3m"     # Secondary emphasis
    C_GREY   = "\e[38;5;245m"  # Dark grey for main text (calmer than white)

    # Icon vocabulary - 5 symbols max, single meaning each
    ICON_OK   = "✓"
    ICON_ERR  = "✗"
    ICON_WARN = "!"
    ICON_ITEM = "·"
    ICON_FLOW = "→"

    # Spinner (ASCII, by prompt)
    SPINNER = %w[| / - \\].freeze

    # Boot quotes (rotates each session)
    QUOTES = [
      "Simplicity is the ultimate sophistication.",
      "Make it work, make it right, make it fast.",
      "Code is read more often than written.",
      "The best code is no code at all.",
      "Clarity over cleverness.",
      "Ship it.",
      "Done is better than perfect.",
      "Constraints breed creativity.",
      "Less, but better.",
      "If in doubt, leave it out."
    ].freeze

    # Session name parts
    ADJECTIVES = %w[crimson azure golden silent swift keen bright calm deep iron].freeze
    NOUNS = %w[falcon raven wolf oak storm forge arrow tide spark blade].freeze

    # Easter eggs (1% chance)
    EGGS = [
      "The machine spirit is pleased.",
      "Consulting the oracle...",
      "Reticulating splines..."
    ].freeze

    # Achievements
    ACHIEVEMENTS = {
      first_command: { name: "First Steps", desc: "Ran first command" },
      streak_5: { name: "Momentum", desc: "5 without error" },
      streak_25: { name: "Flow State", desc: "25 without error" },
      first_refactor: { name: "Craftsman", desc: "First refactor" },
      spent_1: { name: "Investor", desc: "Spent $1 on LLM" },
      commands_100: { name: "Centurion", desc: "100 commands" }
    }.freeze

    # Command aliases for speed
    ALIASES = {
      'q' => 'queue', 's' => 'scan', 'r' => 'refactor', 'a' => 'ask',
      'c' => 'chamber', 'e' => 'evolve', 'i' => 'introspect', 'p' => 'personas',
      'v' => 'version', 'h' => 'help', '?' => 'help', 'd' => 'diff', 'l' => 'log',
      'st' => 'status', 'hi' => 'history', 'cl' => 'clear'
    }.freeze

    COMMANDS = %w[
      ask audit backend beautify cat cd chamber check-ports clean clear commit compare-images
      context converge cost deps describe diff edit enforce-principles evolve exit fav favs git help
      history image install install-hooks introspect lint log ls metrics persona personas principles pull push
      queue quit radio read refactor refine reload review sanity scan smells speak status stream
      tree undo version web
    ].freeze

    HISTORY_FILE = Paths.history
    STATE_FILE = File.join(Paths.var, 'cli_state.json')
    HISTORY_LIMIT = 100
    EASTER_EGG_CHANCE = 0.01
    UPTIME_THRESHOLD = 3600  # Show uptime after 1 hour
    COST_TIER_LOW = 0.01
    COST_TIER_MED = 0.10
    MAX_CODE_PREVIEW = 2000
    MAX_RESEARCH_PREVIEW = 500
    MAX_VIOLATION_PREVIEW = 200
    MAX_REASON_PREVIEW = 200
    MAX_RESPONSE_PREVIEW = 150
    INTERRUPT_TIMEOUT = 2.0  # Seconds to press Ctrl+C again to quit

    # Verbosity levels
    VERBOSITY = { low: 0, medium: 1, high: 2 }.freeze

    def initialize(llm: LLM.new, root: Dir.pwd, verbosity: 0, quiet: false, dry_run: false)
      @llm = llm
      @server = nil
      @root = root
      @verbosity = :high
      @boot_time = Time.now
      @last_tokens = { input: 0, output: 0 }
      @last_cached = false
      @session_name = "#{ADJECTIVES.sample}-#{NOUNS.sample}"
      @streak = 0
      @command_count = 0
      @total_cost = 0.0
      @achievements = []
      @favorites = []
      @aliases = {}
      @last_files = {}
      @last_file = nil      # Most recent file operated on
      @last_dir = nil       # Most recent directory
      @last_query = nil     # Most recent LLM query
      @last_result = nil    # Most recent result
      @last_interrupt = nil
      @input_queue = Queue.new
      @processing = false
      @pastel = Pastel.new if TTY_AVAILABLE
      @prompt = TTY::Prompt.new(symbols: { marker: '›' }, active_color: :cyan) if TTY_AVAILABLE
      load_state
      setup_completion
      load_history
      setup_crash_recovery
      load_self_awareness
    end
    
    # Smart defaults - infer missing arguments from context
    def default_file(arg = nil)
      return arg if arg && !arg.empty?
      return @last_file if @last_file && File.exist?(@last_file)
      
      # Find most recently modified .rb file in current dir
      Dir.glob(File.join(@root, '*.rb')).max_by { |f| File.mtime(f) }
    end
    
    def default_dir(arg = nil)
      return arg if arg && !arg.empty?
      return @last_dir if @last_dir && Dir.exist?(@last_dir)
      @root
    end
    
    def default_target(arg = nil)
      return arg if arg && !arg.empty?
      return @last_file if @last_file
      return @last_dir if @last_dir
      @root
    end
    
    def remember_file(path)
      @last_file = File.expand_path(path, @root) if path
    end
    
    def remember_dir(path)
      @last_dir = File.expand_path(path, @root) if path && Dir.exist?(File.expand_path(path, @root))
    end

    def run
      start_server
      repl
    end

    def trace(msg)
      return unless @verbosity == :high
      ts = format('%07.3f', Time.now - @boot_time)
      puts " #{ts}  #{msg}"
    end

    def info(msg)
      puts "#{C_DIM}#{msg}#{C_RESET}" if VERBOSITY[@verbosity] >= 1
    end

    def process_input(input)
      input = input.to_s.strip
      return nil if input.empty?

      result = handle(input)
      broadcast(result) if result
      result
    end

    private

    def setup_completion
      Readline.completion_proc = proc do |s|
        COMMANDS.grep(/^#{Regexp.escape(s)}/)
      end
      Readline.completion_append_character = ' '
    end

    def load_self_awareness
      # Load MASTER's knowledge of itself
      SelfAwareness.load
      
      # Inject into LLM context
      @llm.add_system_context(SelfAwareness.context_for_llm)
    rescue => e
      # Non-fatal - continue without self-awareness
      trace("Self-awareness load failed: #{e.message}")
    end

    def load_history
      return unless File.exist?(HISTORY_FILE)

      File.readlines(HISTORY_FILE).last(HISTORY_LIMIT).each do |line|
        Readline::HISTORY.push(line.chomp)
      end
    rescue StandardError
      # Ignore history errors
    end

    def save_history
      File.open(HISTORY_FILE, 'a') do |f|
        Readline::HISTORY.to_a.last(HISTORY_LIMIT).each { |line| f.puts(line) }
      end
    rescue StandardError
      # Ignore history errors
    end

    def setup_crash_recovery
      # Double Ctrl+C to quit (first one just warns)
      trap('INT') do
        now = Time.now
        if @last_interrupt && (now - @last_interrupt) < INTERRUPT_TIMEOUT
          puts "\n#{C_DIM}Exiting...#{C_RESET}"
          emergency_save
          exit(0)
        else
          @last_interrupt = now
          puts "\n#{C_YELLOW}Press Ctrl+C again within #{INTERRUPT_TIMEOUT.to_i}s to quit#{C_RESET}"
        end
      end

      # Other signals still exit immediately
      %w[TERM HUP].each do |sig|
        trap(sig) do
          emergency_save
          exit(1)
        end
      end

      # Auto-save on unhandled exceptions
      at_exit { emergency_save }
    end

    def emergency_save
      save_state
      save_history
      @llm.clear_history rescue nil
    rescue StandardError
      # Best effort
    end

    def load_state
      return unless File.exist?(STATE_FILE)

      data = JSON.parse(File.read(STATE_FILE), symbolize_names: true)
      @achievements = data[:achievements] || []
      @favorites = data[:favorites] || []
      @aliases = data[:aliases] || {}
      @command_count = data[:command_count] || 0
      @total_cost = data[:total_cost] || 0.0
    rescue StandardError
      # Fresh state
    end

    def save_state
      FileUtils.mkdir_p(Paths.var)
      File.write(STATE_FILE, JSON.pretty_generate({
        achievements: @achievements,
        favorites: @favorites,
        aliases: @aliases,
        command_count: @command_count,
        total_cost: @total_cost
      }))
    rescue StandardError
      # Ignore save errors
    end

    def ask_verbosity
      puts "Detail level?"
      puts "  1. Full (recommended)"
      puts "  2. Essentials"
      puts "  3. Minimal"
      print "[1/2/3]: "
      choice = $stdin.gets&.strip
      @verbosity = case choice
                   when '3' then :low
                   when '2' then :medium
                   else :high
                   end
    end

    def start_server
      @server = Server.new(self)
      @server.start
    end

    def broadcast(text)
      @server&.push(text)
    end

    def repl
      puts "#{C_DIM}#{QUOTES.sample}#{C_RESET}"
      puts "#{C_DIM}Session: #{@session_name}#{C_RESET}"
      warn_missing_api_key
      puts

      # Start background processor for queued inputs
      start_queue_processor

      loop do
        prompt_text = @processing ? "#{SPINNER[0]} " : build_prompt
        input = if TTY_AVAILABLE && $stdin.tty?
          @prompt.ask(prompt_text) { |q| q.modify :strip }
        else
          Readline.readline(prompt_text, true)
        end
        break unless input

        input = input.strip
        next if input.empty?
        break if %w[exit quit q].include?(input)

        # Queue input for processing (allows typing while waiting)
        if @processing
          @input_queue << input
          puts "#{C_DIM}queued: #{input[0..40]}#{input.size > 40 ? '...' : ''}#{C_RESET}"
        else
          process_single_input(input)
        end
      end

      save_history
      save_state
      @server&.stop
      show_session_summary
    end

    def start_queue_processor
      Thread.new do
        loop do
          break if @shutdown
          unless @input_queue.empty?
            input = @input_queue.pop(true) rescue nil
            process_single_input(input) if input
          end
          sleep 0.1
        end
      end
    end

    def process_single_input(input)
      # Easter egg
      puts "#{C_DIM}#{EGGS.sample}#{C_RESET}" if rand < EASTER_EGG_CHANCE

      # Expand aliases
      input = expand_alias(input)

      start_time = Time.now
      @processing = true
      begin
        result = with_spinner { process_input(input) }
        elapsed_ms = ((Time.now - start_time) * 1000).round

        @streak += 1
        @command_count += 1
        check_achievements

        puts colorize_output(result) if result
        # Terse single-line stats (only if LLM was called)
        if @last_tokens[:input] > 0 || @last_tokens[:output] > 0
          stats = "#{C_DIM}#{elapsed_ms}ms · #{@last_tokens[:input]}→#{@last_tokens[:output]}tok"
          stats += " · cached" if @last_cached
          puts "#{stats}#{C_RESET}"
          @last_tokens = { input: 0, output: 0 }
          @last_cached = false
        end
      rescue => e
        @streak = 0
        puts "#{C_RED}#{e.message}#{C_RESET}"
      ensure
        @processing = false
      end

      auto_lint
    end

    def warn_missing_api_key
      return if @llm.status[:connected]
      puts "#{C_YELLOW}OpenRouter key missing. Set OPENROUTER_API_KEY to enable LLM responses.#{C_RESET}"
    rescue StandardError
      nil
    end

    def expand_alias(input)
      parts = input.split(' ', 2)
      cmd = parts[0]
      if @aliases[cmd]
        [@aliases[cmd], parts[1]].compact.join(' ')
      else
        input
      end
    end

    def check_achievements
      unlock(:first_command) if @command_count == 1
      unlock(:streak_5) if @streak == 5
      unlock(:streak_25) if @streak == 25
      unlock(:commands_100) if @command_count == 100
      unlock(:spent_1) if @total_cost >= 1.0 && !@achievements.include?(:spent_1)
    end

    def unlock(key)
      return if @achievements.include?(key)

      @achievements << key
      a = ACHIEVEMENTS[key]
      puts "#{C_YELLOW}★ #{a[:name]}#{C_RESET} — #{a[:desc]}"
      beep
    end

    def beep
      print "\a" # Terminal bell
    end

    def auto_lint
      return unless @verbosity == :high

      modified = `git diff --name-only 2>/dev/null`.lines.map(&:strip)
      return if modified.empty?

      modified.each do |file|
        next unless File.exist?(file)
        issues = lint_single_file(File.expand_path(file, @root))
        issues.each { |i| puts i }
      end
    rescue StandardError
      # git not available or not a repo
    end

    def show_token_info
      cached = @last_cached ? " [cached]" : ""
      puts "#{C_DIM}#{@last_tokens[:input]} tokens in, #{@last_tokens[:output]} tokens out#{cached}#{C_RESET}"
      @last_tokens = { input: 0, output: 0 }
      @last_cached = false
    end

    def show_session_summary
      duration = Time.now - @boot_time
      mins = (duration / 60).to_i
      secs = (duration % 60).to_i
      cost = @llm.total_cost
      total_in = @llm.total_tokens_in rescue 0
      total_out = @llm.total_tokens_out rescue 0
      requests = @llm.request_count rescue 0

      # Exit quotes
      exits = [
        "Until next time.",
        "Ship it.",
        "Good work.",
        "Stay sharp.",
        "Build something.",
      ]

      puts ""
      puts "#{C_DIM}#{@session_name}#{C_RESET}"
      puts "#{C_DIM}  #{mins}m #{secs}s, #{@command_count} commands, streak #{@streak}#{C_RESET}"
      puts "#{C_DIM}  #{requests} requests, #{total_in + total_out} tokens#{C_RESET}" if requests > 0
      puts "#{C_DIM}  #{colorize_cost(cost)}#{C_RESET}"
      puts ""
      puts "#{C_MINT}#{exits.sample}#{C_RESET}"
      puts ""
    end

    def colorize_cost(cost)
      formatted = "$#{'%.4f' % cost}"
      if cost < COST_TIER_LOW
        "#{C_GREEN}#{formatted}#{C_RESET}"
      elsif cost < COST_TIER_MED
        "#{C_YELLOW}#{formatted}#{C_RESET}"
      else
        "#{C_RED}#{formatted}#{C_RESET}"
      end
    end

    def colorize_output(text)
      return text unless text.is_a?(String)

      if text.start_with?('Error', 'Not found', 'Usage')
        "#{C_RED}#{text}#{C_RESET}"
      elsif text.start_with?('Switched', 'Cleaned', 'Done', 'Changed', 'Cleared')
        "#{C_GREEN}#{text}#{C_RESET}"
      else
        text
      end
    end

    def build_prompt
      # Use starship if available
      return starship_prompt if starship_available?
      
      dir = File.basename(@root)
      persona = @llm.persona&.dig(:name)
      cost = @llm.total_cost
      hist = @llm.instance_variable_get(:@history)&.size || 0
      uptime = Time.now - @boot_time

      parts = [dir]
      parts << ":#{persona}" if persona && persona != 'default'
      parts << "(#{hist})" if hist > 0
      parts << format_uptime(uptime) if uptime > UPTIME_THRESHOLD
      parts << colorize_cost_inline(cost) if cost > 0

      "#{parts.join('')} $ "
    end
    
    def starship_available?
      @starship_available ||= system('which starship > /dev/null 2>&1')
    end
    
    def starship_prompt
      # Set MASTER-specific env vars for starship to use
      ENV['MASTER_PERSONA'] = @llm.persona&.dig(:name) || 'generic'
      ENV['MASTER_COST'] = format('%.2f', @llm.total_cost)
      ENV['MASTER_HIST'] = (@llm.instance_variable_get(:@history)&.size || 0).to_s
      
      `starship prompt 2>/dev/null`.chomp
    rescue StandardError
      build_fallback_prompt
    end
    
    def build_fallback_prompt
      "#{File.basename(@root)} $ "
    end

    def format_uptime(seconds)
      hours = (seconds / UPTIME_THRESHOLD).to_i
      mins = ((seconds % UPTIME_THRESHOLD) / 60).to_i
      "#{hours}h#{mins}m"
    end

    def colorize_cost_inline(cost)
      formatted = "$#{'%.2f' % cost}"
      if cost < COST_TIER_LOW
        "#{C_GREEN}#{formatted}#{C_RESET}"
      elsif cost < COST_TIER_MED
        "#{C_YELLOW}#{formatted}#{C_RESET}"
      else
        "#{C_RED}#{formatted}#{C_RESET}"
      end
    end

    def with_spinner
      # Use TTY::Spinner if available
      if TTY_AVAILABLE
        spinner = TTY::Spinner.new("[:spinner] ", format: :dots)
        spinner.auto_spin
        result = yield
        spinner.stop
        return result
      end
      
      # Fallback to simple orb spinner
      done = false
      result = nil

      spinner = Thread.new do
        i = 0
        until done
          draw_orb(SPINNER[i % SPINNER.size])
          i += 1
          sleep 0.1
        end
        clear_orb
      end

      result = yield
      done = true
      spinner.join
      result
    end

    def terminal_cols
      IO.console&.winsize&.last || 80
    rescue StandardError
      80
    end

    def draw_orb(frame)
      print "\r#{frame} "
      $stdout.flush
    end

    def clear_orb
      print "\r  \r"
      $stdout.flush
    end

    def confirm_expensive(tier)
      return true unless tier == :premium
      info = LLM::TIERS[:premium]
      puts "#{C_YELLOW}Premium tier costs #{info[:input]}/#{info[:output]} per 1000 tokens#{C_RESET}"
      print "Continue? [y/N] "
      response = $stdin.gets&.strip&.downcase
      response == 'y' || response == 'yes'
    end

    def confirm_write(action)
      return true if ENV['MASTER_AUTO_APPROVE']
      return true unless $stdin.tty?
      print "#{action}. Continue? [y/N] "
      response = $stdin.gets&.strip&.downcase
      response == 'y' || response == 'yes'
    end

    def handle(input)
      cmd, *args = input.split(/\s+/, 2)
      cmd = ALIASES[cmd] || cmd  # Resolve aliases
      arg = args.first

      case cmd
      when 'help', '?'
        help_text

      when 'cd'
        change_dir(arg)

      when 'ls', 'tree'
        show_tree

      when 'cat', 'view', 'read'
        view_file(arg)

      when 'edit'
        edit_file(arg)

      when 'clean'
        clean_file(arg)

      when 'scan'
        scan_path(arg || '.')

      when 'smells'
        detect_smells(arg || '.')

      when 'ask', 'chat'
        chat(arg)

      when 'clear'
        @llm.clear_history
        'History cleared.'

      when 'cost'
        format('$%.6f', @llm.total_cost)

      when 'persona'
        switch_persona(arg)

      when 'personas'
        list_personas

      when 'principles'
        list_principles

      when 'converge'
        run_converge(arg || '.')

      when 'audit'
        run_audit(arg)

      when 'review'
        run_review(arg || '.')

      when 'refactor'
        run_refactor(arg)

      when 'beautify'
        beautify_file(arg)

      when 'lint'
        lint_files(arg || '.')

      when 'bughunt', 'hunt', 'debug'
        bughunt_file(arg)

      when 'web'
        browse_web(arg)

      when 'image'
        generate_image(arg)

      when 'describe'
        describe_image(arg)

      when 'speak'
        speak_text(arg)

      when 'radio'
        start_radio(arg)

      when 'version'
        "MASTER v#{VERSION}"

      when 'status'
        status_info

      when 'history'
        show_history(arg&.to_i || 20)

      when 'metrics'
        show_metrics

      when 'refine'
        run_refine(arg)

      when 'git'
        run_git(arg)

      when 'diff'
        run_git('diff')

      when 'log'
        run_git('log --oneline -20')

      when 'commit'
        run_git("commit -am \"#{arg || 'update'}\"")

      when 'pull'
        run_git('pull')

      when 'push'
        run_git('push')

      when 'chamber'
        run_chamber(arg)

      when 'queue'
        run_queue(arg)

      when 'introspect'
        run_introspect(arg)

      when 'session'
        show_session_info

      when 'newsession', 'new-session'
        new_session

      when 'sessions'
        list_sessions

      when 'self', 'selfaware', 'whoami'
        show_self_awareness

      when 'refresh-self'
        refresh_self_awareness

      when 'sanity'
        run_sanity_check(arg)

      when 'evolve'
        run_evolve(arg)

      when 'undo'
        undo_last

      when 'fav'
        add_favorite(arg)

      when 'favs'
        list_favorites

      when 'stream'
        stream_response(arg)

      when 'compare-images'
        compare_images(arg)

      when 'enforce-principles'
        enforce_principles(arg)

      when 'install-hooks'
        install_git_hooks

      when 'check-ports'
        check_port_consistency

      when 'install'
        run_install(arg)

      when 'deps'
        show_dependencies

      when 'reload'
        reload_master

      when 'resume'
        resume_session(arg)

      when 'sessions'
        list_sessions

      when 'checkpoint'
        create_checkpoint(arg)

      when /^f(\d+)$/
        run_favorite($1.to_i)

      when 'alias'
        set_alias(arg)

      when 'aliases'
        list_aliases

      when 'context'
        manage_context(arg)

      when 'backend'
        set_backend(arg)

      when 'auto', 'autonomous'
        run_autonomous(arg)

      when 'goal'
        set_goal(arg)

      when 'goals'
        list_goals

      when 'budget'
        show_budget

      when 'health'
        run_health_check

      when 'learn'
        show_learning_stats

      else
        # Default: send to LLM
        chat(input)
      end
    end

    def show_budget
      remaining = Autonomy.remaining_budget rescue 10.0
      spent = Autonomy.total_cost rescue 0.0
      limit = Autonomy.config[:budget_limit] rescue 10.0
      pct = ((spent / limit) * 100).round(1)
      
      "Budget: $#{spent.round(4)} / $#{limit} (#{pct}% used, $#{remaining.round(4)} remaining)"
    end

    def run_health_check
      checks = []
      
      # LLM connectivity
      checks << "LLM: #{@llm.status[:connected] ? '✓' : '✗'}"
      
      # Circuit breakers
      open_circuits = %i[anthropic google openai deepseek].count { |p| Autonomy.circuit_open?(p) rescue false }
      checks << "Circuits: #{open_circuits > 0 ? "#{open_circuits} open" : '✓ all closed'}"
      
      # Budget
      checks << "Budget: #{Autonomy.exceeded_budget? ? '✗ exceeded' : '✓ ok'}" rescue nil
      
      # Sessions
      sessions_dir = Paths.sessions rescue nil
      session_count = sessions_dir ? Dir.glob(File.join(sessions_dir, '*.yml')).size : 0
      checks << "Sessions: #{session_count} saved"
      
      checks.compact.join("\n")
    end

    def show_learning_stats
      stats = []
      
      # Prompt metrics
      metrics_file = File.join(Paths.var, 'prompt_metrics.yml')
      if File.exist?(metrics_file)
        metrics = YAML.load_file(metrics_file) rescue {}
        total_execs = metrics.values.sum { |m| m[:executions] || 0 }
        total_success = metrics.values.sum { |m| m[:successes] || 0 }
        rate = total_execs > 0 ? ((total_success.to_f / total_execs) * 100).round(1) : 0
        stats << "Prompts: #{total_execs} executions, #{rate}% success"
      end
      
      # Examples learned
      examples_file = File.join(Paths.var, 'few_shot_examples.yml')
      if File.exist?(examples_file)
        examples = YAML.load_file(examples_file) rescue {}
        success_count = (examples[:successes] || {}).values.flatten.size
        failure_count = (examples[:failures] || []).size
        stats << "Examples: #{success_count} successes, #{failure_count} failures learned"
      end
      
      # Skills
      skills_file = File.join(Paths.var, 'agent_skills.yml')
      if File.exist?(skills_file)
        skills = YAML.load_file(skills_file) rescue {}
        stats << "Skills: #{skills.size} acquired"
      end
      
      stats.empty? ? "No learning data yet" : stats.join("\n")
    end

    def undo_last
      result = `git checkout -- . 2>&1`
      result.empty? ? "Reverted uncommitted changes" : result
    end

    def reload_master
      port = @server&.instance_variable_get(:@port)
      
      # Git pull
      pull_result = `git pull 2>&1`.strip
      trace "git pull: #{pull_result}"
      
      return "Pull failed: #{pull_result}" unless $?.success?
      
      # Save state
      save_state
      save_history
      
      # Re-exec with same port
      ENV['MASTER_PORT'] = port.to_s if port
      ENV['MASTER_SESSION'] = @session_name
      
      trace "reloading..."
      exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
    end

    def add_favorite(cmd)
      return "Usage: fav <command>" unless cmd

      @favorites << cmd
      save_state
      "Saved: #{cmd}"
    end

    def list_favorites
      return "No favorites" if @favorites.empty?

      @favorites.each_with_index.map { |f, i| "f#{i + 1}: #{f}" }.join("\n")
    end

    def run_favorite(n)
      cmd = @favorites[n - 1]
      return "No favorite ##{n}" unless cmd

      handle(cmd)
    end

    def set_alias(arg)
      return list_aliases unless arg

      name, cmd = arg.split('=', 2)
      return "Usage: alias name=command" unless name && cmd

      @aliases[name.strip] = cmd.strip
      save_state
      "Alias: #{name} → #{cmd}"
    end

    def list_aliases
      return "No aliases" if @aliases.empty?

      @aliases.map { |k, v| "#{k} → #{v}" }.join("\n")
    end

    def resume_session(arg)
      recovery = MASTER::SessionRecovery.new
      checkpoints = recovery.list
      
      return "No sessions to resume" if checkpoints.empty?
      
      if arg
        # Resume specific checkpoint by index or task name
        idx = arg.to_i - 1
        checkpoint = checkpoints[idx] if idx >= 0 && idx < checkpoints.size
        checkpoint ||= checkpoints.find { |c| c[:task].to_s.include?(arg) }
        return "Session not found: #{arg}" unless checkpoint
      else
        checkpoint = checkpoints.first
      end
      
      restored = recovery.restore(checkpoint[:file])
      return "Failed to restore" unless restored
      
      @context = restored[:context]
      age = ((Time.now.to_i - restored[:timestamp]) / 3600.0).round(1)
      "resumed: #{restored[:task]} (#{age}h ago)"
    end

    def list_sessions
      recovery = MASTER::SessionRecovery.new
      checkpoints = recovery.list
      
      return "No saved sessions" if checkpoints.empty?
      
      lines = checkpoints.each_with_index.map do |c, i|
        age = ((Time.now.to_i - c[:timestamp]) / 3600.0).round(1)
        completed = c.dig(:files, :completed)&.size || 0
        pending = c.dig(:files, :pending)&.size || 0
        "#{i + 1}. #{c[:task]} (#{age}h) #{completed}✓ #{pending}…"
      end
      lines.join("\n")
    end

    def create_checkpoint(task)
      # Default to planner's current task or "snapshot"
      if task.nil? || task.empty?
        @planner ||= Planner.new(@llm)
        if @planner.current_plan
          current = @planner.next_task
          task = current ? current[:action] : @planner.current_plan[:goal]
        else
          task = "manual snapshot #{Time.now.strftime('%H:%M')}"
        end
      end
      
      recovery = MASTER::SessionRecovery.new
      checkpoint = recovery.checkpoint(
        task: task,
        context: { variables: @context || {} },
        instructions: ["Resume with: resume #{task.split.first}"]
      )
      
      "checkpoint: #{task}"
    end

    # Autonomous mode - MASTER continues working on goals
    GOALS_FILE = File.join(Paths.var, 'goals.yml')
    AUTO_INTERVAL = 30  # seconds between autonomous actions

    def run_autonomous(duration_arg)
      duration = (duration_arg || '10').to_i  # minutes
      end_time = Time.now + (duration * 60)
      
      # Use planner if a plan exists, otherwise check goals
      @planner ||= Planner.new(@llm)
      
      if @planner.current_plan
        run_planned_execution(end_time)
      else
        goals = load_goals
        return "No goals or plan. Use: goal <description> OR plan <goal>" if goals.empty?
        
        # Create plan from first goal
        goal = goals.first
        puts "auto: creating plan for: #{goal[:name]}"
        result = @planner.create_plan(goal[:name])
        
        return "Failed to create plan: #{result.error}" unless result.ok?
        
        puts @planner.format_plan
        run_planned_execution(end_time)
      end
    end
    
    def run_planned_execution(end_time)
      iteration = 0
      
      while Time.now < end_time
        task = @planner.next_task
        break unless task
        
        iteration += 1
        prog = @planner.progress
        
        puts "\n[#{iteration}] (#{prog[:progress]}) #{task[:action]}"
        
        result = @planner.execute_next do |action|
          process_input(action)
        end
        
        if result.ok?
          puts "  ✓ done"
        else
          puts "  ✗ #{result.error[0..60]}"
          
          # Ask if should continue or abort
          if @planner.current_plan[:status] == :blocked
            puts "  Plan blocked after #{MAX_RETRIES} retries. Skipping task."
            @planner.skip_task
          end
        end
        
        sleep AUTO_INTERVAL
      end
      
      prog = @planner.progress
      status = prog[:status] == :complete ? "complete!" : "#{prog[:progress]} tasks done"
      "auto: #{status}"
    end
    
    def create_plan(goal_description)
      # Use current goal if none provided
      if goal_description.nil? || goal_description.empty?
        goals = load_goals
        if goals.empty?
          return "No goal. Set one: goal <description>"
        end
        goal_description = goals.last[:name]
        puts "Planning for: #{goal_description}"
      end
      
      @planner ||= Planner.new(@llm)
      result = @planner.create_plan(goal_description)
      
      return "Failed: #{result.error}" unless result.ok?
      
      @planner.format_plan
    end
    
    def show_plan
      @planner ||= Planner.new(@llm)
      @planner.format_plan
    end
    
    def run_next_task
      @planner ||= Planner.new(@llm)
      
      task = @planner.next_task
      return "No tasks remaining" unless task
      
      puts "Running: #{task[:action]}"
      
      result = @planner.execute_next do |action|
        process_input(action)
      end
      
      if result.ok?
        prog = @planner.progress
        "✓ Done (#{prog[:progress]})"
      else
        "✗ Failed: #{result.error}"
      end
    end
    
    def skip_current_task
      @planner ||= Planner.new(@llm)
      result = @planner.skip_task
      result.ok? ? result.value : result.error
    end
    
    def clear_current_plan
      @planner ||= Planner.new(@llm)
      @planner.clear_plan
      "Plan cleared"
    end

    def set_goal(description)
      return "Usage: goal <description>" unless description
      
      goals = load_goals
      goal = {
        id: SecureRandom.hex(4),
        name: description,
        created: Time.now.to_i,
        progress: []
      }
      goals << goal
      save_goals(goals)
      
      "goal set: #{description}"
    end

    def list_goals
      goals = load_goals
      return "No goals. Use: goal <description>" if goals.empty?
      
      goals.map.with_index do |g, i|
        age = ((Time.now.to_i - g[:created]) / 3600.0).round(1)
        progress = g[:progress]&.size || 0
        "#{i + 1}. #{g[:name]} (#{age}h, #{progress} steps)"
      end.join("\n")
    end

    def load_goals
      return [] unless File.exist?(GOALS_FILE)
      YAML.load_file(GOALS_FILE) rescue []
    end

    def save_goals(goals)
      FileUtils.mkdir_p(File.dirname(GOALS_FILE))
      File.write(GOALS_FILE, goals.to_yaml)
    end

    def help_text
      <<~HELP
        #{C_BOLD}Core#{C_RESET}
          ask, a        #{C_DIM}Chat with LLM#{C_RESET}
          clear, cl     #{C_DIM}Reset context#{C_RESET}
          status, st    #{C_DIM}Show state#{C_RESET}
          history, hi   #{C_DIM}Past commands#{C_RESET}
          metrics       #{C_DIM}Session stats#{C_RESET}
          exit, quit    #{C_DIM}Leave#{C_RESET}

        #{C_BOLD}Files#{C_RESET} #{C_DIM}(defaults to last used)#{C_RESET}
          ls, tree      #{C_DIM}List files#{C_RESET}
          cat [file]    #{C_DIM}View file#{C_RESET}
          edit [file]   #{C_DIM}Modify file#{C_RESET}
          diff, d       #{C_DIM}Show changes#{C_RESET}
          cd [path]     #{C_DIM}Change dir (default: ~)#{C_RESET}

        #{C_BOLD}Code#{C_RESET} #{C_DIM}(defaults to last file/dir)#{C_RESET}
          scan [path]   #{C_DIM}Find issues#{C_RESET}
          smells        #{C_DIM}Detect rot#{C_RESET}
          refactor [path] #{C_DIM}Auto-fix#{C_RESET}
          lint          #{C_DIM}Check style#{C_RESET}
          beautify [file] #{C_DIM}Format#{C_RESET}
          bughunt [file] #{C_DIM}8-phase debug#{C_RESET}

        #{C_BOLD}AI#{C_RESET}
          chamber [file] #{C_DIM}Multi-model deliberation#{C_RESET}
          queue, q      #{C_DIM}Batch process#{C_RESET}
          evolve, e     #{C_DIM}Self-improve#{C_RESET}
          introspect, i #{C_DIM}Self-check#{C_RESET}
          converge      #{C_DIM}Loop stable#{C_RESET}
          backend       #{C_DIM}Switch LLM#{C_RESET}
          context       #{C_DIM}Manage files#{C_RESET}

        #{C_BOLD}Git#{C_RESET}
          log, l        #{C_DIM}History#{C_RESET}
          commit        #{C_DIM}Save#{C_RESET}
          push/pull     #{C_DIM}Sync#{C_RESET}

        #{C_BOLD}Media#{C_RESET}
          image         #{C_DIM}Generate#{C_RESET}
          describe      #{C_DIM}Vision#{C_RESET}
          speak         #{C_DIM}TTS#{C_RESET}

        #{C_BOLD}Sessions#{C_RESET}
          session       #{C_DIM}Show current#{C_RESET}
          newsession    #{C_DIM}Start fresh#{C_RESET}
          sessions      #{C_DIM}List all#{C_RESET}
          resume        #{C_DIM}Restore#{C_RESET}
          checkpoint    #{C_DIM}Save state (auto-names)#{C_RESET}

        #{C_BOLD}Autonomous#{C_RESET}
          auto [mins]   #{C_DIM}Run autonomously (default: 10)#{C_RESET}
          goal <desc>   #{C_DIM}Set persistent goal#{C_RESET}
          goals         #{C_DIM}List active goals#{C_RESET}
          plan [goal]   #{C_DIM}Break into tasks (uses current goal)#{C_RESET}
          next          #{C_DIM}Run next task#{C_RESET}
          show-plan     #{C_DIM}View current plan#{C_RESET}
          budget        #{C_DIM}Show remaining budget#{C_RESET}
          health        #{C_DIM}System health check#{C_RESET}
          learn         #{C_DIM}Learning statistics#{C_RESET}
          
        #{C_BOLD}Self-Awareness#{C_RESET}
          self, whoami  #{C_DIM}Show codebase knowledge#{C_RESET}
          refresh-self  #{C_DIM}Rescan MASTER code#{C_RESET}
      HELP
    end

    def change_dir(path)
      path = path&.strip
      path = '~' if path.nil? || path.empty?  # default to home

      full = File.expand_path(path, @root)
      if Dir.exist?(full)
        @root = full
        Dir.chdir(full)
        remember_dir(full)
        "Changed to #{full}"
      else
        "Not found: #{path}"
      end
    end

    def show_tree
      ignore = %w[. .. .git node_modules vendor tmp .bundle]
      files = []

      Dir.glob(File.join(@root, '**', '*'), File::FNM_DOTMATCH).each do |path|
        next if ignore.any? { |i| path.include?("/#{i}/") || path.end_with?("/#{i}") }
        next if File.basename(path).start_with?('.')
        next unless File.file?(path)

        files << path.sub(@root + '/', '')
      end

      files.sort.join("\n")
    end

    def view_file(path)
      path = default_file(path)
      return 'No file. Usage: cat <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      remember_file(full)
      File.read(full)
    end

    def edit_file(path)
      path = default_file(path)
      return 'No file. Usage: edit <file>' unless path

      full = File.expand_path(path, @root)
      remember_file(full)
      editor = ENV['EDITOR'] || 'vi'
      system("#{editor} #{full}")
      'Done.'
    end

    def clean_file(path)
      path = default_file(path)
      return 'No file. Usage: clean <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)
      return 'Cancelled.' unless confirm_write("This will reformat #{path}")

      remember_file(full)
      content = File.read(full)
      original = content.dup

      # CRLF -> LF
      content.gsub!("\r\n", "\n")
      # Trailing whitespace
      content.gsub!(/[ \t]+$/, '')
      # Multiple blank lines -> single
      content.gsub!(/\n{3,}/, "\n\n")
      # Ensure final newline
      content << "\n" unless content.end_with?("\n")

      if content != original
        File.write(full, content)
        'Cleaned.'
      else
        'Already clean.'
      end
    end

    def scan_path(path)
      path = default_target(path)
      remember_file(path) if File.file?(path)
      remember_dir(path) if File.directory?(path)
      
      result = Engine.scan(File.expand_path(path, @root))
      return result.error if result.err?

      issues = result.value
      return 'No issues found.' if issues.empty?

      issues.map { |i| "#{i[:file]}: #{i[:type]} (#{i[:lines] || i[:message]})" }.join("\n")
    end

    def detect_smells(path)
      scan_path(path)
    end

    def chat(message)
      return 'Usage: ask <message>' unless message

      # Inject filesystem context for paths mentioned in message
      message = inject_path_context(message)

      result = @llm.chat(message)
      @last_tokens = @llm.last_tokens
      @last_cached = @llm.last_cached
      
      return "Error: #{result.error}" unless result.ok?
      
      response = result.value
      
      # Execute any code blocks in response
      exec_results = Executor.process_response(response)
      if exec_results.any? && exec_results.any? { |r| r[:success] == false }
        formatted = Executor.format_results(exec_results)
        followup = @llm.chat("Execution results:\n#{formatted}\n\nFix errors. Reply with terse result only.")
        response = followup.value if followup.ok?
      end
      
      # Strip markdown fluff from conversational responses (not code)
      has_code_request = message.match?(/refactor|edit|fix|write|create|show.*code|diff/i)
      has_code_request ? response : clean_response(response)
    end
    
    def clean_response(text)
      # Keep code blocks if they look intentional (user asked for code)
      return render_markdown(text) if text.scan(/```/).size >= 2 && text.match?(/def |class |function |const |import /)
      
      # Render markdown to ANSI for terminal display
      render_markdown(text)
    end
    
    # Convert markdown to ANSI terminal codes
    def render_markdown(text)
      out = text.dup
      
      # Code blocks: dim grey background effect
      out.gsub!(/```(\w*)\n(.*?)```/m) { "#{C_DIM}#{$2.strip}#{C_RESET}" }
      
      # Headers: bold cyan (# ## ###)
      out.gsub!(/^#+ +(.+)$/) { "#{C_BOLD}#{C_CYAN}#{$1}#{C_RESET}" }
      
      # Bold: actual bold
      out.gsub!(/\*\*(.+?)\*\*/) { "#{C_BOLD}#{$1}#{C_RESET}#{C_GREY}" }
      
      # Italic: actual italic
      out.gsub!(/\*(.+?)\*/) { "#{C_ITALIC}#{$1}#{C_RESET}#{C_GREY}" }
      out.gsub!(/_(.+?)_/) { "#{C_ITALIC}#{$1}#{C_RESET}#{C_GREY}" }
      
      # Inline code: dim
      out.gsub!(/`([^`]+)`/) { "#{C_DIM}#{$1}#{C_RESET}#{C_GREY}" }
      
      # Links: just the text, cyan
      out.gsub!(/\[([^\]]+)\]\([^)]+\)/) { "#{C_CYAN}#{$1}#{C_RESET}#{C_GREY}" }
      
      # Bullets: grey dot
      out.gsub!(/^(\s*)[-*]\s+/) { "#{$1}#{C_DIM}·#{C_RESET} " }
      
      # Numbered lists: keep numbers, dim
      out.gsub!(/^(\s*)(\d+)\.\s+/) { "#{$1}#{C_DIM}#{$2}.#{C_RESET} " }
      
      # Collapse excessive whitespace
      out.gsub!(/\n{3,}/, "\n\n")
      
      # Wrap in grey for calmer appearance
      "#{C_GREY}#{out.strip}#{C_RESET}"
    end

    # Inject actual filesystem context when paths are mentioned
    def inject_path_context(message)
      # Find paths in message (Unix-style)
      paths = message.scan(%r{(?:/[\w./-]+)+}).uniq
      return message if paths.empty?

      context_lines = []
      paths.each do |path|
        if File.exist?(path)
          if File.directory?(path)
            entries = Dir.children(path).first(20)
            context_lines << "[PATH EXISTS] #{path}/ contains: #{entries.join(', ')}"
          else
            size = File.size(path)
            context_lines << "[FILE EXISTS] #{path} (#{size} bytes)"
          end
        else
          context_lines << "[PATH MISSING] #{path} does not exist"
        end
      end

      return message if context_lines.empty?

      "[Filesystem context:\n#{context_lines.join("\n")}]\n\n#{message}"
    end

    def switch_persona(name)
      return "Available: #{Persona.list.join(', ')}" unless name

      trace "persona: #{name}"
      result = @llm.switch_persona(name)
      result.ok? ? "Switched to #{name}" : result.error
    end

    def switch_tier(name)
      return "Current tier: #{@llm.current_tier}" unless name
      key = name.to_sym
      return "Unknown tier: #{name}" unless LLM::TIERS.key?(key)
      @llm.set_tier(key)
      MASTER::Boot.save_preferred_model(key) unless ENV['MASTER_NO_CONFIG_WRITE']
      "Tier set to #{key}"
    end

    def list_personas
      Persona.list.join("\n")
    end

    def list_principles
      Principle.load_all.map { |p| "#{p[:filename]}: #{p[:name]}" }.join("\n")
    end

    def browse_web(url)
      return 'Usage: web <url>' unless url

      begin
        require_relative 'web'
        Web.browse(url)
      rescue LoadError
        'Web module not available'
      end
    end

    def generate_image(prompt)
      return 'Usage: image <prompt>' unless prompt

      begin
        require_relative 'replicate'
        Replicate.generate_image(prompt)
      rescue LoadError
        'Replicate module not available'
      end
    end

    def describe_image(path)
      return 'Usage: describe <image>' unless path

      begin
        require_relative 'replicate'
        Replicate.describe_image(File.expand_path(path, @root))
      rescue LoadError
        'Replicate module not available'
      end
    end

    def run_converge(path)
      require_relative 'converge'

      puts "#{C_CYAN}Starting convergence...#{C_RESET}"
      result = Converge.run(path) do |iteration, issues|
        puts "#{C_DIM}Iteration #{iteration}: #{issues.size} issues#{C_RESET}"
      end

      if result.ok?
        data = result.value
        "#{C_GREEN}Converged#{C_RESET} in #{data[:iterations]} iterations (#{data[:final_issues]} issues)"
      else
        "#{C_RED}#{result.error}#{C_RESET}"
      end
    end

    def run_audit(ref)
      require_relative 'converge'

      ref ||= 'HEAD~10'
      audit = Converge.audit(@root, ref)

      lines = []
      lines << "Comparing current vs #{ref}"
      lines << "Current: #{audit[:current_count]} features"
      lines << "Historical: #{audit[:historical_count]} features"
      lines << "Coverage: #{(audit[:coverage] * 100).round(1)}%"

      if audit[:missing].any?
        lines << ""
        lines << "#{C_RED}Missing (#{audit[:missing].size}):#{C_RESET}"
        audit[:missing].first(10).each { |f| lines << "  - #{f}" }
        lines << "  ..." if audit[:missing].size > 10
      end

      if audit[:added].any?
        lines << ""
        lines << "#{C_GREEN}Added (#{audit[:added].size}):#{C_RESET}"
        audit[:added].first(10).each { |f| lines << "  + #{f}" }
        lines << "  ..." if audit[:added].size > 10
      end

      lines.join("\n")
    end

    def run_review(path)
      begin
        require_relative 'agents/review_crew'

        crew = MASTER::Agents::ReviewCrew.new(llm: @llm, principles: Principle.load_all)
        files = resolve_files(path)
        return "No files found: #{path}" if files.empty?

        total_findings = 0
        reviewed = 0
        skipped = 0

        files.each do |file|
          begin
            code = File.read(file)
            results = crew.review(code, file)
            total_findings += results[:summary][:total_findings]
            reviewed += 1
          rescue StandardError => e
            skipped += 1
            warn "Warning: review skipped #{file}: #{e.message}"
          end
        end

        suffix = skipped.positive? ? " (#{skipped} skipped)" : ""
        if reviewed > 1
          "#{C_CYAN}Review complete:#{C_RESET} #{total_findings} findings across #{reviewed} files#{suffix}"
        else
          "#{C_CYAN}Review complete:#{C_RESET} #{total_findings} findings#{suffix}"
        end
      rescue LoadError, StandardError => e
        "Review agents not available: #{e.message}"
      end
    end

    def run_refactor(path)
      path = default_target(path)
      return 'No target. Usage: refactor <file|dir>' unless path

      files = resolve_files(path)
      return "No files found: #{path}" if files.empty?
      
      remember_file(files.first) if files.size == 1
      trace "refactoring #{files.size} files"
      return 'Cancelled.' unless confirm_write("This will refactor #{files.size} file(s) using LLM suggestions")
      total_iterations = 0
      total_changes = 0

      files.each do |file|
        result = refactor_file(file)
        total_iterations += result[:iterations]
        total_changes += result[:changes]
      end

      "#{C_GREEN}Refactored#{C_RESET} #{files.size} file(s): #{total_changes} changes in #{total_iterations} iterations"
    end

    def refactor_file(file)
      trace "analyzing: #{file}"

      # Phase 1: Research - understand the domain
      code = File.read(file)
      ext = File.extname(file)
      lang = detect_language(ext)

      research_prompt = <<~PROMPT
        Analyze this #{lang} code and identify:
        1. What libraries/frameworks it uses
        2. Best practices that should apply
        3. Common patterns in this domain
        4. Potential improvements

        Be concise. Return as bullet points.

        ```#{lang}
        #{code[0..MAX_CODE_PREVIEW]}
        ```
      PROMPT

      trace "phase 1: research"
      research = with_spinner("Researching") { @llm.chat(research_prompt, tier: :fast) }
      research_text = research.ok? ? research.value : ""

      # Phase 2: Iterate until convergence
      max_iterations = 5
      min_change_threshold = 0.02
      iteration = 0
      prev_code = code
      changes = 0

      loop do
        iteration += 1
        break if iteration > max_iterations

        trace "phase 2: iteration #{iteration}"

        refactor_prompt = <<~PROMPT
          You are refactoring #{lang} code. Apply these insights:
          #{research_text[0..MAX_RESEARCH_PREVIEW]}

          Rules:
          - Make minimal, surgical changes
          - Preserve all functionality
          - Improve clarity, not just style
          - Return ONLY the refactored code, no explanation

          ```#{lang}
          #{prev_code}
          ```
        PROMPT

        result = with_spinner("Iteration #{iteration}") { @llm.chat(refactor_prompt, tier: :code) }
        break unless result.ok?

        new_code = extract_code(result.value, lang)
        break if new_code.nil? || new_code.empty?

        # Calculate change ratio
        ratio = change_ratio(prev_code, new_code)
        trace "change: #{(ratio * 100).round(1)}%"

        if ratio < min_change_threshold
          trace "converged"
          break
        end

        changes += 1
        prev_code = new_code
      end

      # Write final result if changed
      if prev_code != code
        File.write(file, prev_code)
        info "Wrote: #{file}"
      end

      { iterations: iteration, changes: changes }
    end

    def resolve_files(path)
      full = File.expand_path(path, @root)

      if File.file?(full)
        [full]
      elsif Dir.exist?(full)
        Dir.glob(File.join(full, '**', '*.{rb,py,js,ts,go,rs}')).reject { |f| f.include?('/vendor/') || f.include?('/node_modules/') }
      else
        Dir.glob(File.join(@root, path))
      end
    end

    def detect_language(ext)
      {
        '.rb' => 'ruby', '.py' => 'python', '.js' => 'javascript',
        '.ts' => 'typescript', '.go' => 'go', '.rs' => 'rust',
        '.sh' => 'zsh', '.zsh' => 'zsh', '.yml' => 'yaml', '.yaml' => 'yaml',
        '.html' => 'html', '.erb' => 'erb', '.css' => 'css', '.scss' => 'scss'
      }[ext] || 'text'
    end

    BEAUTIFY_GUIDES = {
      'ruby' => <<~GUIDE,
        Follow these Ruby style principles:
        - Short methods (under 10 lines ideal)
        - Meaningful variable names, no abbreviations
        - Use guard clauses instead of nested conditionals
        - Prefer each/map/select over for loops
        - Use symbols for hash keys
        - Align hash rockets or use new syntax consistently
        - Remove unnecessary parentheses
        - Use string interpolation over concatenation
        - Apply Sandi Metz rules (5 lines per method, 100 chars per line)
      GUIDE
      'html' => <<~GUIDE,
        Follow semantic HTML principles:
        - Eliminate divitis: use semantic tags (article, section, nav, header, footer, main, aside)
        - Use proper heading hierarchy (h1 -> h2 -> h3)
        - Lists for navigation (ul/li for menus)
        - figure/figcaption for images with captions
        - Use button for actions, a for navigation
        - Minimal classes, prefer semantic structure
        - No inline styles
        - Accessible: alt text, aria labels where needed
      GUIDE
      'css' => <<~GUIDE,
        Follow modern CSS principles:
        - Use CSS Grid for 2D layouts, Flexbox for 1D
        - CSS custom properties (variables) for colors and spacing
        - Mobile-first: min-width media queries
        - Logical properties (margin-inline, padding-block)
        - Use clamp() for responsive typography
        - Prefer rem/em over px
        - Minimal specificity, avoid !important
        - Group related properties
        - Use modern selectors (:is, :where, :has)
      GUIDE
      'scss' => <<~GUIDE,
        Follow SCSS best practices:
        - Shallow nesting (max 3 levels)
        - Use variables for colors, spacing, breakpoints
        - Mixins for repeated patterns
        - Placeholder selectors for extends
        - BEM or similar naming when classes needed
        - Separate concerns: variables, mixins, base, components
      GUIDE
      'erb' => <<~GUIDE,
        Follow ERB best practices:
        - Minimal logic in templates
        - Use partials for reusable components
        - Semantic HTML structure
        - Escape output by default
        - Use content_for for yield blocks
        - Keep helpers in helper files, not inline
      GUIDE
      'javascript' => <<~GUIDE,
        Follow modern JavaScript principles:
        - Use const by default, let when needed, never var
        - Arrow functions for callbacks
        - Template literals over concatenation
        - Destructuring for objects and arrays
        - Spread operator over Object.assign
        - Async/await over promise chains
        - Short-circuit evaluation
        - Optional chaining (?.) and nullish coalescing (??)
        - Named exports over default
      GUIDE
      'zsh' => <<~GUIDE
        Follow shell scripting best practices:
        - Quote variables: "$var" not $var
        - Use [[ ]] over [ ]
        - Functions for reusable logic
        - Meaningful variable names
        - Error handling with set -e or explicit checks
        - Use $() over backticks
        - Local variables in functions
        - Comments for non-obvious logic
      GUIDE
    }.freeze

    def beautify_file(path)
      path = default_file(path)
      return "No file. Usage: beautify <file>" unless path

      file = File.expand_path(path, @root)
      return "File not found: #{path}" unless File.exist?(file)

      remember_file(file)
      code = File.read(file)
      ext = File.extname(file)
      lang = detect_language(ext)
      guide = BEAUTIFY_GUIDES[lang] || ""

      prompt = <<~PROMPT
        Beautify this #{lang} code completely.

        #{guide}

        Reflow rules:
        - Order everything by importance: constants, public API, then internals
        - Most critical code at top, utilities at bottom
        - Group related logic together

        Comment rules:
        - Delete ALL existing comments first
        - Reassess each line: if not self-documenting, rewrite the code to be clearer
        - Only add comments when code truly cannot express intent
        - Comments must be Strunk & White style: brevity plus clarity
        - Maximum information density, no filler words
        - No ASCII art, no decorative lines, no banners

        Naming rules:
        - Reassess every name: variables, functions, classes, constants
        - Names must be self-documenting, no abbreviations
        - Rename anything unclear to express intent precisely
        - Prefer verbs for functions, nouns for variables
        - Boolean variables: use is_, has_, can_, should_ prefixes
        - Collections: use plural nouns
        - Single-letter variables only for trivial iterators (i, j, k)

        Output rules:
        - Preserve all functionality exactly
        - Return ONLY the beautified code
        - No markdown fences, no explanation

        #{code}
      PROMPT

      result = with_spinner { @llm.chat(prompt, tier: :code) }
      return result.error if result.error?

      new_code = extract_code(result.value, lang)
      if new_code && !new_code.empty? && new_code != code
        File.write(file, new_code)
        "Beautified: #{path} (#{lang})"
      else
        "No changes needed"
      end
    end

    def lint_files(path)
      files = resolve_beautify_files(path)
      return "No supported files found" if files.empty?

      warnings = []
      files.each do |file|
        issues = lint_single_file(file)
        warnings.concat(issues) if issues.any?
      end

      if warnings.empty?
        "All #{files.size} files pass style checks"
      else
        warnings.join("\n")
      end
    end

    def bughunt_file(path)
      path = default_file(path)
      return "No file. Usage: bughunt <file>" unless path

      full = File.expand_path(path, @root)
      return "File not found: #{path}" unless File.exist?(full)

      remember_file(full)
      code = File.read(full)
      report = BugHunting.analyze(code, file_path: full)
      BugHunting.format(report)
    end

    def resolve_beautify_files(path)
      full = File.expand_path(path, @root)
      exts = %w[.rb .js .ts .html .erb .css .scss .zsh .sh]

      if File.file?(full)
        [full]
      elsif Dir.exist?(full)
        Dir.glob(File.join(full, '**', '*')).select do |f|
          File.file?(f) && exts.include?(File.extname(f)) &&
            !f.include?('/vendor/') && !f.include?('/node_modules/')
        end
      else
        []
      end
    end

    def lint_single_file(file)
      issues = []
      code = File.read(file)
      ext = File.extname(file)
      lang = detect_language(ext)
      rel = file.sub("#{@root}/", '')

      case lang
      when 'html'
        div_count = code.scan(/<div/).size
        semantic_count = code.scan(/<(article|section|nav|header|footer|main|aside)/).size
        if div_count > 5 && semantic_count < div_count / 3
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: divitis detected (#{div_count} divs, #{semantic_count} semantic tags)"
        end
        if code.include?('style=')
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: inline styles found"
        end

      when 'css', 'scss'
        if code.scan(/!important/).size > 2
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: excessive !important usage"
        end
        if code.scan(/px/).size > 10 && code.scan(/rem|em/).size < 3
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: prefer rem/em over px"
        end

      when 'ruby'
        long_methods = code.scan(/^\s*def \w+.*?^\s*end/m).select { |m| m.lines.size > 20 }
        if long_methods.any?
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: #{long_methods.size} methods exceed 20 lines"
        end
        if code =~ /\bfor\b.*\bdo\b/
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: use each/map instead of for loops"
        end

      when 'javascript'
        if code.include?('var ')
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: use const/let instead of var"
        end
        if code.scan(/\.then\(/).size > 3
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: prefer async/await over promise chains"
        end

      when 'zsh'
        # Check for bash-isms that should use zsh native patterns
        if code =~ /\|\s*(awk|sed|tr|grep)\s/
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: prefer zsh parameter expansion over #{$1}"
        end
        if code =~ /\$\w+[^"]/
          issues << "#{C_YELLOW}#{rel}#{C_RESET}: unquoted variables detected"
        end
      end

      issues
    end

    def extract_code(response, lang)
      # Extract code block from LLM response
      if response =~ /```#{lang}\s*(.*?)```/m
        $1.strip
      elsif response =~ /```\s*(.*?)```/m
        $1.strip
      else
        response.strip
      end
    end

    def change_ratio(old_code, new_code)
      return 0.0 if old_code == new_code
      return 1.0 if old_code.empty?

      # Simple line-based diff ratio
      old_lines = old_code.lines
      new_lines = new_code.lines

      common = old_lines & new_lines
      total = [old_lines.size, new_lines.size].max

      1.0 - (common.size.to_f / total)
    end

    def run_optimize(target = nil)
      target ||= 'lib'
      files = resolve_files(target)
      return "No files found: #{target}" if files.empty?

      simulate = ENV['MASTER_SIMULATE_OPTIMIZE'] || !@llm.status[:connected]
      llm_for_conceptual = simulate ? SimulatedLLM.new : @llm
      fixed_files = 0
      violation_count = 0

      files.each do |file|
        code = File.read(file)
        normalized = normalize_content(code)
        analysis = Violations.analyze(code, path: file, llm: llm_for_conceptual, conceptual: true)
        violations = (analysis[:literal] || []) + (analysis[:conceptual] || [])
        needs_fix = normalized != code || violations.any?
        next unless needs_fix

        violation_count += violations.size
        violation_count += 1 if normalized != code && violations.empty?
        updated = autofix_code(normalized, file, violations, simulate: simulate)
        next if updated == code

        File.write(file, updated)
        fixed_files += 1
      end

      note = simulate ? ' (simulated LLM pass)' : ''
      "Self-optimization complete: scanned #{files.size}, fixed #{fixed_files}, violations #{violation_count}#{note}"
    end

    def run_refine(target = nil)
      target ||= 'lib'
      files = resolve_files(target)
      return "No files found: #{target}" if files.empty?

      prompt = <<~PROMPT
        Analyze this codebase and suggest 20 micro-refinements.
        Each refinement must be:
        - Minimal (1-3 lines changed)
        - High impact (UX, performance, clarity)
        - Specific (exact file, line, change)

        Format each as:
        [N] file:line - description
        OLD: exact code
        NEW: exact code

        Files:
        #{files.map { |f| "--- #{f} ---\n#{File.read(f)}" }.join("\n\n")}
      PROMPT

      result = with_spinner { @llm.chat(prompt, tier: :strong) }
      return result.error if result.err?

      suggestions = parse_refinements(result.value)
      return "No refinements found" if suggestions.empty?

      puts "\n#{suggestions.size} refinements suggested:\n\n"
      suggestions.each_with_index do |s, i|
        puts "[#{i + 1}] #{s[:file]}:#{s[:line]} - #{s[:desc]}"
      end

      puts "\nApply which? (1,3,5 or 'all' or 'none'): "
      choice = Readline.readline('', false)&.strip

      return "Cancelled" if choice.nil? || choice == 'none' || choice.empty?

      indices = if choice == 'all'
        (0...suggestions.size).to_a
      else
        choice.split(/[,\s]+/).map { |n| n.to_i - 1 }.select { |i| i >= 0 && i < suggestions.size }
      end

      applied = 0
      indices.each do |i|
        s = suggestions[i]
        if apply_refinement(s)
          applied += 1
          puts "+ #{s[:desc]}"
        end
      end

      "Applied #{applied}/#{indices.size} refinements"
    end

    def autofix_code(code, file, violations, simulate:)
      return normalize_content(code) if simulate

      lang = detect_language(File.extname(file))
      formatted = format_violations(violations)
      prompt = <<~PROMPT
        You are running a self-optimization pass to fix principle violations.
        Fix every issue listed below with minimal, correct changes.
        Return the full updated file content only. No markdown, no commentary.

        Violations:
        #{formatted}

        CODE:
        ```#{lang}
        #{code}
        ```
      PROMPT

      result = @llm.chat(prompt, tier: :code)
      return normalize_content(code) if result.err?

      updated = extract_code(result.value, lang)
      updated.empty? ? normalize_content(code) : normalize_content(updated)
    end

    def normalize_content(content)
      text = content.dup
      text.gsub!("\r\n", "\n")
      text = text.lines.map(&:rstrip).join("\n")
      text.gsub!(/\n{3,}/, "\n\n")
      text << "\n" unless text.end_with?("\n")
      text
    end

    def format_violations(violations)
      violations.map do |v|
        if v[:type] == :conceptual
          "#{v[:principle]}: #{v[:analysis].to_s[0..MAX_VIOLATION_PREVIEW]}"
        else
          "#{v[:principle]}: #{v[:message]} (line #{v[:line]})"
        end
      end.join("\n")
    end

    def parse_refinements(text)
      refinements = []
      current = nil

      text.lines.each do |line|
        if line =~ /^\[(\d+)\]\s*(\S+):(\d+)\s*-\s*(.+)/
          refinements << current if current
          current = { num: $1.to_i, file: $2, line: $3.to_i, desc: $4.strip, old: '', new: '' }
        elsif current
          if line =~ /^OLD:\s*(.*)/ || line =~ /^old:\s*(.*)/
            current[:old] = $1.strip
          elsif line =~ /^NEW:\s*(.*)/ || line =~ /^new:\s*(.*)/
            current[:new] = $1.strip
          end
        end
      end
      refinements << current if current
      refinements.compact
    end

    def apply_refinement(ref)
      file = File.expand_path(ref[:file], @root)
      return false unless File.exist?(file)

      content = File.read(file)
      return false if ref[:old].empty? || ref[:new].empty?
      return false unless content.include?(ref[:old])

      new_content = content.sub(ref[:old], ref[:new])
      File.write(file, new_content)
      true
    rescue StandardError
      false
    end

    def status_info
      llm_status = @llm.status rescue {}
      session = @llm.session_info rescue {}
      model = llm_status[:model] ? "#{llm_status[:tier]} (#{llm_status[:model]})" : 'unknown'
      cached = llm_status[:last_cached] ? 'yes' : 'no'
      tokens = llm_status[:last_tokens] || {}
      <<~STATUS
        MASTER v#{VERSION}
        Session: #{session[:name] || 'unknown'} (#{session[:messages] || 0} messages)
        Root: #{@root}
        Persona: #{@llm.persona&.dig(:name) || 'default'}
        Model: #{model}
        Last tokens: #{tokens[:input] || 0} in, #{tokens[:output] || 0} out (cached: #{cached})
        Cost: $#{format('%.6f', @llm.total_cost)}
        Server: #{@server&.url || 'stopped'}
        Backend: #{@llm.backend}
        Context files: #{@llm.context_files.size}
      STATUS
    end

    def show_session_info
      info = @llm.session_info rescue {}
      started = info[:started] ? info[:started].strftime('%Y-%m-%d %H:%M') : 'unknown'
      summary = info[:summary] ? "\nSummary: #{info[:summary]}" : ''
      <<~SESSION
        Session: #{info[:name] || 'unknown'}
        ID: #{info[:id] || 'none'}
        Started: #{started}
        Messages: #{info[:messages] || 0}#{summary}
      SESSION
    end

    def new_session
      @llm.new_session!
      info = @llm.session_info
      "New session: #{info[:name]}"
    end

    def list_sessions
      session_dir = File.join(@root, 'var')
      return 'No sessions' unless File.directory?(session_dir)
      
      # Current session
      current = @llm.session_info rescue {}
      output = ["Current: #{current[:name]} (#{current[:messages]} messages)"]
      
      # Check for archived sessions
      archives = Dir.glob(File.join(session_dir, 'sessions', '*.json'))
      if archives.any?
        output << "\nArchived sessions:"
        archives.last(10).each do |f|
          data = JSON.parse(File.read(f), symbolize_names: true) rescue next
          output << "  #{data[:name]} - #{data[:message_count]} msgs (#{Time.at(data[:last_active]).strftime('%m/%d')})"
        end
      end
      
      output.join("\n")
    end

    def show_self_awareness
      SelfAwareness.summary
    end

    def refresh_self_awareness
      SelfAwareness.refresh!
      load_self_awareness
      "Self-awareness refreshed. #{SelfAwareness.load[:file_count]} files analyzed."
    end

    def manage_context(arg)
      return context_list if arg.nil? || arg.empty?
      action, value = arg.split(/\s+/, 2)
      case action
      when 'add'
        context_add(value)
      when 'drop'
        context_drop(value)
      when 'clear'
        context_clear
      when 'list'
        context_list
      else
        'Usage: context add <file...> | context drop <file...> | context clear | context list'
      end
    end

    def context_add(path)
      return 'Usage: context add <file>' unless path
      paths = Shellwords.split(path)
      messages = paths.map do |item|
        full = File.expand_path(item, @root)
        result = @llm.add_context_file(full)
        result.ok? ? "Context added: #{full}" : result.error
      end
      messages.join("\n")
    end

    def context_drop(path)
      return 'Usage: context drop <file>' unless path
      paths = Shellwords.split(path)
      messages = paths.map do |item|
        full = File.expand_path(item, @root)
        result = @llm.drop_context_file(full)
        result.ok? ? "Context removed: #{full}" : result.error
      end
      messages.join("\n")
    end

    def context_clear
      @llm.clear_context_files
      'Context cleared'
    end

    def context_list
      files = @llm.context_files
      return 'Context empty' if files.empty?
      files.join("\n")
    end

    def set_backend(arg)
      return "Usage: backend <#{LLM::BACKENDS.join('|')}>" unless arg
      result = @llm.set_backend(arg)
      result.ok? ? "Backend: #{result.value}" : result.error
    end

    def run_git(args)
      return 'Usage: git <command>' unless args
      `git --no-pager #{args} 2>&1`.strip
    end

    def run_chamber(path)
      path = default_file(path)
      return 'No file. Usage: chamber <file>' unless path

      require_relative 'chamber'
      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      remember_file(full)
      puts "#{C_CYAN}Chamber deliberation starting...#{C_RESET}"
      chamber = Chamber.new(@llm)
      result = chamber.deliberate(full)

      if result[:applied]
        puts "#{C_GREEN}Winner: #{result[:winner][:model]}#{C_RESET}"
        puts result[:reason][0..MAX_REASON_PREVIEW]
        "#{result[:proposals].size} models deliberated"
      else
        "Chamber complete (no changes): #{result[:reason]}"
      end
    rescue LoadError, StandardError => e
      "Chamber error: #{e.message}"
    end

    def run_queue(arg)
      require_relative 'queue'

      if arg.nil? || arg.empty?
        # Show queue status
        queue = RefactorQueue.load
        return "Queue empty" if queue.empty?

        lines = ["Queue: #{queue.size} files"]
        queue.pending.first(10).each do |item|
          lines << "  #{item[:priority]}. #{item[:path]}"
        end
        lines << "  ..." if queue.size > 10
        return lines.join("\n")
      end

      case arg
      when 'next'
        queue = RefactorQueue.load
        item = queue.next
        return "Queue empty" unless item
        "Next: #{item[:path]} (priority #{item[:priority]})"

      when 'run'
        queue = RefactorQueue.load
        return "Queue empty" if queue.empty?

        processed = 0
        queue.each do |item|
          puts "#{C_DIM}Processing: #{item[:path]}#{C_RESET}"
          result = refactor_file(item[:path])
          queue.complete(item[:path])
          processed += 1
        end
        "Processed #{processed} files"

      when 'clear'
        RefactorQueue.clear
        "Queue cleared"

      else
        # Add directory to queue
        queue = RefactorQueue.new
        files = resolve_files(arg)
        return "No files found: #{arg}" if files.empty?

        files.each { |f| queue.add(f) }
        queue.save
        "Added #{files.size} files to queue"
      end
    rescue LoadError, StandardError => e
      "Queue error: #{e.message}"
    end

    def run_introspect(target)
      require_relative 'introspection'

      intro = Introspection.new(@llm)

      if target.nil? || target.empty? || target == 'principles'
        # Hostile question all principles
        puts "#{C_CYAN}Auditing principles with hostile questions...#{C_RESET}"
        results = intro.audit_principles(Paths.principles)

        lines = ["#{results.size} principles examined:\n"]
        results.each do |r|
          lines << "#{C_YELLOW}#{r[:principle]}#{C_RESET}"
          lines << "  Q: #{r[:question]}"
          lines << "  A: #{r[:response][0..MAX_RESPONSE_PREVIEW]}..."
          lines << ""
        end
        lines.join("\n")
      else
        # Single hostile question
        result = intro.hostile_question(target)
        "#{C_YELLOW}Q: #{result[:question]}#{C_RESET}\n\n#{result[:response]}"
      end
    rescue LoadError, StandardError => e
      "Introspection error: #{e.message}"
    end

    def run_sanity_check(plan)
      return 'Usage: sanity <proposed action>' unless plan

      require_relative 'introspection'

      intro = Introspection.new(@llm)
      result = intro.sanity_check(plan)
      result
    rescue LoadError, StandardError => e
      "Sanity check error: #{e.message}"
    end

    def run_evolve(arg)
      require_relative 'evolve'

      target = arg ? File.expand_path(arg, @root) : @root
      budget = 2.0

      puts "#{C_CYAN}Evolving #{target}#{C_RESET}"
      puts "$#{budget} budget"
      puts

      evolve = Evolve.new(@llm)
      result = evolve.converge_and_document(target: target, budget: budget)

      lines = []
      lines << "#{C_GREEN}Evolution complete#{C_RESET}"
      lines << "  Iterations: #{result[:iterations]}"
      lines << "  Converged: #{result[:converged] ? 'yes' : 'no'}"
      lines << "  Cost: $#{'%.4f' % result[:cost]}"
      lines << ""
      lines << "Wishlist for next session:"
      result[:wishlist].first(5).each_with_index do |item, i|
        lines << "  #{i + 1}. #{item}"
      end

      lines.join("\n")
    rescue LoadError, StandardError => e
      "Evolution error: #{e.message}"
    end

    def speak_text(text)
      return "Usage: speak <text>" unless text && !text.empty?

      # Use parallel TTS for faster generation
      @tts ||= ParallelTTS.new
      Thread.new { @tts.speak(text) }
      "Speaking: #{text[0..50]}..."
    rescue => e
      # Fall back to Replicate direct
      result = Replicate.speak(text, voice: 'af_bella', speed: 1.0)
      if result.is_a?(String) && result.start_with?('http')
        save_and_play_audio(result)
        "Spoke: #{text[0..50]}..."
      else
        "TTS error: #{e.message}"
      end
    end

    def start_radio(topic = nil)
      @radio_running = true
      topic ||= 'science'

      Thread.new do
        while @radio_running
          content = generate_radio_content(topic)
          content.each do |item|
            break unless @radio_running
            result = Replicate.speak(item[:text], voice: 'af_bella', speed: item[:speed])
            save_and_play_audio(result) if result.is_a?(String) && result.start_with?('http')
          end
        end
      end

      "Radio started (#{topic}). Type 'radio stop' to end."
    end

    def generate_radio_content(topic)
      prompt = <<~PROMPT
        Generate 10 fascinating #{topic} facts. Each should be one sentence.
        Mix profound insights (mark with [SLOW]) and quick facts (mark with [FAST]).
        Return as numbered list. No fluff, only genuinely interesting content.
      PROMPT

      result = @llm.chat(prompt, tier: :fast)
      return default_facts unless result.ok?

      parse_radio_content(result.value)
    end

    def parse_radio_content(text)
      lines = text.lines.map(&:strip).reject(&:empty?)
      lines.map do |line|
        clean = line.sub(/^\d+\.\s*/, '').sub(/\[(SLOW|FAST)\]\s*/i, '')
        speed = line.include?('[SLOW]') ? 0.85 : (line.include?('[FAST]') ? 1.15 : 1.0)
        { text: clean, speed: speed }
      end
    end

    def default_facts
      [
        { text: "A single bolt of lightning contains enough energy to toast a hundred thousand slices of bread.", speed: 0.9 },
        { text: "Honey bees can recognize human faces.", speed: 0.95 },
        { text: "Octopuses have nine brains. One central and one in each arm.", speed: 0.85 },
        { text: "Crows can hold grudges and remember faces for years.", speed: 0.9 },
        { text: "There are more trees on Earth than stars in the Milky Way.", speed: 0.85 },
        { text: "A cloud weighs about one million pounds on average.", speed: 0.9 },
        { text: "Bananas glow blue under black light.", speed: 1.0 },
        { text: "The Eiffel Tower grows six inches every summer due to heat expansion.", speed: 0.9 },
        { text: "Butterflies taste with their feet.", speed: 1.0 },
        { text: "A shrimp's heart is in its head.", speed: 0.95 },
        { text: "Humans share fifty percent of their DNA with bananas.", speed: 0.85 },
        { text: "The shortest war in history lasted thirty eight minutes.", speed: 0.9 },
        { text: "A group of flamingos is called a flamboyance.", speed: 1.0 },
        { text: "The unicorn is Scotland's national animal.", speed: 0.95 },
        { text: "Almonds are members of the peach family.", speed: 1.0 }
      ].shuffle
    end

    def save_and_play_audio(url)
      path = File.join(MASTER::ROOT, 'var', 'audio', "#{Time.now.to_i}.wav")
      FileUtils.mkdir_p(File.dirname(path))

      # Download
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        File.binwrite(path, http.get(uri).body)
      end

      # Play based on OS
      play_audio(path)
      path
    end

    def play_audio(path)
      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        system("powershell -c \"Add-Type -AssemblyName presentationCore; $p = New-Object System.Windows.Media.MediaPlayer; $p.Open('#{path}'); Start-Sleep -Milliseconds 500; $p.Play(); Start-Sleep -Seconds 5; $p.Close()\"")
      when /darwin/
        system("afplay '#{path}'")
      when /linux|bsd/
        system("mpv --no-video '#{path}' 2>/dev/null || ffplay -nodisp -autoexit '#{path}' 2>/dev/null || aplay '#{path}' 2>/dev/null")
      end
    end

    # Stream LLM response token-by-token
    def stream_response(query)
      return "Usage: stream <query>" unless query
      
      puts "Streaming response..."
      @llm.stream_ask(query) do |token|
        print token
        $stdout.flush
      end
      puts
      "Stream complete"
    rescue => e
      "Error streaming: #{e.message}"
    end

    # Compare two images using LLaVA
    def compare_images(args)
      images = args&.split(/\s+/)
      return "Usage: compare-images <image1> <image2>" unless images&.size == 2
      
      comparison = ImageComparison.new(llm: @llm)
      result = comparison.compare(images[0], images[1])
      
      output = ["Image Comparison:", ""]
      output << "Winner: Image #{result[:winner]}" if result[:winner]
      output << "Similarity: #{result[:similarity_score]}%" if result[:similarity_score]
      output << ""
      output << "Key Observations:"
      result[:key_observations]&.each { |obs| output << "  - #{obs}" }
      
      output.join("\n")
    rescue => e
      "Error comparing images: #{e.message}"
    end

    # Enforce principles on file or directory
    def enforce_principles(path)
      path ||= '.'
      return "Path not found: #{path}" unless File.exist?(path)
      
      files = File.directory?(path) ? Dir["#{path}/**/*.rb"] : [path]
      violations = []
      
      files.each do |file|
        code = File.read(file)
        file_violations = Violations.check_literal(code)
        violations << { file: file, violations: file_violations } if file_violations.any?
      end
      
      if violations.any?
        output = ["Principle violations found:", ""]
        violations.each do |item|
          output << "#{item[:file]}:"
          item[:violations].each { |v| output << "  - #{v[:principle]}: #{v[:pattern]}" }
          output << ""
        end
        output.join("\n")
      else
        "✓ No principle violations found"
      end
    rescue => e
      "Error checking principles: #{e.message}"
    end

    # Install git hooks
    def install_git_hooks
      hooks_script = File.expand_path('../bin/install-hooks', MASTER::ROOT)
      return "Hook installer not found" unless File.exist?(hooks_script)
      
      result = `ruby #{hooks_script}`
      result.empty? ? "Hooks installed" : result
    rescue => e
      "Error installing hooks: #{e.message}"
    end

    # Check port consistency
    def check_port_consistency
      ports_script = File.expand_path('../bin/check_ports', MASTER::ROOT)
      return "Port checker not found" unless File.exist?(ports_script)
      
      result = `ruby #{ports_script}`
      result.empty? ? "Ports OK" : result
    rescue => e
      "Error checking ports: #{e.message}"
    end

    # Show command history
    def show_history(n = 20)
      return "No history" unless File.exist?(HISTORY_FILE)
      lines = File.readlines(HISTORY_FILE).last(n)
      lines.each_with_index.map { |l, i| "#{i + 1}. #{l.strip}" }.join("\n")
    end

    # Show session metrics
    def show_metrics
      uptime = Time.now - @boot_time
      [
        "#{C_BOLD}MASTER v#{VERSION}#{C_RESET}",
        "",
        out_row("Uptime", format_duration(uptime)),
        out_row("Commands", @command_count),
        out_row("Streak", @streak),
        out_row("Session", @session_name),
        out_row("Cost", "$#{'%.4f' % @llm.total_cost}"),
        out_row("Tokens", "#{@last_tokens[:input]}in / #{@last_tokens[:output]}out"),
        out_row("Memory", "#{`ps -o rss= -p #{Process.pid}`.to_i / 1024}MB"),
        out_row("Audit", "#{Audit.tail(1).empty? ? 0 : File.readlines(Audit::LOG_FILE).size rescue 0} entries")
      ].join("\n")
    end

    def format_duration(secs)
      if secs < 60
        "#{secs.to_i}s"
      elsif secs < 3600
        "#{(secs / 60).to_i}m #{(secs % 60).to_i}s"
      else
        "#{(secs / 3600).to_i}h #{((secs % 3600) / 60).to_i}m"
      end
    end

    # Auto-install dependencies
    def run_install(arg)
      case arg
      when 'all'
        results = AutoInstall.ensure_all(verbose: true)
        summary = []
        summary << "#{results[:packages].size} packages" if results[:packages].any?
        summary << "#{results[:gems].size} gems" if results[:gems].any?
        summary << "#{results[:repos].size} repos" if results[:repos].any?
        summary.empty? ? out_ok("All dependencies installed") : out_ok("Installed: #{summary.join(', ')}")
      when 'packages', 'pkg'
        installed = AutoInstall.ensure_packages(verbose: true)
        installed.empty? ? out_ok("All packages installed") : out_ok("Installed #{installed.size} packages")
      when 'gems'
        installed = AutoInstall.ensure_gems(verbose: true)
        installed.empty? ? out_ok("All gems installed") : out_ok("Installed #{installed.size} gems")
      when 'repos'
        cloned = AutoInstall.ensure_repos(verbose: true)
        cloned.empty? ? out_ok("All repos cloned") : out_ok("Cloned #{cloned.size} repos")
      when nil
        show_dependencies
      else
        # Install specific item
        if AutoInstall.install_gem(arg)
          out_ok("Installed gem: #{arg}")
        elsif AutoInstall.install_package(arg)
          out_ok("Installed package: #{arg}")
        else
          out_err("Could not install: #{arg}")
        end
      end
    end

    def show_dependencies
      missing = AutoInstall.missing
      status = AutoInstall.status
      
      lines = ["#{C_BOLD}Dependencies#{C_RESET}", ""]
      
      # Packages
      if RUBY_PLATFORM.include?('openbsd')
        lines << "#{C_BOLD}Packages#{C_RESET}"
        lines << out_row("Installed", status[:packages].size)
        lines << out_row("Missing", missing[:packages].size)
        lines << "  #{C_DIM}#{missing[:packages].first(5).join(', ')}#{C_RESET}" if missing[:packages].any?
        lines << ""
      end
      
      # Gems
      lines << "#{C_BOLD}Gems#{C_RESET}"
      lines << out_row("Installed", status[:gems].size)
      lines << out_row("Missing", missing[:gems].size)
      lines << "  #{C_DIM}#{missing[:gems].first(5).join(', ')}#{C_RESET}" if missing[:gems].any?
      lines << ""
      
      # Repos
      lines << "#{C_BOLD}Repos#{C_RESET}"
      lines << out_row("Cloned", status[:repos].size)
      lines << out_row("Missing", missing[:repos].size)
      
      lines << ""
      lines << "#{C_DIM}Run 'install all' to install everything#{C_RESET}"
      
      lines.join("\n")
    end

    # Output helpers - consistent formatting per typography spec
    def out_ok(msg)
      "#{C_GREEN}#{ICON_OK}#{C_RESET} #{msg}"
    end

    def out_err(msg, detail = nil)
      lines = ["#{C_RED}#{ICON_ERR}#{C_RESET} #{msg}"]
      lines << "  #{C_DIM}#{detail}#{C_RESET}" if detail
      lines.join("\n")
    end

    def out_warn(msg)
      "#{C_YELLOW}#{ICON_WARN}#{C_RESET} #{msg}"
    end

    def out_dim(msg)
      "#{C_DIM}#{msg}#{C_RESET}"
    end

    def out_row(label, value, width = 12)
      "  #{label.ljust(width)}#{C_DIM}#{value}#{C_RESET}"
    end

    # Visual separator - using whitespace instead of ASCII art
    def separator(label = nil)
      if label
        "\n#{C_BOLD}#{label}#{C_RESET}\n"
      else
        ""
      end
    end

    # Progress indicator for long operations
    def with_progress(message)
      if TTY_AVAILABLE
        spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots)
        spinner.auto_spin
        result = yield
        spinner.success
        return result
      end
      
      done = false
      spinner_thread = Thread.new do
        i = 0
        until done
          print "\r#{message} #{SPINNER[i % 4]}"
          i += 1
          sleep 0.1
        end
      end
      result = yield
      done = true
      spinner_thread.join
      puts "\r#{message} #{C_GREEN}✓#{C_RESET}"
      result
    end
    
    # TTY-Prompt interactive selection
    def tty_select(question, choices, default: nil)
      return choices.first unless TTY_AVAILABLE
      @prompt.select(question, choices, default: default, cycle: true)
    end
    
    # TTY-Prompt multi-select
    def tty_multi_select(question, choices)
      return choices unless TTY_AVAILABLE
      @prompt.multi_select(question, choices, cycle: true)
    end
    
    # TTY-Prompt yes/no
    def tty_confirm(question, default: true)
      return default unless TTY_AVAILABLE
      @prompt.yes?(question, default: default)
    end
    
    # TTY-Prompt text input
    def tty_ask(question, default: nil)
      return default unless TTY_AVAILABLE
      @prompt.ask(question, default: default)
    end
    
    # TTY-Table for structured data
    def tty_table(headers, rows)
      if TTY_AVAILABLE
        table = TTY::Table.new(headers, rows)
        table.render(:unicode, padding: [0, 1])
      else
        # Fallback to simple aligned output
        widths = headers.map.with_index { |h, i| [h.to_s.length, rows.map { |r| r[i].to_s.length }.max || 0].max }
        lines = [headers.map.with_index { |h, i| h.to_s.ljust(widths[i]) }.join('  ')]
        rows.each { |row| lines << row.map.with_index { |c, i| c.to_s.ljust(widths[i]) }.join('  ') }
        lines.join("\n")
      end
    end
    
    # TTY-Box for highlighted content
    def tty_box(content, title: nil)
      if TTY_AVAILABLE
        TTY::Box.frame(content, title: title, padding: 1, border: :round)
      else
        title_line = title ? "#{C_BOLD}#{title}#{C_RESET}\n\n" : ""
        "#{title_line}#{content}"
      end
    end
    
    # Pastel colorization (richer than ANSI)
    def colorize(text, *styles)
      return text unless TTY_AVAILABLE && @pastel
      @pastel.decorate(text, *styles)
    end
  end
end
COMMAND_SHORTCUTS = {"q" => "quit", "h" => "help", "s" => "status", "l" => "list", "r" => "run", "c" => "clear", "v" => "version", "d" => "debug"}.freeze
EXIT_CODES = {success: 0, error: 1, usage: 2}.freeze
