#!/usr/bin/env ruby
# frozen_string_literal: true

# CRC - Claude Ruby CLI
# Autonomous AI coding assistant with Claude load awareness

require "yaml"
require "json"

require "fileutils"
require "pathname"

require "logger"

require "concurrent-ruby"

require "digest"

require "io/console"

require "langchainrb"

require "octokit"

RUGGED_AVAILABLE = begin

  require "rugged"

  true
rescue LoadError

  false

end

LISTEN_AVAILABLE = begin

  require "listen"

  true
rescue LoadError

  false

end

AST_AVAILABLE = begin

  require "parser/current"

  require "rubocop/ast"
  true

rescue LoadError

  false

end

FERRUM_AVAILABLE = begin

  require "ferrum"

  true
rescue LoadError

  false

end

PLEDGE_AVAILABLE = begin

  require "pledge"

  true
rescue LoadError

  RbConfig::CONFIG["host_os"] =~ /openbsd/

end

# Cross-platform utilities

class PlatformDetector

  def self.platform_name
    host_os = RbConfig::CONFIG["host_os"]

    return :openbsd if host_os =~ /openbsd/

    return :cygwin if host_os =~ /cygwin/

    return :termux if ENV["PREFIX"] == "/data/data/com.termux/files/usr"

    return :windows if host_os =~ /mswin|mingw/

    return :macos if host_os =~ /darwin/

    return :linux if host_os =~ /linux/

    :unknown

  end

  def self.shell_command_prefix

    %i[windows cygwin].include?(platform_name) ? "cmd /c" : ""

  end
end

class CrossPlatformPath

  def self.home_directory

    ENV["HOME"] || ENV["USERPROFILE"] || Dir.pwd
  end

  def self.config_directory

    case PlatformDetector.platform_name

    when :windows, :cygwin
      File.join(home_directory, "AppData", "Roaming", "crc")

    when :termux

      prefix = ENV["PREFIX"] || "/data/data/com.termux/files/usr"

      File.join(prefix, "etc", "crc")

    else

      xdg_config = ENV["XDG_CONFIG_HOME"] || File.join(home_directory, ".config")

      File.join(xdg_config, "crc")

    end

  end

  def self.config_file

    File.join(config_directory, "config.yml")

  end
  def self.ensure_config_directory

    FileUtils.mkdir_p(config_directory)

  end
end

class AtomicFileWriter

  def self.write(filepath, content)

    temp_path = "#{filepath}.tmp.#{Process.pid}.#{Time.now.to_i}"
    begin

      File.open(temp_path, "w") do |temp_file|

        temp_file.write(content)
        temp_file.fsync if temp_file.respond_to?(:fsync)

      end

      File.rename(temp_path, filepath)

      true

    rescue => e
      File.unlink(temp_path) if File.exist?(temp_path)

      raise e

    end

  end

end

# Configuration management

class Configuration

  DEFAULT_CONFIG = {
    "anthropic_api_key" => nil,

    "openai_api_key" => nil,

    "github_token" => nil,

    "default_model" => "anthropic",

    "max_file_size" => 100_000,

    "excluded_dirs" => [".git", "node_modules", "vendor", "tmp"],

    "supported_extensions" => [".rb", ".py", ".js", ".ts", ".md", ".yml", ".yaml"],

    "log_level" => "INFO",

    "autonomous_mode" => false,

    "working_directory" => Dir.pwd,

    "cognitive_tracking" => true,

    "knowledge_store" => true

  }.freeze

  def self.load

    CrossPlatformPath.ensure_config_directory

    config_file = CrossPlatformPath.config_file
    File.exist?(config_file) ? (YAML.load_file(config_file) || DEFAULT_CONFIG.dup) : DEFAULT_CONFIG.dup

  rescue => e

    puts "Config error: #{e.message}"
    DEFAULT_CONFIG.dup

  end

  def self.save(config)

    AtomicFileWriter.write(CrossPlatformPath.config_file, config.to_yaml)

  end
end

# Console utilities

class Console

  def self.print_header(text)
    puts

    puts "=" * 60

    puts "  #{text}"

    puts "=" * 60

    puts

  end

  def self.print_status(type, text)

    symbols = { success: "*", error: "!", warning: "-", info: ">" }

    puts "#{symbols[type]} #{text}"
  end

  %i[success error warning info].each do |type|

    define_singleton_method("print_#{type}") { |text| print_status(type, text) }

  end
  def self.ask(prompt, default: nil)

    prompt_text = default ? "#{prompt} [#{default}]" : prompt

    print "#{prompt_text}: "
    input = $stdin.gets.chomp

    input.empty? ? default : input

  end

  def self.ask_password(prompt)

    print "#{prompt}: "

    password = $stdin.noecho(&:gets).chomp
    puts

    password

  end

  def self.ask_yes_no(prompt, default: true)

    default_text = default ? "[Y/n]" : "[y/N]"

    print "#{prompt} #{default_text}: "
    input = $stdin.gets.chomp.downcase

    return default if input.empty?

    input.start_with?("y")

  end

  def self.select_option(prompt, options)

    puts prompt

    puts
    options.each_with_index { |option, i| puts "  #{i + 1}. #{option}" }

    loop do

      print "\nSelect (1-#{options.length}): "

      input = $stdin.gets.chomp.to_i
      return options[input - 1] if input.between?(1, options.length)

      print_error("Invalid choice")

    end

  end

  def self.pause(message = "Press Enter...")

    print message

    $stdin.gets
  end

  def self.clear_screen

    system("clear") || system("cls")

  end
  def self.spinner(message)

    chars = %w[| / - \\]

    i = 0
    thread = Thread.new do

      loop do

        print "\r#{chars[i % chars.length]} #{message}"
        i += 1

        sleep(0.1)

      end

    end

    yield if block_given?

    thread.kill

    print "\r* #{message}\n"
  end

end

# Logger setup

class CLILogger

  def self.setup(level = "INFO")
    logger = Logger.new($stdout)

    logger.level = Logger.const_get(level.upcase)

    logger.formatter = proc { |severity, datetime, progname, msg| "[#{datetime.strftime("%H:%M:%S")}] #{severity}: #{msg}\n" }

    logger

  end

end

# Simple Claude tracking (7±2 rule)

class CognitiveTracker

  def initialize(enabled = true)
    @enabled = enabled

    @tasks = []

    @max_capacity = 7

  end

  def add_task(description, weight = 1.0)

    return unless @enabled

    @tasks << { desc: description[0..30], weight: weight, time: Time.now }
    @tasks.shift if @tasks.size > @max_capacity

  end
  def current_load

    @tasks.sum { |task| task[:weight] }

  end
  def overloaded?

    current_load > @max_capacity

  end
  def status

    { load: current_load.round(1), capacity: @max_capacity, tasks: @tasks.size }

  end
  def clear

    @tasks.clear

  end
end

# File-based knowledge store

class KnowledgeStore

  def initialize(enabled = true, store_dir = "data/knowledge")
    @enabled = enabled

    @store_dir = store_dir

    FileUtils.mkdir_p(@store_dir) if @enabled

  end

  def add_document(content, title = nil)

    return false unless @enabled && content

    filename = "#{Time.now.to_i}_#{title&.gsub(/[^a-zA-Z0-9]/, '_') || 'doc'}.txt"
    filepath = File.join(@store_dir, filename)

    File.write(filepath, content)
    true

  rescue
    false

  end

  def search(query, limit = 5)

    return [] unless @enabled && query

    results = []
    Dir.glob(File.join(@store_dir, "*.txt")).each do |file|

      content = File.read(file)
      if content.downcase.include?(query.downcase)

        results << {

          content: content,

          file: File.basename(file),

          score: calculate_score(query, content)

        }

      end

    end

    results.sort_by { |r| -r[:score] }.first(limit)

  rescue

    []
  end

  private

  def calculate_score(query, content)

    query_words = query.downcase.split
    content_words = content.downcase.split
    (query_words & content_words).size.to_f / query_words.size

  end

end

# LLM fallback handler

class LLMFallback

  def initialize(config, logger)
    @config = config

    @logger = logger

    @providers = setup_providers

    @cooldowns = {}

  end

  def route_query(query, context: nil)

    [@config["default_model"], "mock"].each do |provider|

      next if in_cooldown?(provider)
      begin

        response = send("#{provider}_request", query, context)

        return response unless response[:error]
        add_cooldown(provider, 60)

      rescue => e

        @logger.error("#{provider}: #{e.message}")
        add_cooldown(provider, 120)

      end

    end

    { content: "All providers failed", error: true }

  end

  private
  def setup_providers

    providers = [@config["default_model"]]
    providers << "mock" unless providers.include?("mock")
    providers

  end

  def in_cooldown?(provider)

    @cooldowns[provider] && Time.now < @cooldowns[provider]

  end
  def add_cooldown(provider, seconds)

    @cooldowns[provider] = Time.now + seconds

  end
  def anthropic_request(query, context)

    provider = LLMProvider.new(@config, @logger)

    provider.generate_response(query, context: context)
  end

  def openai_request(query, context)

    config = @config.merge("default_model" => "openai")

    provider = LLMProvider.new(config, @logger)
    provider.generate_response(query, context: context)

  end

  def mock_request(query, context)

    { content: "Mock response for: #{query[0..50]}...", model: "mock" }

  end
end

# OpenBSD security sandbox

class OpenBSDSandbox

  def self.available?
    PLEDGE_AVAILABLE

  end

  def self.setup_filesystem_sandbox

    return unless available?

    begin
      Pledge.pledge("stdio rpath wpath cpath fattr")

    rescue NameError
      begin

        require "fiddle"

        Fiddle::Function.new(

          Fiddle::Handle::DEFAULT["pledge"],

          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],

          Fiddle::TYPE_INT

        ).call("stdio rpath wpath cpath fattr", nil)

      rescue

        # Silent fail on non-OpenBSD

      end

    rescue

      # Silent fail

    end

  end

  def self.setup_network_sandbox

    return unless available?

    begin
      Pledge.pledge("stdio rpath wpath cpath inet dns")

    rescue NameError
      begin

        require "fiddle"

        Fiddle::Function.new(

          Fiddle::Handle::DEFAULT["pledge"],

          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],

          Fiddle::TYPE_INT

        ).call("stdio rpath wpath cpath inet dns", nil)

      rescue

        # Silent fail

      end

    rescue

      # Silent fail

    end

  end

end

# Web scraping with visual reasoning

class WebScraper

  def initialize(config, logger)
    @config = config

    @logger = logger

    @browser = nil

  end

  def available?

    FERRUM_AVAILABLE

  end
  def setup_browser

    return unless available?

    @browser = Ferrum::Browser.new(
      headless: true,

      window_size: [1280, 1024],
      timeout: 30,

      js_errors: false,

      process_timeout: 60

    )

  end

  def scrape_with_reasoning(url, llm_client, objective)

    return { error: "Web scraping unavailable" } unless available? && @browser

    begin
      @browser.goto(url)

      @browser.wait_for_idle(1)
      page_source = @browser.body

      screenshot_path = "/tmp/screenshot_#{Time.now.to_i}.png"

      @browser.screenshot(path: screenshot_path)
      screenshot_data = File.read(screenshot_path)

      File.unlink(screenshot_path)

      reasoning_prompt = build_scraping_prompt(page_source, objective)
      if llm_client.available?

        response = llm_client.generate_response(reasoning_prompt)
        parse_scraping_instructions(response[:content], page_source)
      else

        { content: page_source[0..5000], links: extract_basic_links(page_source) }

      end

    rescue => e

      @logger.error("Scraping: #{e.message}")

      { error: e.message }
    end

  end

  def cleanup

    @browser&.quit

  end
  private

  def build_scraping_prompt(html_content, objective)

    <<~PROMPT
    Analyze this webpage and determine what content to extract for: #{objective}
    HTML Content (first 2000 chars):

    #{html_content[0..2000]}

    Based on the objective and HTML content, provide:
    1. Specific CSS selectors for relevant content

    2. Links to follow for more information
    3. Key data points to extract

    Format as JSON with 'selectors', 'links', and 'data' fields.

    PROMPT

  end
  def extract_basic_links(html)

    html.scan(/href=[""]([^"']+)["']/i).flatten.select { |link| link.start_with?("http") }

  end
  def parse_scraping_instructions(llm_response, html_content)

    { content: html_content[0..5000], instructions: llm_response }

  end
end

# LangchainRB filesystem and web tools

class ToolsProvider

  def initialize(config, logger)
    @config = config

    @logger = logger

  end

  def available_tools

    tools = []

    if LANGCHAIN_AVAILABLE
      tools << create_tool { create_filesystem_tool }

      tools << create_tool { create_search_tool } if ENV["SERP_API_KEY"]
      tools << create_tool { create_code_interpreter_tool }

      tools << create_tool { create_database_tool } if ENV["DATABASE_URL"]

    end

    tools.compact

  end

  private
  def create_tool

    yield
  rescue => e
    @logger.error("Tool: #{e.message}")

    nil

  end

  def create_filesystem_tool

    Langchain::Tool::FileSystem.new(

      read_permission: true,
      write_permission: @config["autonomous_mode"]

    )

  end

  def create_search_tool

    Langchain::Tool::GoogleSearch.new(api_key: ENV["SERP_API_KEY"])

  end
  def create_code_interpreter_tool

    Langchain::Tool::RubyCodeInterpreter.new(timeout: 30)

  end
  def create_database_tool

    Langchain::Tool::Database.new(connection_string: ENV["DATABASE_URL"])

  end
end

# LLM Integration with enhanced capabilities

class LLMProvider

  def initialize(config, logger, tools = [], cognitive_monitor = nil)
    @config = config

    @logger = logger

    @tools = tools

    @cognitive_monitor = cognitive_monitor

    @client = setup_client

    @assistant = setup_assistant if LANGCHAIN_AVAILABLE

  end

  def available?

    @client || (@assistant && LANGCHAIN_AVAILABLE)

  end
  def autonomous_mode?

    @config["autonomous_mode"] && @assistant

  end
  def set_cognitive_monitor(monitor)

    @cognitive_monitor = monitor

  end
  def generate_response(prompt, context: nil)

    return { error: "LLM unavailable" } unless available?

    begin
      if autonomous_mode?

        autonomous_response(prompt, context)
      else

        full_prompt = context ? "#{context}\n\n#{prompt}" : prompt

        @cognitive_monitor&.add_concept(prompt[0..50], 0.3)

        case @config["default_model"]

        when "anthropic" then anthropic_response(full_prompt)
        when "openai" then openai_response(full_prompt)
        else mock_response(full_prompt)

        end

      end

    rescue => e

      @logger.error("LLM: #{e.message}")

      { error: "LLM failed: #{e.message}" }

    end

  end

  def autonomous_response(prompt, context)

    return { error: "Assistant not available" } unless @assistant

    begin
      @assistant.add_message(role: "user", content: context ? "#{context}\n\n#{prompt}" : prompt)

      result = @assistant.run(auto_tool_execution: true)
      { content: result.messages.last&.content || "No response", model: "autonomous" }

    rescue => e

      @logger.error("Autonomous: #{e.message}")
      { error: e.message }

    end

  end

  private

  def setup_assistant

    return nil unless LANGCHAIN_AVAILABLE
    llm_client = setup_client
    return nil unless llm_client

    Langchain::Assistant.new(
      llm: llm_client,

      instructions: "You are an autonomous coding assistant with filesystem and web access. Always use tools when available to gather information and perform actions. Be thorough but concise in your responses.",
      tools: @tools,

      auto_tool_execution: true

    )

  rescue => e

    @logger.error("Assistant setup: #{e.message}")

    nil

  end

  def setup_client

    return nil unless LANGCHAIN_AVAILABLE

    case @config["default_model"]
    when "anthropic"

      return nil unless @config["anthropic_api_key"]
      Langchain::LLM::Anthropic.new(api_key: @config["anthropic_api_key"])

    when "openai"

      return nil unless @config["openai_api_key"]

      Langchain::LLM::OpenAI.new(api_key: @config["openai_api_key"])

    end

  rescue => e

    @logger.error("LLM setup: #{e.message}")

    nil

  end

  def anthropic_response(prompt)

    return mock_response(prompt) unless @client

    response = @client.chat(messages: [{ role: "user", content: prompt }])
    { content: response.chat_completion, model: "claude-3-sonnet" }

  end
  def openai_response(prompt)

    return mock_response(prompt) unless @client

    response = @client.chat(messages: [{ role: "user", content: prompt }])
    { content: response.chat_completion, model: "gpt-4" }

  end
  def mock_response(prompt)

    { content: "Mock response for: #{prompt[0..100]}...", model: "mock" }

  end
end

# Code analysis using AST

class CodeAnalyzer

  def initialize(logger)
    @logger = logger

  end

  def available?

    AST_AVAILABLE

  end
  def analyze_file(filepath)

    return { error: "AST analysis unavailable" } unless available?

    return { error: "File not found" } unless File.exist?(filepath)
    begin

      content = File.read(filepath)

      return { error: "File too large" } if content.size > 1_000_000
      case File.extname(filepath)

      when ".rb"

        analyze_ruby_code(content, filepath)
      else

        { error: "Unsupported file type" }

      end

    rescue => e

      @logger.error("Analysis: #{e.message}")

      { error: e.message }

    end

  end

  private

  def analyze_ruby_code(content, filepath)

    ast = Parser::CurrentRuby.parse(content)
    processor = RuboCop::AST::ProcessedSource.new(content, RUBY_VERSION.to_f, filepath)
    {

      file: filepath,

      lines: content.lines.count,
      classes: count_nodes(ast, :class),

      methods: count_nodes(ast, :def),

      complexity: calculate_complexity(ast),

      issues: find_issues(processor)

    }

  rescue Parser::SyntaxError => e

    { error: "Syntax error: #{e.message}" }

  end

  def count_nodes(node, type)

    return 0 unless node.is_a?(Parser::AST::Node)

    count = node.type == type ? 1 : 0
    node.children.each { |child| count += count_nodes(child, type) }

    count
  end

  def calculate_complexity(node)

    return 1 unless node.is_a?(Parser::AST::Node)

    complexity = case node.type
                 when :if, :case, :while, :until, :for, :rescue then 1

                 else 0
                 end

    node.children.each { |child| complexity += calculate_complexity(child) }

    complexity

  end
  def find_issues(processor)

    issues = []

    issues << "Long file (#{processor.lines.count} lines)" if processor.lines.count > 200
    issues << "High complexity detected" if calculate_complexity(processor.ast) > 20

    issues

  end

end

# GitHub integration

class GitHubIntegration

  def initialize(config, logger)
    @config = config

    @logger = logger

    @client = setup_client

  end

  def available?

    OCTOKIT_AVAILABLE && @client

  end
  def repository_info

    return { error: "GitHub unavailable" } unless available?

    begin
      repo_path = find_git_repo

      return { error: "Not a git repository" } unless repo_path
      remote_url = `git config --get remote.origin.url`.strip

      return { error: "No remote origin" } if remote_url.empty?

      repo_name = extract_repo_name(remote_url)
      repo_info = @client.repository(repo_name)

      {
        name: repo_info.name,

        description: repo_info.description,
        stars: repo_info.stargazers_count,

        forks: repo_info.forks_count,

        language: repo_info.language

      }

    rescue => e

      @logger.error("GitHub: #{e.message}")

      { error: e.message }

    end

  end

  private

  def setup_client

    return nil unless OCTOKIT_AVAILABLE && @config["github_token"]
    Octokit::Client.new(access_token: @config["github_token"])
  rescue => e

    @logger.error("GitHub setup: #{e.message}")
    nil

  end

  def find_git_repo

    current_dir = Dir.pwd

    while current_dir != "/"
      return current_dir if Dir.exist?(File.join(current_dir, ".git"))

      current_dir = File.dirname(current_dir)

    end

    nil

  end

  def extract_repo_name(remote_url)

    remote_url.gsub(/.*[\/:]([^\/]+\/[^\/]+)\.git$/, '\1')

  end
end

# Project scanner

class ProjectScanner

  def initialize(config, logger)
    @config = config

    @logger = logger

  end

  def scan_project(directory = Dir.pwd)

    {

      root: directory,
      files: scan_files(directory),

      structure: scan_structure(directory),

      technologies: detect_technologies(directory)

    }

  end

  private

  def scan_files(directory)

    files = []
    excluded = @config["excluded_dirs"]
    extensions = @config["supported_extensions"]

    Dir.glob("#{directory}/**/*").select do |path|

      File.file?(path) &&

        extensions.include?(File.extname(path)) &&
        excluded.none? { |dir| path.include?("/#{dir}/") }

    end.each do |file|

      files << {

        path: file.gsub("#{directory}/", ""),

        size: File.size(file),

        modified: File.mtime(file)

      }

    end

    files

  end

  def scan_structure(directory)
    structure = {}

    Dir.glob("#{directory}/*").each do |path|
      name = File.basename(path)

      next if @config["excluded_dirs"].include?(name)

      if File.directory?(path)

        structure[name] = "directory"

      else
        structure[name] = File.extname(path)[1..-1] || "file"

      end

    end

    structure

  end

  def detect_technologies(directory)

    tech = []

    tech << "Ruby" if File.exist?(File.join(directory, "Gemfile"))
    tech << "Rails" if File.exist?(File.join(directory, "config/application.rb"))

    tech << "Node.js" if File.exist?(File.join(directory, "package.json"))
    tech << "Python" if File.exist?(File.join(directory, "requirements.txt"))

    tech << "Docker" if File.exist?(File.join(directory, "Dockerfile"))

    tech

  end

end
# File watcher

class FileWatcher

  def initialize(config, logger)
    @config = config

    @logger = logger

    @listener = nil

    @watching = false

  end

  def available?

    LISTEN_AVAILABLE

  end
  def start_watching(directory = Dir.pwd, &block)

    return false unless available?

    @listener = Listen.to(directory, only: /\.(rb|py|js|ts|md|yml|yaml)$/) do |modified, added, removed|
      block.call(modified: modified, added: added, removed: removed)

    end
    @listener.start

    @watching = true

    true
  rescue => e

    @logger.error("File watching: #{e.message}")

    false

  end

  def stop_watching

    return unless @watching && @listener

    @listener.stop
    @watching = false

  end
  def watching?

    @watching

  end
end

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

# Main execution

if __FILE__ == $0

  check_dependencies
  begin

    cli = CognitiveRubyCLI.new

    cli.run
  rescue Interrupt

    puts "\nExiting..."

    exit(0)

  rescue => e

    puts "Fatal error: #{e.message}"

    puts "Check configuration and dependencies"

    exit(1)

  end

end

