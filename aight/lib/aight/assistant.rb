# frozen_string_literal: true
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

