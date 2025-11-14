# Main CLI application
class CognitiveRubyCLI

  def initialize
    Console.clear_screen

    Console.print_header("CRC - Claude Ruby CLI")

    OpenBSDSandbox.setup_filesystem_sandbox

    show_system_info

    @config = load_or_create_config
    @logger = CLILogger.setup(@config["log_level"])
    @Claude = CognitiveTracker.new(@config["cognitive_tracking"])

    @knowledge = KnowledgeStore.new(@config["knowledge_store"])
    @fallback = LLMFallback.new(@config, @logger)

    @tools = ToolsProvider.new(@config, @logger)

    @llm = LLMProvider.new(@config, @logger, @tools.available_tools, @cognitive)

    @scraper = WebScraper.new(@config, @logger)

    @analyzer = CodeAnalyzer.new(@logger)

    @github = GitHubIntegration.new(@config, @logger)

    @scanner = ProjectScanner.new(@config, @logger)

    @watcher = FileWatcher.new(@config, @logger)

    @scraper.setup_browser if @scraper.available?

    setup_file_watcher

    Console.print_success("Ready!")
  end

  def run
    loop do

      show_main_menu
      choice = Console.ask("Choice", default: "1")

      handle_main_menu_choice(choice)

    rescue Interrupt

      Console.print_warning("\nExiting...")
      cleanup

      exit(0)

    rescue => e

      Console.print_error("Error: #{e.message}")

      Console.pause

    end

  end

  private

  def show_system_info

    puts "Platform: #{PlatformDetector.platform_name}"
    puts "Ruby: #{RUBY_VERSION}"
    puts "Working Directory: #{Dir.pwd}"

    puts

    Console.print_info("Features:")

    features = {

      "LangchainRB" => LANGCHAIN_AVAILABLE,

      "GitHub" => OCTOKIT_AVAILABLE,

      "Git" => RUGGED_AVAILABLE,

      "File watching" => LISTEN_AVAILABLE,

      "AST analysis" => AST_AVAILABLE,

      "Web scraping" => FERRUM_AVAILABLE,

      "OpenBSD sandbox" => PLEDGE_AVAILABLE,

      "Claude tracking" => @config&.dig("cognitive_tracking"),

      "Knowledge store" => @config&.dig("knowledge_store")

    }

    features.each { |name, available| Console.print_success("  #{name}: #{available ? "Yes" : "No"}") }

    puts

  end

  def load_or_create_config

    config = Configuration.load

    if config == Configuration::DEFAULT_CONFIG
      Console.print_info("First run - setting up configuration")

      config = setup_initial_config
      Configuration.save(config)

    else

      Console.print_info("Configuration loaded")

    end

    config

  end

  def setup_initial_config
    config = Configuration::DEFAULT_CONFIG.dup

    Console.print_header("Initial Configuration")
    if LANGCHAIN_AVAILABLE

      if Console.ask_yes_no("Configure Anthropic API?", default: true)
        config["anthropic_api_key"] = Console.ask_password("Anthropic API key")
      end

      if Console.ask_yes_no("Configure OpenAI API?", default: false)

        config["openai_api_key"] = Console.ask_password("OpenAI API key")

      end
      unless config["anthropic_api_key"] || config["openai_api_key"]

        Console.print_info("Using mock responses")

      end
    else

      Console.print_info("Using mock responses")

    end

    if LANGCHAIN_AVAILABLE && Console.ask_yes_no("Enable autonomous mode? (requires API keys)", default: false)

      config["autonomous_mode"] = true

    end
    if Console.ask_yes_no("Enable Claude tracking?", default: true)

      config["cognitive_tracking"] = true

    end
    if Console.ask_yes_no("Enable knowledge store?", default: true)

      config["knowledge_store"] = true

    end
    if OCTOKIT_AVAILABLE && Console.ask_yes_no("Configure GitHub?", default: false)

      config["github_token"] = Console.ask_password("GitHub token")

    end
    config

  end

  def setup_file_watcher
    return unless @watcher.available?

    @watcher.start_watching do |changes|
      if changes[:modified].any? || changes[:added].any?

        @cognitive.add_task("file_change", 0.2)
      end

    end

  end

  def show_main_menu

    Console.print_header("Main Menu")

    status = @cognitive.status
    puts "Claude Load: #{status[:load]}/#{status[:capacity]} (#{status[:tasks]} tasks)"

    puts
    puts "1. Generate Code with AI"

    puts "2. Analyze File"

    puts "3. Scan Project"

    puts "4. Knowledge Search"

    puts "5. Toggle File Watcher"

    puts "6. Project Info"

    puts "7. Configuration"

    puts "8. Web Scraping"

    puts "9. Git Operations"

    puts "10. Autonomous Mode"

    puts "11. Claude Status"

    puts "q. Quit"

    puts

  end

  def handle_main_menu_choice(choice)

    case choice.downcase

    when "1" then handle_code_generation
    when "2" then handle_file_analysis

    when "3" then handle_project_scan

    when "4" then handle_knowledge_search

    when "5" then handle_file_watcher_toggle

    when "6" then handle_project_info

    when "7" then handle_configuration

    when "8" then handle_web_scraping

    when "9" then handle_git_operations

    when "10" then handle_autonomous_mode

    when "11" then handle_cognitive_status

    when "q", "quit", "exit"

      Console.print_warning("Goodbye!")

      cleanup

      exit(0)

    else

      Console.print_error("Invalid choice")

    end

  end

  def handle_code_generation

    Console.print_header("AI Code Generation")

    unless @llm.available?
      Console.print_error("LLM unavailable - check configuration")

      Console.pause
      return

    end

    if @cognitive.overloaded?

      Console.print_warning("High Claude load - simplifying task")

    end
    task = Console.ask("What should I code?")

    return if task.empty?

    @cognitive.add_task("code_gen", 1.5)
    include_context = Console.ask_yes_no("Include project context?", default: true)

    context = nil
    if include_context
      Console.spinner("Scanning project...") do
        scan_result = @scanner.scan_project

        context = "Project structure:\n#{format_scan_result(scan_result)}"

      end

    end

    Console.spinner("Generating...") { sleep(0.5) }

    response = @fallback.route_query(task, context: context)

    if response[:error]
      Console.print_error("Error: #{response[:error] || "Generation failed"}")
    else
      puts response[:content]

      puts

      Console.print_info("Model: #{response[:model]}")

      if Console.ask_yes_no("Save to file?", default: false)

        filename = Console.ask("Filename", default: "generated_code.rb")

        File.write(filename, response[:content])
        Console.print_success("Saved to #{filename}")

        @knowledge.add_document(response[:content], "generated_#{task[0..20]}")

      end

    end
    Console.pause

  end

  def handle_file_analysis
    Console.print_header("File Analysis")

    unless @analyzer.available?
      Console.print_error("AST analysis unavailable - install parser rubocop-ast gems")

      Console.pause
      return

    end

    filepath = Console.ask("File path")

    return if filepath.empty?

    Console.spinner("Analyzing...") do
      @analysis_result = @analyzer.analyze_file(filepath)

    end
    if @analysis_result[:error]

      Console.print_error("Error: #{@analysis_result[:error]}")

    else
      Console.print_header("Analysis Results")

      puts "File: #{@analysis_result[:file]}"

      puts "Lines: #{@analysis_result[:lines]}"

      puts "Classes: #{@analysis_result[:classes]}"

      puts "Methods: #{@analysis_result[:methods]}"

      puts "Complexity: #{@analysis_result[:complexity]}"

      if @analysis_result[:issues].any?

        puts "Issues:"

        @analysis_result[:issues].each { |issue| puts "  - #{issue}" }
      end

    end

    Console.pause

  end

  def handle_project_scan
    Console.print_header("Project Scan")

    Console.spinner("Scanning...") do
      @scan_result = @scanner.scan_project

    end
    Console.print_header("Scan Results")

    puts "Root: #{@scan_result[:root]}"

    puts "Files: #{@scan_result[:files].size}"
    puts "Technologies: #{@scan_result[:technologies].join(", ")}"

    puts

    puts "Structure:"

    @scan_result[:structure].each { |name, type| puts "  #{name} (#{type})" }

    Console.pause

  end

  def handle_knowledge_search
    Console.print_header("Knowledge Search")

    query = Console.ask("Search query")
    return if query.empty?

    Console.spinner("Searching knowledge base...") do
      @search_results = @knowledge.search(query)

    end
    if @search_results.empty?

      Console.print_warning("No results found")

      if Console.ask_yes_no("Search web instead?", default: true)
        handle_web_scraping_with_query(query)

      end
    else

      Console.print_header("Knowledge Results")

      @search_results.each_with_index do |result, i|

        puts "#{i + 1}. #{result[:file]}"

        puts "   #{result[:content][0..100]}..."

        puts "   Score: #{(result[:score] * 100).round(1)}%"

        puts

      end

      if Console.ask_yes_no("Analyze with LLM?", default: true)

        context = @search_results.map { |r| r[:content] }.join("\n\n")

        enhanced_query = "Based on knowledge: #{context[0..1000]}\n\nQuestion: #{query}"
        response = @fallback.route_query(enhanced_query)

        puts "\nEnhanced Analysis:"

        puts response[:content]
      end

    end

    Console.pause

  end

  def handle_cognitive_status
    Console.print_header("Claude Status")

    status = @cognitive.status
    puts "Load: #{status[:load]}/#{status[:capacity]}"

    puts "Active tasks: #{status[:tasks]}"
    puts "Overloaded: #{@cognitive.overloaded? ? "Yes" : "No"}"

    if @cognitive.overloaded?

      if Console.ask_yes_no("Clear Claude load?", default: true)

        @cognitive.clear
        Console.print_success("Claude load cleared")

      end

    end

    Console.pause

  end

  def handle_web_scraping_with_query(query)
    url = Console.ask("URL to scrape for: #{query}")

    return if url.empty?
    Console.spinner("Scraping and analyzing...") do

      @scrape_result = @scraper.scrape_with_reasoning(url, @llm, query)

    end
    if @scrape_result[:error]

      Console.print_error("Error: #{@scrape_result[:error]}")

    else
      Console.print_success("Content extracted")

      puts @scrape_result[:content][0..500]

      @knowledge.add_document(@scrape_result[:content], "scraped_#{query[0..20]}")

      Console.print_success("Added to knowledge base")

    end
  end

  def handle_file_watcher_toggle

    Console.print_header("File Watcher")

    unless @watcher.available?
      Console.print_error("File watching unavailable - install listen gem")

      Console.pause
      return

    end

    if @watcher.watching?

      @watcher.stop_watching

      Console.print_success("File watching stopped")
    else

      if @watcher.start_watching

        Console.print_success("File watching started")

      else

        Console.print_error("Failed to start file watching")

      end

    end

    Console.pause

  end

  def handle_project_info
    Console.print_header("Project Information")

    puts "Working Directory: #{Dir.pwd}"
    puts

    puts "Available Features:"
    features = [

      ["LangchainRB", LANGCHAIN_AVAILABLE],

      ["GitHub", OCTOKIT_AVAILABLE],

      ["Git", RUGGED_AVAILABLE],

      ["File watching", LISTEN_AVAILABLE],

      ["AST analysis", AST_AVAILABLE],

      ["Web scraping", FERRUM_AVAILABLE],

      ["OpenBSD sandbox", PLEDGE_AVAILABLE],

      ["Claude tracking", @config["cognitive_tracking"]],

      ["Knowledge store", @config["knowledge_store"]]

    ]

    features.each { |name, available| puts "  #{name}: #{available ? "Yes" : "No"}" }

    puts

    if @github.available?

      Console.spinner("Getting repository info...") do
        @repo_info = @github.repository_info

      end

      if @repo_info[:error]

        Console.print_warning("Repository info: #{@repo_info[:error]}")

      else
        puts "Repository: #{@repo_info[:name]}"

        puts "Description: #{@repo_info[:description]}" if @repo_info[:description]

        puts "Language: #{@repo_info[:language]}" if @repo_info[:language]

        puts "Stars: #{@repo_info[:stars]}"

        puts "Forks: #{@repo_info[:forks]}"

      end

    end

    Console.pause

  end

  def handle_configuration
    Console.print_header("Configuration")

    puts "Current Configuration:"
    puts "Default Model: #{@config["default_model"]}"

    puts "Autonomous Mode: #{@config["autonomous_mode"] ? "Enabled" : "Disabled"}"
    puts "Claude Tracking: #{@config["cognitive_tracking"] ? "Enabled" : "Disabled"}"

    puts "Knowledge Store: #{@config["knowledge_store"] ? "Enabled" : "Disabled"}"

    puts

    options = ["Back", "Edit API Keys", "Toggle Autonomous Mode", "Toggle Claude Tracking", "Toggle Knowledge Store"]

    choice = Console.select_option("Configuration Options:", options)

    case choice
    when "Edit API Keys"

      edit_api_keys
    when "Toggle Autonomous Mode"

      @config["autonomous_mode"] = !@config["autonomous_mode"]

      Configuration.save(@config)

      Console.print_success("Autonomous mode #{@config["autonomous_mode"] ? "enabled" : "disabled"}")

    when "Toggle Claude Tracking"

      @config["cognitive_tracking"] = !@config["cognitive_tracking"]

      Configuration.save(@config)

      Console.print_success("Claude tracking #{@config["cognitive_tracking"] ? "enabled" : "disabled"}")

    when "Toggle Knowledge Store"

      @config["knowledge_store"] = !@config["knowledge_store"]

      Configuration.save(@config)

      Console.print_success("Knowledge store #{@config["knowledge_store"] ? "enabled" : "disabled"}")

    end

    Console.pause unless choice == "Back"

  end

  def edit_api_keys
    Console.print_header("API Key Configuration")

    if Console.ask_yes_no("Update Anthropic API key?", default: false)
      @config["anthropic_api_key"] = Console.ask_password("Anthropic API key")

    end
    if Console.ask_yes_no("Update OpenAI API key?", default: false)

      @config["openai_api_key"] = Console.ask_password("OpenAI API key")

    end
    if Console.ask_yes_no("Update GitHub token?", default: false)

      @config["github_token"] = Console.ask_password("GitHub token")

    end
    Configuration.save(@config)

    Console.print_success("Configuration saved")

  end
  def handle_web_scraping

    Console.print_header("Intelligent Web Scraping")

    unless @scraper.available?
      Console.print_error("Web scraping unavailable - install ferrum gem")

      Console.pause
      return

    end

    url = Console.ask("Target URL")

    return if url.empty?

    objective = Console.ask("Scraping objective", default: "Extract main content")
    OpenBSDSandbox.setup_network_sandbox

    Console.spinner("Scraping and analyzing...") do
      @scrape_result = @scraper.scrape_with_reasoning(url, @llm, objective)
    end
    if @scrape_result[:error]

      Console.print_error("Error: #{@scrape_result[:error]}")

    else
      Console.print_header("Scraping Results")

      puts @scrape_result[:content][0..1000]

      puts "..." if @scrape_result[:content].length > 1000

      if Console.ask_yes_no("Save results?", default: false)

        filename = Console.ask("Filename", default: "scrape_results.txt")

        File.write(filename, @scrape_result.to_json)
        Console.print_success("Saved to #{filename}")

        @knowledge.add_document(@scrape_result[:content], "scraped_#{objective[0..20]}")

        Console.print_success("Added to knowledge base")

      end
    end

    Console.pause

  end

  def handle_git_operations
    Console.print_header("Git Operations")

    operations = ["Back", "Repository Status", "Create Branch", "Commit Changes"]
    choice = Console.select_option("Git Operations:", operations)

    case choice
    when "Repository Status"

      show_git_status
    when "Create Branch"

      create_git_branch

    when "Commit Changes"

      commit_git_changes

    end

    Console.pause unless choice == "Back"

  end

  def show_git_status
    info = @github.repository_info

    if info[:error]
      Console.print_warning("Repository info: #{info[:error]}")

    else
      puts "Repository: #{info[:name]}"

      puts "Description: #{info[:description]}" if info[:description]

      puts "Language: #{info[:language]}" if info[:language]

      puts "Stars: #{info[:stars]}"

      puts "Forks: #{info[:forks]}"

    end

    begin

      status = `git status --porcelain`.strip

      if status.empty?
        Console.print_success("Working directory clean")

      else

        puts "Changes:"

        puts status

      end

    rescue

      Console.print_error("Git not available")

    end

  end

  def create_git_branch

    branch_name = Console.ask("Branch name")

    return if branch_name.empty?
    begin

      system("git checkout -b #{branch_name}")

      Console.print_success("Branch #{branch_name} created")
    rescue

      Console.print_error("Failed to create branch")

    end

  end

  def commit_git_changes

    message = Console.ask("Commit message")

    return if message.empty?
    begin

      system("git add .")

      system("git commit -m \"#{message}\"")
      Console.print_success("Changes committed")

    rescue

      Console.print_error("Failed to commit changes")

    end

  end

  def handle_autonomous_mode

    Console.print_header("Autonomous Mode")

    unless @llm.autonomous_mode?
      Console.print_error("Autonomous mode requires LangchainRB and API keys")

      Console.pause
      return

    end

    task = Console.ask("Autonomous task description")

    return if task.empty?

    Console.print_warning("Autonomous mode can modify files and execute code")
    return unless Console.ask_yes_no("Continue?", default: false)

    @cognitive.add_task("autonomous", 2.0)
    Console.spinner("Executing autonomous task...") do

      @autonomous_result = @llm.generate_response(task)
    end
    Console.print_header("Autonomous Results")

    puts @autonomous_result[:content] if @autonomous_result[:content]

    Console.print_error("Error: #{@autonomous_result[:error]}") if @autonomous_result[:error]
    Console.pause

  end

  def format_scan_result(result)
    "Files: #{result[:files].size}\nTechnologies: #{result[:technologies].join(", ")}"

  end
  def cleanup

    @watcher&.stop_watching

    @scraper&.cleanup
  end

end

def check_dependencies

  missing = []

  missing << "langchainrb (for AI)" unless LANGCHAIN_AVAILABLE
  missing << "ferrum (for web scraping)" unless FERRUM_AVAILABLE

  missing << "octokit (for GitHub)" unless OCTOKIT_AVAILABLE

  missing << "rugged (for Git)" unless RUGGED_AVAILABLE

  missing << "listen (for file watching)" unless LISTEN_AVAILABLE

  missing << "parser rubocop-ast (for analysis)" unless AST_AVAILABLE

  missing << "pledge (for OpenBSD sandbox)" unless PLEDGE_AVAILABLE

  return if missing.empty?

  puts "Optional dependencies missing:"

  missing.each { |dep| puts "  - #{dep}" }
  puts "\nInstall: gem install langchainrb ferrum octokit rugged listen parser rubocop-ast pledge"
  puts "Tool works with limited features without these.\n"

  puts

end

