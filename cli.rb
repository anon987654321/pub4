#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - Consolidated single-file implementation
# Zero gem dependencies, pure stdlib, master.yml integration
# Prioritizes API mode (OpenRouter) over browser automation

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "digest"
require "io/console"

# ============================================================================
# MasterConfig - Loads and enforces master.yml governance rules
# ============================================================================

class MasterConfig
  attr_reader :version, :banned_tools, :golden_rule, :forbidden_patterns, :config

  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze

  DANGEROUS_PATTERNS = [
    "rm -rf /",
    "rm -rf /*",
    "rm -rf ~",
    "rm -rf $HOME",
    "> /etc/passwd",
    "> /etc/shadow",
    "> /etc/sudoers",
    "| sh",
    "| bash",
    "curl | sh",
    "wget | sh"
  ].freeze

  def initialize
    @config = load_config
    @version = @config.dig("meta", "version") || "unknown"
    @golden_rule = @config.dig("principles", "golden_rule") || "preserve_then_improve_never_break"
    @banned_tools = @config.dig("constraints", "banned_tools") || []
    @forbidden_patterns = @config.dig("principles", "anti_truncation", "forbidden") || []
    @max_function_lines = @config.dig("thresholds", "size", "function_lines") || 20
    @max_nesting = @config.dig("thresholds", "complexity", "nesting") || 3
    
    @banned_regex = if @banned_tools.any?
      Regexp.new("\\b(#{@banned_tools.map { |t| Regexp.escape(t) }.join('|')})\\b")
    end
  end

  def loaded
    !@config.empty?
  end

  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    path ? YAML.safe_load_file(path, aliases: false) : {}
  rescue => e
    warn "master.yml error: #{e.message}"
    {}
  end

  def banned?(command)
    @banned_regex ? command =~ @banned_regex : false
  end

  def banned_tool(command)
    return nil unless @banned_regex && command =~ @banned_regex
    match = command.match(@banned_regex)
    match ? match[1] : nil
  end

  def dangerous?(command)
    DANGEROUS_PATTERNS.any? { |p| command.include?(p) }
  end

  def suggest_alternative(tool)
    case tool
    when "sed" then "use zsh: ${var//old/new}"
    when "awk" then "use zsh: ${${(s: :)line}[2]}"
    when "bash" then "use zsh patterns"
    when "wc" then "use zsh: ${#lines}"
    when "head" then "use zsh: ${lines[1,10]}"
    when "tail" then "use zsh: ${lines[-5,-1]}"
    when "python" then "use ruby"
    when "sudo" then "use doas"
    else "use zsh/ruby"
    end
  end

  def validate_no_truncation!(content)
    return unless loaded
    
    @forbidden_patterns.each do |pattern|
      if content.include?(pattern)
        raise "Anti-truncation violation: found '#{pattern}' in response"
      end
    end
  end

  def max_function_lines
    @max_function_lines
  end

  def max_nesting
    @max_nesting
  end

  def system_prompt_fragment
    return "" unless loaded
    
    <<~PROMPT
      ## GOVERNANCE (master.yml v#{@version})
      Golden Rule: #{@golden_rule}
      Banned Tools: #{@banned_tools.join(", ")}
      Thresholds: Functions ≤#{@max_function_lines} lines, Nesting ≤#{@max_nesting}
      Anti-Truncation: NEVER use #{@forbidden_patterns.join(", ")}
    PROMPT
  end
end

# ============================================================================
# Config - User configuration (~/.convergence/config.yml)
# ============================================================================

class Config
  CONFIG_DIR = File.expand_path("~/.convergence").freeze
  CONFIG_PATH = File.join(CONFIG_DIR, "config.yml").freeze

  attr_accessor :provider, :api_keys, :model

  def self.load
    new.tap(&:load!)
  end

  def initialize
    @provider = nil
    @api_keys = {}
    @model = nil
  end

  def load!
    return self unless File.exist?(CONFIG_PATH)
    
    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: false)
    return self unless data.is_a?(Hash)
    
    @provider = data["provider"]&.to_sym if data["provider"]
    @api_keys = data["api_keys"] || {}
    @model = data["model"]
    
    self
  rescue => e
    warn "Warning: Failed to load config: #{e.message}"
    self
  end

  def save
    FileUtils.mkdir_p(CONFIG_DIR)
    
    data = {
      "provider" => @provider ? @provider.to_s : nil,
      "api_keys" => @api_keys,
      "model" => @model
    }
    
    File.write(CONFIG_PATH, YAML.dump(data))
    File.chmod(0600, CONFIG_PATH)
    
    true
  rescue => e
    warn "Warning: Failed to save config: #{e.message}"
    false
  end

  def configured?
    !@provider.nil? && !api_key_for(@provider).nil?
  end

  def api_key_for(provider)
    @api_keys[provider.to_s]
  end

  def set_api_key(provider, key)
    @api_keys[provider.to_s] = key
  end
end

# ============================================================================
# APIClient - Multi-provider API client with OpenAI-compatible interface
# ============================================================================

class APIClient
  PROVIDERS = {
    openrouter: {
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      models: {
        "deepseek-r1" => "deepseek/deepseek-r1",
        "claude-3.5" => "anthropic/claude-3.5-sonnet",
        "gpt-4o" => "openai/gpt-4o",
        "gemini-2.0" => "google/gemini-2.0-flash-exp"
      },
      default_model: "deepseek/deepseek-r1"
    },
    anthropic: {
      name: "Anthropic",
      base_url: "https://api.anthropic.com/v1",
      models: {
        "claude-opus-4" => "claude-opus-4-20250514",
        "claude-sonnet-4" => "claude-sonnet-4-20250514",
        "claude-3.5" => "claude-3-5-sonnet-20241022"
      },
      default_model: "claude-sonnet-4-20250514",
      format: :anthropic
    },
    openai: {
      name: "OpenAI",
      base_url: "https://api.openai.com/v1",
      models: {
        "gpt-4o" => "gpt-4o",
        "gpt-4o-mini" => "gpt-4o-mini",
        "gpt-4-turbo" => "gpt-4-turbo-preview"
      },
      default_model: "gpt-4o"
    }
  }.freeze

  attr_reader :provider, :model, :messages

  def initialize(provider:, api_key:, model: nil, master_config: nil)
    @provider = provider.to_sym
    @api_key = api_key
    @config = PROVIDERS[@provider] or raise "Unknown provider: #{provider}"
    @model = model || @config[:default_model]
    @messages = []
    @master_config = master_config
  end

  def send_message(message, &block)
    @messages << { role: "user", content: message }
    
    case @config[:format]
    when :anthropic
      send_anthropic(&block)
    else
      send_openai_compatible(&block)
    end
  end

  def clear_history
    @messages = []
  end

  def models
    @config[:models]
  end

  def switch_model(new_model)
    if @config[:models].values.include?(new_model) || @config[:models].key?(new_model)
      @model = @config[:models][new_model] || new_model
      true
    else
      false
    end
  end

  private

  def send_openai_compatible(&block)
    uri = URI("#{@config[:base_url]}/chat/completions")
    headers = build_headers
    
    body = {
      model: @model,
      messages: @messages,
      stream: block_given?
    }
    
    if block_given?
      send_streaming_request(uri, headers, body, &block)
    else
      send_non_streaming_request(uri, headers, body)
    end
  end

  def send_anthropic(&block)
    uri = URI("#{@config[:base_url]}/messages")
    headers = build_anthropic_headers
    
    body = {
      model: @model,
      messages: @messages,
      max_tokens: 8192,
      stream: block_given?
    }
    
    if block_given?
      send_streaming_request(uri, headers, body, format: :anthropic, &block)
    else
      send_non_streaming_request(uri, headers, body, format: :anthropic)
    end
  end

  def build_headers
    {
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json",
      "HTTP-Referer" => "https://github.com/anon987654321/pub4",
      "X-Title" => "Convergence CLI"
    }
  end

  def build_anthropic_headers
    {
      "x-api-key" => @api_key,
      "anthropic-version" => "2023-06-01",
      "Content-Type" => "application/json"
    }
  end

  def send_streaming_request(uri, headers, body, format: :openai)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)
      
      accumulated = ""
      
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise "API error (#{response.code}): #{response.body[0..200]}"
        end
        
        response.read_body do |chunk|
          chunk.each_line do |line|
            next if line.strip.empty?
            next unless line.start_with?("data: ")
            
            data = line[6..-1].strip
            next if data == "[DONE]"
            
            begin
              json = JSON.parse(data)
              
              delta = case format
              when :anthropic
                json.dig("delta", "text") if json["type"] == "content_block_delta"
              else
                json.dig("choices", 0, "delta", "content")
              end
              
              if delta
                accumulated << delta
                yield delta if block_given?
              end
            rescue JSON::ParserError
              # Skip invalid JSON
            end
          end
        end
      end
      
      @master_config&.validate_no_truncation!(accumulated)
      @messages << { role: "assistant", content: accumulated }
      accumulated
    end
  rescue => e
    "API Error: #{e.message}"
  end

  def send_non_streaming_request(uri, headers, body, format: :openai)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    
    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = JSON.generate(body)
    
    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "API error (#{response.code}): #{response.message}"
    end
    
    json = JSON.parse(response.body)
    
    content = case format
    when :anthropic
      json.dig("content", 0, "text")
    else
      json.dig("choices", 0, "message", "content")
    end
    
    @master_config&.validate_no_truncation!(content)
    @messages << { role: "assistant", content: content }
    content
  rescue => e
    "API Error: #{e.message}"
  end
end

# ============================================================================
# FileSystem - Local filesystem tools with sandboxing
# ============================================================================

class FileSystem
  attr_reader :base_path

  def initialize(base_path: Dir.pwd, master_config: nil)
    @base_path = File.expand_path(base_path)
    @master_config = master_config
  end

  def read(path:)
    safe_path = enforce_sandbox!(path)
    
    return { error: "file not found" } unless File.exist?(safe_path)
    return { error: "not a file" } unless File.file?(safe_path)
    
    content = File.read(safe_path)
    sha256 = Digest::SHA256.hexdigest(content)
    
    {
      path: path,
      content: content[0..50000],
      size: File.size(safe_path),
      sha256: sha256,
      truncated: content.size > 50000
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "failed to read: #{e.message}" }
  end

  def write(path:, content:)
    safe_path = enforce_sandbox!(path)
    
    FileUtils.mkdir_p(File.dirname(safe_path))
    File.write(safe_path, content)
    
    {
      success: true,
      path: path,
      size: File.size(safe_path),
      sha256: Digest::SHA256.hexdigest(content)
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "failed to write: #{e.message}" }
  end

  def list(path: ".", recursive: false)
    safe_path = enforce_sandbox!(File.join(@base_path, path))
    
    return { error: "not found" } unless File.exist?(safe_path)
    return { error: "not a directory" } unless File.directory?(safe_path)
    
    if recursive
      entries = Dir.glob(File.join(safe_path, "**/*"))
        .reject { |e| File.basename(e).start_with?(".") }
    else
      entries = Dir.entries(safe_path)
        .reject { |e| e.start_with?(".") }
        .map { |e| File.join(safe_path, e) }
    end
    
    files = entries.map do |entry|
      relative = entry.sub("#{@base_path}/", "")
      {
        name: relative,
        type: File.directory?(entry) ? "directory" : "file",
        size: File.file?(entry) ? File.size(entry) : nil
      }
    end
    
    {
      path: path,
      count: files.size,
      files: files.sort_by { |f| [f[:type] == "directory" ? 0 : 1, f[:name]] }
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "failed to list: #{e.message}" }
  end

  def search(query:, path: ".", case_sensitive: false)
    safe_path = enforce_sandbox!(File.join(@base_path, path))
    
    return { error: "not found" } unless File.exist?(safe_path)
    
    files = Dir.glob(File.join(safe_path, "**/*"))
      .select { |f| File.file?(f) }
      .reject { |f| File.basename(f).start_with?(".") }
    
    results = []
    
    files.each do |file|
      begin
        content = File.read(file)
        matches = []
        
        content.lines.each_with_index do |line, idx|
          if case_sensitive ? line.include?(query) : line.downcase.include?(query.downcase)
            matches << {
              line_number: idx + 1,
              line: line.strip[0..200]
            }
          end
        end
        
        if matches.any?
          relative = file.sub("#{@base_path}/", "")
          results << {
            file: relative,
            matches: matches.first(10)
          }
        end
      rescue
        next
      end
      
      break if results.size >= 50
    end
    
    {
      query: query,
      path: path,
      results_count: results.size,
      results: results
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "search failed: #{e.message}" }
  end

  def shell(command:, timeout: 30)
    if @master_config&.banned?(command)
      banned_tool = @master_config.banned_tool(command)
      return {
        error: "BLOCKED by master.yml: #{banned_tool}",
        alternative: @master_config.suggest_alternative(banned_tool)
      }
    end
    
    if @master_config&.dangerous?(command)
      return { error: "BLOCKED: dangerous pattern detected" }
    end
    
    shell_path = ["/usr/local/bin/zsh", "/bin/zsh", "/bin/sh"].find { |s| File.executable?(s) } || "/bin/sh"
    
    begin
      Timeout.timeout(timeout) do
        stdout, stderr, status = Open3.capture3(shell_path, "-c", command)
        
        {
          stdout: stdout[0..4000],
          stderr: stderr[0..1000],
          exit_code: status.exitstatus,
          success: status.success?
        }
      end
    rescue Timeout::Error
      { error: "command timeout after #{timeout}s" }
    rescue => e
      { error: e.message }
    end
  end

  def tree(path: ".", max_depth: 3)
    safe_path = enforce_sandbox!(File.join(@base_path, path))
    
    return { error: "not found" } unless File.exist?(safe_path)
    return { error: "not a directory" } unless File.directory?(safe_path)
    
    tree_output = build_tree(safe_path, "", 0, max_depth)
    
    {
      path: path,
      tree: tree_output
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "failed to build tree: #{e.message}" }
  end

  private

  def enforce_sandbox!(filepath)
    expanded = File.expand_path(filepath)
    unless expanded.start_with?(@base_path)
      raise SecurityError, "Access denied: #{filepath} outside sandbox"
    end
    expanded
  end

  def build_tree(dir, prefix, depth, max_depth)
    return "...\n" if depth >= max_depth
    
    entries = Dir.entries(dir)
      .reject { |e| e.start_with?(".") }
      .sort
    
    output = ""
    
    entries.each_with_index do |entry, idx|
      path = File.join(dir, entry)
      is_last = idx == entries.size - 1
      
      connector = is_last ? "└── " : "├── "
      output << "#{prefix}#{connector}#{entry}\n"
      
      if File.directory?(path)
        extension = is_last ? "    " : "│   "
        output << build_tree(path, prefix + extension, depth + 1, max_depth)
      end
    end
    
    output
  end
end

# ============================================================================
# ContextBuilder - Builds LLM context with master.yml governance
# ============================================================================

class ContextBuilder
  def initialize(master_config:, filesystem:)
    @master_config = master_config
    @filesystem = filesystem
  end

  def build_system_prompt
    prompt = <<~PROMPT
      You are a helpful coding assistant with access to filesystem tools.
      
      #{@master_config.system_prompt_fragment}
      
      ## Available Tools
      
      - read(path: string): Read a file with SHA256 hash for verification
      - write(path: string, content: string): Write content to a file
      - list(path: string, recursive: bool): List directory contents
      - search(query: string, path: string): Search for text in files
      - shell(command: string): Execute shell command (subject to master.yml restrictions)
      - tree(path: string, max_depth: int): Show directory tree structure
      
      ## Filesystem Context
      
      Working directory: #{@filesystem.base_path}
    PROMPT
    
    # Add Gemfile info if it exists
    gemfile_path = File.join(@filesystem.base_path, "Gemfile")
    if File.exist?(gemfile_path)
      prompt << "\n## Project Info\n\n"
      prompt << "This is a Ruby project with Gemfile.\n"
    end
    
    prompt
  end

  def add_project_context
    context = []
    
    # Try to read Gemfile
    gemfile_result = @filesystem.read(path: "Gemfile")
    if gemfile_result[:content]
      context << "## Gemfile\n\n```ruby\n#{gemfile_result[:content]}\n```"
    end
    
    # Try to read README
    ["README.md", "readme.md", "README"].each do |readme_file|
      readme_result = @filesystem.read(path: readme_file)
      if readme_result[:content]
        context << "## README\n\n#{readme_result[:content][0..2000]}"
        break
      end
    end
    
    context.join("\n\n")
  end
end

# ============================================================================
# ToolExecutor - Parses and executes JSON tool calls from LLM
# ============================================================================

class ToolExecutor
  def initialize(filesystem:)
    @filesystem = filesystem
  end

  def execute(tool_call_json)
    call = JSON.parse(tool_call_json)
    tool_name = call["tool"]
    params = call["params"] || {}
    
    case tool_name
    when "read"
      @filesystem.read(**params.transform_keys(&:to_sym))
    when "write"
      @filesystem.write(**params.transform_keys(&:to_sym))
    when "list"
      @filesystem.list(**params.transform_keys(&:to_sym))
    when "search"
      @filesystem.search(**params.transform_keys(&:to_sym))
    when "shell"
      @filesystem.shell(**params.transform_keys(&:to_sym))
    when "tree"
      @filesystem.tree(**params.transform_keys(&:to_sym))
    else
      { error: "unknown tool: #{tool_name}" }
    end
  rescue JSON::ParserError => e
    { error: "invalid JSON: #{e.message}" }
  rescue => e
    { error: "execution failed: #{e.message}" }
  end
end

# ============================================================================
# UI - Terminal interface module
# ============================================================================

module UI
  extend self

  def banner
    puts "\n╔═══════════════════════════════════════╗"
    puts "║   CONVERGENCE CLI v2.0                ║"
    puts "╚═══════════════════════════════════════╝\n"
  end

  def puts(text = "")
    Kernel.puts(text)
  end

  def prompt
    print "> "
    $stdin.gets&.chomp
  end

  def response(text)
    puts "\n#{text}\n"
  end

  def error(msg)
    puts "Error: #{msg}"
  end

  def status(msg)
    puts msg
  end

  def ask_yes_no(question, default: true)
    prompt_text = default ? "#{question} [Y/n]" : "#{question} [y/N]"
    print "#{prompt_text}: "
    answer = $stdin.gets&.chomp
    return default if answer.nil? || answer.empty?
    answer.downcase.start_with?("y")
  end

  def ask_choice(question, choices)
    puts question
    choices.each_with_index { |choice, i| puts "  #{i + 1}. #{choice}" }
    print "Enter number (1-#{choices.size}): "
    idx = $stdin.gets&.chomp&.to_i
    return nil if idx < 1 || idx > choices.size
    choices[idx - 1]
  end

  def ask_secret(prompt_text)
    print "#{prompt_text}: "
    password = $stdin.noecho(&:gets).chomp
    puts
    password
  end
end

# ============================================================================
# CLI - Main interactive loop
# ============================================================================

class CLI
  HELP = <<~HELP
    Commands:
      /help          Show this help
      /model NAME    Switch model
      /clear         Clear conversation history
      /tree [PATH]   Show file tree
      /read PATH     Read a file with SHA256
      /master        Show master.yml status
      /config        Show configuration
      /reset         Reset and reconfigure
      exit           Quit
  HELP

  def initialize
    @master_config = MasterConfig.new
    @config = Config.load
    @filesystem = FileSystem.new(master_config: @master_config)
    @context_builder = ContextBuilder.new(master_config: @master_config, filesystem: @filesystem)
    @tool_executor = ToolExecutor.new(filesystem: @filesystem)
    @client = nil
  end

  def run(args = [])
    # Handle command-line arguments
    if args.include?("--init")
      setup_wizard
      return
    end

    if args.include?("--master")
      show_master_status
      return
    end

    # Direct query mode
    if args.any? && !args.first.start_with?("--")
      query = args.join(" ")
      return run_direct_query(query)
    end

    # Interactive mode
    run_interactive
  end

  private

  def setup_wizard
    UI.banner
    UI.puts "\nWelcome! Let's configure your CLI.\n"

    # Select provider
    providers = APIClient::PROVIDERS.keys.map(&:to_s)
    UI.puts "\nAvailable providers:"
    providers.each { |p| UI.puts "  • #{p}" }
    UI.puts ""

    provider_name = UI.ask_choice("Select provider:", providers)
    provider = (provider_name || "openrouter").to_sym

    # Get API key
    api_key = prompt_api_key(provider)

    # Save config
    @config.provider = provider
    @config.set_api_key(provider, api_key)
    @config.save

    UI.status("\nConfiguration saved to ~/.convergence/config.yml")
    UI.status("Run 'ruby cli.rb' to start the interactive session")
  end

  def prompt_api_key(provider)
    UI.puts "\nYou'll need an API key for #{provider}."

    case provider
    when :openrouter
      UI.puts "Get your key at: https://openrouter.ai/keys"
    when :openai
      UI.puts "Get your key at: https://platform.openai.com/api-keys"
    when :anthropic
      UI.puts "Get your key at: https://console.anthropic.com/settings/keys"
    end

    UI.puts ""
    UI.ask_secret("Enter API key")
  end

  def run_interactive
    unless @config.configured?
      UI.error("Not configured. Run with --init to set up.")
      return
    end

    UI.banner
    UI.puts "Provider: #{@config.provider}"
    UI.puts "Model: #{@config.model || "default"}"
    UI.puts "Master.yml: v#{@master_config.version}" if @master_config.loaded
    UI.puts "\nType /help for commands\n"

    setup_client

    loop do
      input = UI.prompt
      break if input.nil? || input =~ /^(exit|quit)$/i
      next if input.strip.empty?

      if input.start_with?("/")
        handle_command(input)
      else
        handle_message(input)
      end
    end

    UI.status("\nSession ended")
  end

  def run_direct_query(query)
    unless @config.configured?
      UI.error("Not configured. Run with --init to set up.")
      return
    end

    setup_client
    
    print "Thinking..."
    response = @client.send_message(query)
    print "\r" + " " * 20 + "\r"
    
    UI.puts response
  end

  def setup_client
    api_key = @config.api_key_for(@config.provider)
    
    unless api_key
      UI.error("No API key found. Run with --init to configure.")
      exit 1
    end

    @client = APIClient.new(
      provider: @config.provider,
      api_key: api_key,
      model: @config.model,
      master_config: @master_config
    )
  end

  def handle_command(input)
    parts = input.split(/\s+/, 2)
    cmd = parts[0]
    arg = parts[1]

    case cmd
    when "/help"
      UI.puts HELP
    when "/model"
      handle_model_command(arg)
    when "/clear"
      @client&.clear_history
      UI.status("Conversation cleared")
    when "/tree"
      result = @filesystem.tree(path: arg || ".")
      UI.puts result[:tree] || result[:error]
    when "/read"
      if arg
        result = @filesystem.read(path: arg)
        if result[:error]
          UI.error(result[:error])
        else
          UI.puts "Path: #{result[:path]}"
          UI.puts "SHA256: #{result[:sha256]}"
          UI.puts "Size: #{result[:size]} bytes"
          UI.puts "\n#{result[:content]}"
        end
      else
        UI.error("Usage: /read PATH")
      end
    when "/master"
      show_master_status
    when "/config"
      show_config
    when "/reset"
      if UI.ask_yes_no("Reset configuration?", default: false)
        File.delete(Config::CONFIG_PATH) if File.exist?(Config::CONFIG_PATH)
        UI.status("Configuration reset. Run with --init to reconfigure.")
        exit 0
      end
    else
      UI.error("Unknown command. Type /help for available commands.")
    end
  end

  def handle_model_command(arg)
    if arg.nil? || arg.empty?
      UI.puts "Available models:"
      @client.models.each { |short, full| UI.puts "  • #{short} (#{full})" }
    else
      if @client.switch_model(arg)
        @config.model = @client.model
        @config.save
        UI.status("Switched to model: #{@client.model}")
      else
        UI.error("Unknown model: #{arg}")
      end
    end
  end

  def handle_message(text)
    print "Thinking..."
    
    response = ""
    @client.send_message(text) do |chunk|
      if response.empty?
        print "\r" + " " * 20 + "\r"
      end
      print chunk
      response << chunk
    end
    
    puts "" unless response.empty?
  rescue => e
    print "\r" + " " * 20 + "\r"
    UI.error(e.message)
  end

  def show_master_status
    UI.puts "\n╔═══════════════════════════════════════╗"
    UI.puts "║   Master.yml Status                    ║"
    UI.puts "╚═══════════════════════════════════════╝\n"
    
    if @master_config.loaded
      UI.puts "Version: #{@master_config.version}"
      UI.puts "Golden Rule: #{@master_config.golden_rule}"
      UI.puts "Banned Tools: #{@master_config.banned_tools.join(", ")}"
      UI.puts "Max Function Lines: #{@master_config.max_function_lines}"
      UI.puts "Max Nesting: #{@master_config.max_nesting}"
      UI.puts "Forbidden Patterns: #{@master_config.forbidden_patterns.join(", ")}"
    else
      UI.puts "Status: Not loaded"
      UI.puts "Searched paths:"
      MasterConfig::SEARCH_PATHS.each { |p| UI.puts "  • #{p}" }
    end
    
    UI.puts ""
  end

  def show_config
    UI.puts "\n╔═══════════════════════════════════════╗"
    UI.puts "║   Configuration                        ║"
    UI.puts "╚═══════════════════════════════════════╝\n"
    
    UI.puts "Provider: #{@config.provider}"
    UI.puts "Model: #{@config.model || "default"}"
    UI.puts "Config file: #{Config::CONFIG_PATH}"
    UI.puts "API keys configured: #{@config.api_keys.keys.join(", ")}"
    UI.puts ""
  end
end

# ============================================================================
# Main entry point
# ============================================================================

if __FILE__ == $0
  CLI.new.run(ARGV)
end
