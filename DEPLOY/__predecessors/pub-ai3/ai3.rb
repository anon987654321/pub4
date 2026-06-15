#!/usr/bin/env ruby
# frozen_string_literal: true

# AI³ (AI Cubed) - Interactive Multi-LLM RAG CLI
# Main entry point with TTY interface and cognitive orchestration

require 'bundler/setup'
require 'tty-prompt'
require 'tty-spinner'
require 'tty-box'
require 'pastel'
require 'yaml'
require 'dotenv'
require 'i18n'

# Load environment variables
Dotenv.load('.env', File.expand_path('~/.ai3_keys'))

# Setup I18n
I18n.load_path = Dir[File.join(__dir__, 'config', 'locales', '*.yml')]
I18n.default_locale = :en

# Require core AI³ components
require_relative 'lib/cognitive_orchestrator'
require_relative 'lib/multi_llm_manager'
require_relative 'lib/enhanced_session_manager'
require_relative 'lib/rag_engine'
require_relative 'lib/assistant_registry'
require_relative 'lib/universal_scraper'

# Main AI³ CLI Application
class AI3CLI
  VERSION = '12.3.0'

  attr_reader :config, :cognitive_orchestrator, :llm_manager, :session_manager,
              :rag_engine, :assistant_registry, :current_assistant, :prompt, :pastel, :scraper

  def initialize
    @pastel = Pastel.new
    @prompt = TTY::Prompt.new

    # Load configuration
    @config = load_configuration

    # Initialize core components with cognitive integration
    initialize_components

    # Setup signal handlers
    setup_signal_handlers

    # Create required directories
    setup_directories
  end

  # Main CLI loop
  def run
    display_welcome

    # Main interactive loop
    loop do
      # Check cognitive state
      check_cognitive_health

      # Get user input
      input = get_user_input

      # Process command
      process_command(input) unless input.nil? || input.strip.empty?
    rescue Interrupt
      puts "\n👋 Goodbye!"
      break
    rescue StandardError => e
      handle_error(e)
    end
  end

  private

  # Load and merge configuration files
  def load_configuration
    config_file = File.join(__dir__, 'config', 'config.yml')

    if File.exist?(config_file)
      config = YAML.load_file(config_file)

      # Substitute environment variables
      substitute_env_vars(config)
    else
      puts '⚠️ Configuration file not found, using defaults'
      default_configuration
    end
  end

  # Initialize all AI³ components
  def initialize_components
    puts '🚀 Initializing AI³ Cognitive Architecture Framework...'

    spinner = TTY::Spinner.new('[:spinner] Loading components...', format: :dots)
    spinner.auto_spin

    # Initialize cognitive orchestrator (core of 7±2 working memory)
    @cognitive_orchestrator = CognitiveOrchestrator.new

    # Initialize multi-LLM manager with fallback chains
    @llm_manager = MultiLLMManager.new(@config)

    # Initialize enhanced session manager with cognitive awareness
    @session_manager = EnhancedSessionManager.new(
      max_sessions: @config.dig('session', 'max_sessions') || 10,
      eviction_strategy: @config.dig('session', 'eviction_strategy')&.to_sym || :cognitive_load_aware
    )

    # Initialize RAG engine
    @rag_engine = RAGEngine.new(
      db_path: @config.dig('rag', 'vector_db_path') || 'data/vector_store.db'
    )
    @rag_engine.set_cognitive_monitor(@cognitive_orchestrator)

    # Initialize assistant registry
    @assistant_registry = AssistantRegistry.new(@cognitive_orchestrator)

    # Set default assistant
    @current_assistant = @assistant_registry.get_assistant(
      @config.dig('assistants', 'default_assistant') || 'general'
    )

    spinner.stop
    puts '✅ AI³ system initialized successfully'
  end

  # Setup signal handlers for graceful shutdown
  def setup_signal_handlers
    Signal.trap('INT') do
      puts "\n🛑 Graceful shutdown initiated..."
      # Save any pending data
      @session_manager&.clear_all_sessions if @session_manager
      exit(0)
    end
  end

  # Create required directories
  def setup_directories
    directories = %w[data logs tmp config screenshots]
    directories.each do |dir|
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end
  end

  # Display welcome message with cognitive status
  def display_welcome
    box_content = "#{@pastel.bold.cyan('AI³')} #{@pastel.dim('v' + VERSION)}\n" \
                  "#{I18n.t('ai3.welcome')}\n\n" \
                  "#{@pastel.green('●')} Cognitive Load: #{cognitive_load_indicator}\n" \
                  "#{@pastel.blue('●')} Current Assistant: #{@current_assistant.name}\n" \
                  "#{@pastel.yellow('●')} Current LLM: #{@llm_manager.current_provider}\n\n" \
                  "#{@pastel.dim('Type \"help\" for commands or \"exit\" to quit')}"

    puts TTY::Box.frame(box_content, padding: 1, border: :light)
  end

  # Get user input with cognitive-aware prompting
  def get_user_input
    prompt_text = cognitive_prompt

    @prompt.ask(prompt_text) do |q|
      q.required false
      q.modify :strip
    end
  end

  # Generate cognitive-aware prompt
  def cognitive_prompt
    load_indicator = cognitive_load_indicator
    flow_indicator = flow_state_indicator

    "#{load_indicator}#{flow_indicator} #{@pastel.cyan('ai3>')} "
  end

  # Process user commands
  def process_command(input)
    parts = input.split(' ', 2)
    command = parts[0].downcase
    args = parts[1]

    case command
    when 'chat'
      handle_chat_command(args)
    when 'rag'
      handle_rag_command(args)
    when 'task'
      handle_task_command(args)
    when 'scrape'
      handle_scrape_command(args)
    when 'switch'
      handle_switch_command(args)
    when 'assistant'
      handle_assistant_command(args)
    when 'legal'
      handle_legal_command(args)
    when 'swarm'
      handle_swarm_command(args)
    when 'list'
      handle_list_command(args)
    when 'status'
      handle_status_command
    when 'help', '?'
      handle_help_command
    when 'exit', 'quit', 'q'
      puts "👋 #{I18n.t('ai3.messages.goodbye', default: 'Goodbye!')}"
      exit(0)
    else
      puts "❌ #{I18n.t('ai3.errors.command_not_found', command: command)}"
      puts "💡 Type 'help' to see available commands"
    end
  end

  # Handle chat command
  def handle_chat_command(query)
    return puts '❌ Please provide a query' unless query

    # Check cognitive capacity
    complexity = @cognitive_orchestrator.assess_complexity(query)

    if @cognitive_orchestrator.cognitive_overload?
      snapshot_id = @cognitive_orchestrator.trigger_circuit_breaker
      puts "🧠 #{I18n.t('ai3.cognitive.circuit_breaker.activated')} (Snapshot: #{snapshot_id})"
      return
    end

    spinner = TTY::Spinner.new("[:spinner] #{I18n.t('ai3.messages.processing')}...", format: :dots)
    spinner.auto_spin

    begin
      # Get session context
      session = @session_manager.get_session('default_user')

      # Generate response using current assistant
      response = @current_assistant.respond(query, context: session[:context])

      # Route through LLM manager if needed
      if response.is_a?(String) && response.include?("I'm #{@current_assistant.name}")
        llm_response = @llm_manager.route_query(query)
        response = llm_response[:response]

        if llm_response[:fallback_used]
          puts "🔄 #{I18n.t('ai3.messages.fallback_activated')} (#{llm_response[:provider]})"
        end
      end

      # Update session
      @session_manager.update_session('default_user', {
                                        last_query: query,
                                        last_response: response,
                                        assistant_used: @current_assistant.name
                                      })

      # Add to cognitive orchestrator
      @cognitive_orchestrator.add_concept(query[0..50], complexity * 0.1)

      spinner.stop
      puts "\n#{@pastel.green('Assistant:')} #{response}\n"
    rescue StandardError => e
      spinner.stop
      puts "❌ Error: #{e.message}"
    end
  end

  # Handle RAG command
  def handle_rag_command(query)
    return puts '❌ Please provide a query' unless query

    spinner = TTY::Spinner.new("[:spinner] #{I18n.t('ai3.rag.searching')}...", format: :dots)
    spinner.auto_spin

    begin
      # Search using RAG engine
      results = @rag_engine.search(query, limit: 5)

      spinner.stop

      if results.empty?
        puts "❌ #{I18n.t('ai3.rag.no_results')}"
        return
      end

      puts "📚 #{I18n.t('ai3.rag.results_found', count: results.size)}\n"

      # Display results
      results.each_with_index do |result, index|
        puts "#{@pastel.cyan("#{index + 1}.")} #{result[:content][0..200]}..."
        puts "   #{@pastel.dim("Similarity: #{(result[:similarity] * 100).round(1)}%")}\n"
      end

      # Enhance query with RAG context and get LLM response
      context_text = results.map { |r| r[:content] }.join("\n\n")
      enhanced_query = "Based on this context: #{context_text}\n\nQuestion: #{query}"

      llm_response = @llm_manager.route_query(enhanced_query)
      puts "\n#{@pastel.green('Enhanced Response:')} #{llm_response[:response]}\n"
    rescue StandardError => e
      spinner.stop
      puts "❌ RAG Error: #{e.message}"
    end
  end

  # Handle other commands (simplified for brevity)
  def handle_task_command(_args)
    puts '🔧 Task execution feature coming soon...'
  end

  def handle_scrape_command(args)
    return puts '❌ Please provide a URL to scrape' unless args

    url = args.strip
    return puts '❌ Invalid URL format' unless url.match?(%r{^https?://})

    # Initialize scraper if not already done
    @scraper ||= initialize_scraper

    spinner = TTY::Spinner.new("[:spinner] #{I18n.t('ai3.scraper.scraping', url: url, default: 'Scraping...')}...",
                               format: :dots)
    spinner.auto_spin

    begin
      # Perform scraping
      result = @scraper.scrape(url)

      spinner.stop

      if result[:success]
        puts "✅ #{I18n.t('ai3.scraper.content_extracted', default: 'Content extracted successfully')}"
        puts "📄 Title: #{result[:title]}" if result[:title]
        puts "📸 Screenshot: #{result[:screenshot]}" if result[:screenshot]
        puts "🔗 Links found: #{result[:links]&.size || 0}" if result[:links]

        # Show content preview
        if result[:content] && !result[:content].empty?
          preview = result[:content][0..300]
          preview += '...' if result[:content].length > 300
          puts "\n📄 Content Preview:"
          puts "#{@pastel.dim(preview)}\n"
        end

        # Add to RAG if enabled
        add_scraped_content_to_rag(result) if @config.dig('rag', 'enabled')

        # Ask if user wants to chat about the content
        if @prompt.yes?('💬 Would you like to chat about this content?')
          enhanced_query = "Based on the content from #{url}: #{result[:content][0..500]}... Please analyze and summarize this content."
          handle_chat_command(enhanced_query)
        end

      else
        puts "❌ #{I18n.t('ai3.scraper.error', error: result[:error], default: 'Scraping failed')}: #{result[:error]}"
      end
    rescue StandardError => e
      spinner.stop
      puts "❌ Scraping error: #{e.message}"
    end
  end

  def handle_switch_command(args)
    return puts '❌ Please specify LLM provider' unless args

    begin
      @llm_manager.switch_provider(args.to_sym)
      puts "✅ Switched to #{args}"
    rescue StandardError => e
      puts "❌ Switch failed: #{e.message}"
    end
  end

  def handle_assistant_command(args)
    return puts '❌ Please specify assistant name' unless args

    begin
      @current_assistant = @assistant_registry.get_assistant(args)
      puts "✅ Switched to #{@current_assistant.name} assistant"
    rescue StandardError => e
      puts "❌ Assistant switch failed: #{e.message}"
    end
  end

  def handle_legal_command(args)
    return puts '❌ Please provide a legal query' unless args

    # Get Norwegian legal assistant
    legal_assistant = @assistant_registry.get_assistant('lawyer')
    
    if legal_assistant.nil?
      puts '❌ Norwegian Legal Assistant not available'
      return
    end

    spinner = TTY::Spinner.new("[:spinner] #{I18n.t('ai3.legal.norwegian.searching_lovdata', default: 'Researching Norwegian law')}...", format: :dots)
    spinner.auto_spin

    begin
      # Use the specialized Norwegian legal assistant
      response = legal_assistant.respond(args)
      
      spinner.stop
      puts "\n#{@pastel.green('Norwegian Legal Analysis:')} #{response}\n"
      
      # Add to session for context
      @session_manager.update_session('default_user', {
        last_legal_query: args,
        last_legal_response: response,
        assistant_used: legal_assistant.name
      })
      
    rescue StandardError => e
      spinner.stop
      puts "❌ Legal research error: #{e.message}"
    end
  end

  def handle_swarm_command(args)
    return puts '❌ Please provide a task for multi-agent coordination' unless args

    puts I18n.t('ai3.assistants.swarm.orchestration_started', default: 'Multi-agent orchestration started')
    
    # Check if cognitive load allows multi-agent processing
    if @cognitive_orchestrator.cognitive_overload?
      puts "🧠 Cognitive overload - deferring to single agent processing"
      handle_chat_command(args)
      return
    end

    # Determine optimal assistant combination for the task
    relevant_assistants = determine_relevant_assistants(args)
    
    spinner = TTY::Spinner.new("[:spinner] Coordinating #{relevant_assistants.size} agents...", format: :dots)
    spinner.auto_spin

    begin
      # Coordinate multiple assistants
      swarm_results = coordinate_swarm_task(args, relevant_assistants)
      
      spinner.stop
      puts "\n#{@pastel.green('Multi-Agent Response:')} #{swarm_results}\n"
      
    rescue StandardError => e
      spinner.stop
      puts "❌ Swarm coordination error: #{e.message}"
    end
  end

  def handle_list_command(type)
    case type&.downcase
    when 'assistants', 'assistant', 'a'
      list_assistants
    when 'llms', 'llm', 'providers', 'l'
      list_llm_providers
    when 'tools', 'tool', 't'
      list_tools
    else
      puts 'Available lists: assistants, llms, tools'
    end
  end

  def handle_status_command
    display_cognitive_status
  end

  def handle_help_command
    puts I18n.t('ai3.help.usage')
  end

  # Display cognitive status
  def display_cognitive_status
    cognitive_state = @cognitive_orchestrator.cognitive_state
    session_state = @session_manager.cognitive_state

    status_content = "#{@pastel.bold('Cognitive Status')}\n\n" \
                     "#{@pastel.yellow('●')} Cognitive Load: #{cognitive_state[:load].round(2)}/7\n" \
                     "#{@pastel.blue('●')} Flow State: #{cognitive_state[:flow_state]}\n" \
                     "#{@pastel.green('●')} Active Concepts: #{cognitive_state[:concepts]}\n" \
                     "#{@pastel.magenta('●')} Context Switches: #{cognitive_state[:switches]}\n" \
                     "#{@pastel.cyan('●')} Overload Risk: #{cognitive_state[:overload_risk]}%\n\n" \
                     "#{@pastel.bold('Session Management')}\n\n" \
                     "#{@pastel.yellow('●')} Active Sessions: #{session_state[:total_sessions]}\n" \
                     "#{@pastel.blue('●')} Cognitive Health: #{session_state[:cognitive_health]}\n" \
                     "#{@pastel.green('●')} Load Distribution: #{session_state[:cognitive_load_percentage]}%"

    puts TTY::Box.frame(status_content, padding: 1, border: :light)
  end

  # List assistants
  def list_assistants
    assistants = @assistant_registry.list_assistants

    puts "#{@pastel.bold('Available Assistants:')}\n"
    assistants.each do |assistant|
      status_indicator = assistant[:status][:session_active] ? @pastel.green('●') : @pastel.dim('○')
      current_indicator = assistant[:name] == @current_assistant.name ? @pastel.yellow(' [CURRENT]') : ''

      puts "#{status_indicator} #{@pastel.cyan(assistant[:name])} - #{assistant[:role]}#{current_indicator}"
      puts "  #{@pastel.dim("Capabilities: #{assistant[:capabilities].join(', ')}")}"
      puts "  #{@pastel.dim("Cognitive Load: #{assistant[:status][:cognitive_load].round(2)}/7")}\n"
    end
  end

  # List LLM providers
  def list_llm_providers
    status = @llm_manager.provider_status

    puts "#{@pastel.bold('LLM Providers:')}\n"
    status.each do |provider, info|
      status_indicator = info[:available] ? @pastel.green('●') : @pastel.red('●')
      current_indicator = provider == @llm_manager.current_provider ? @pastel.yellow(' [CURRENT]') : ''

      puts "#{status_indicator} #{@pastel.cyan(info[:name])}#{current_indicator}"

      if info[:available]
        puts "  #{@pastel.dim("Last Success: #{info[:last_success] || 'Never'}")}"
      else
        cooldown = info[:cooldown_remaining]
        puts "  #{@pastel.red("Cooldown: #{cooldown}s remaining")}" if cooldown > 0
      end
      puts
    end
  end

  def list_tools
    puts '🔧 Available tools: RAG, Web Scraping, Session Management, Cognitive Monitoring'
  end

  # Determine which assistants are most relevant for a given task
  def determine_relevant_assistants(task)
    task_downcase = task.downcase
    relevant = []
    
    # Add legal assistant for legal queries
    relevant << 'lawyer' if task_downcase.match?(/law|legal|court|contract|compliance/)
    
    # Add trading assistant for financial queries
    relevant << 'trader' if task_downcase.match?(/trading|stock|finance|investment|market/)
    
    # Add medical assistant for health queries
    relevant << 'medical' if task_downcase.match?(/health|medical|doctor|diagnosis|drug/)
    
    # Add security assistant for security queries
    relevant << 'hacker' if task_downcase.match?(/security|hack|vulnerability|penetration|threat/)
    
    # Add web developer for technical queries
    relevant << 'web_developer' if task_downcase.match?(/web|app|development|programming|code/)
    
    # Always include general assistant as coordinator
    relevant << 'general' unless relevant.empty?
    
    relevant.uniq
  end

  # Coordinate a task across multiple assistants
  def coordinate_swarm_task(task, assistant_names)
    results = []
    
    assistant_names.each do |name|
      assistant = @assistant_registry.get_assistant(name)
      next unless assistant
      
      begin
        # Get response from each assistant
        response = assistant.respond(task)
        results << {
          assistant: assistant.name,
          response: response
        }
        
        # Add cognitive load for coordination
        @cognitive_orchestrator.add_concept("swarm_#{name}", 0.5)
        
      rescue StandardError => e
        results << {
          assistant: name,
          error: e.message
        }
      end
    end
    
    # Synthesize results
    synthesize_swarm_results(results)
  end

  # Combine results from multiple assistants into coherent response
  def synthesize_swarm_results(results)
    return "No results from swarm coordination" if results.empty?
    
    synthesis = "Multi-Agent Analysis:\n\n"
    
    results.each do |result|
      if result[:error]
        synthesis += "#{result[:assistant]}: Error - #{result[:error]}\n\n"
      else
        synthesis += "#{result[:assistant]}:\n#{result[:response]}\n\n"
      end
    end
    
    synthesis += "Coordinated Recommendation:\n"
    synthesis += generate_coordinated_recommendation(results)
    
    synthesis
  end

  # Generate a coordinated recommendation from multiple assistant inputs
  def generate_coordinated_recommendation(results)
    successful_results = results.reject { |r| r[:error] }
    return "Unable to generate recommendation due to errors" if successful_results.empty?
    
    "Based on analysis from #{successful_results.size} specialized assistants, " \
    "consider the integrated insights above for a comprehensive approach to your query."
  end

  # Initialize scraper with cognitive integration
  def initialize_scraper
    scraper_config = {
      screenshot_dir: @config.dig('scraper', 'screenshot_dir') || 'data/screenshots',
      max_depth: @config.dig('scraper', 'max_depth') || 2,
      timeout: @config.dig('scraper', 'timeout') || 30,
      user_agent: @config.dig('scraper', 'user_agent') || 'AI3-Bot/1.0'
    }

    scraper = UniversalScraper.new(scraper_config)
    scraper.set_cognitive_monitor(@cognitive_orchestrator)
    scraper
  end

  # Add scraped content to RAG engine
  def add_scraped_content_to_rag(scrape_result)
    return unless scrape_result[:success] && scrape_result[:content]

    document = {
      content: scrape_result[:content],
      title: scrape_result[:title],
      url: scrape_result[:url],
      scraped_at: scrape_result[:timestamp]
    }

    collection = 'scraped_content'

    if @rag_engine.add_document(document, collection: collection)
      puts "📚 Content added to knowledge base (collection: #{collection})"
    else
      puts '⚠️ Failed to add content to knowledge base'
    end
  end

  # Cognitive load indicator for prompt
  def cognitive_load_indicator
    load = @cognitive_orchestrator.current_load

    case load
    when 0..3
      @pastel.green('●')
    when 4..6
      @pastel.yellow('●')
    else
      @pastel.red('●')
    end
  end

  # Flow state indicator
  def flow_state_indicator
    state = @cognitive_orchestrator.flow_state_indicators.current_state

    case state
    when :optimal
      @pastel.green('◆')
    when :focused
      @pastel.blue('◆')
    when :stressed
      @pastel.yellow('◆')
    else
      @pastel.red('◆')
    end
  end

  # Check cognitive health and take action if needed
  def check_cognitive_health
    return unless @cognitive_orchestrator.cognitive_overload?

    puts "⚠️ #{I18n.t('ai3.messages.cognitive_overload')}"
    @cognitive_orchestrator.trigger_circuit_breaker
  end

  # Handle errors gracefully
  def handle_error(error)
    puts "💥 #{@pastel.red('Error:')} #{error.message}"
    puts "🔍 #{@pastel.dim('Type \"help\" for usage information')}"

    # Log error for debugging
    File.open('logs/errors.log', 'a') do |f|
      f.puts "[#{Time.now}] #{error.class}: #{error.message}"
      f.puts error.backtrace.join("\n")
      f.puts '---'
    end
  end

  # Substitute environment variables in config
  def substitute_env_vars(obj)
    case obj
    when Hash
      obj.each { |k, v| obj[k] = substitute_env_vars(v) }
    when Array
      obj.map! { |v| substitute_env_vars(v) }
    when String
      obj.gsub(/\$\{([^}]+)\}/) { |match| ENV[::Regexp.last_match(1)] || match }
    else
      obj
    end
  end

  # Default configuration
  def default_configuration
    {
      'llm' => { 'primary' => 'xai', 'fallback_enabled' => true },
      'cognitive' => { 'max_working_memory' => 7 },
      'session' => { 'max_sessions' => 10 },
      'assistants' => { 'default_assistant' => 'general' }
    }
  end
end

# Run the CLI if this file is executed directly
if __FILE__ == $0
  begin
    cli = AI3CLI.new
    cli.run
  rescue StandardError => e
    puts "💥 Fatal error: #{e.message}"
    puts 'Please check your configuration and try again.'
    exit(1)
  end
end
