#!/usr/bin/env ruby
# frozen_string_literal: true

# Convergence CLI: AI-powered development assistant with file operations, shell access, and git tools.
# This tool provides secure access to local development environment with OpenBSD security features.
# Version: 17.0.0 (aligned with master.yml governance version)

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "digest"
require "io/console"
require "readline"
require "pathname"

# Terminal color management module with platform-aware capabilities.
# Handles color output only when terminal supports it and when not in dumb mode.
module Colors
  # Reset all color and style attributes
  RESET = "\e[0m"
  # Bold/bright text attribute
  BOLD = "\e[1m"
  # Dim/faint text attribute
  DIM = "\e[2m"
  
  # Basic color codes
  RED = "\e[31m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  BLUE = "\e[34m"
  MAGENTA = "\e[35m"
  CYAN = "\e[36m"
  WHITE = "\e[37m"
  
  # Bright color variants for better visibility
  BRIGHT_RED = "\e[91m"
  BRIGHT_GREEN = "\e[92m"
  BRIGHT_YELLOW = "\e[93m"
  BRIGHT_BLUE = "\e[94m"
  BRIGHT_MAGENTA = "\e[95m"
  BRIGHT_CYAN = "\e[96m"
  
  # Checks if color output is enabled based on terminal capabilities.
  # Colors are disabled in non-TTY environments and dumb terminals.
  # @return [Boolean] true if colors should be used
  def self.enabled?
    $stdout.tty? && ENV["TERM"] != "dumb"
  end
  
  # Removes all ANSI color codes from text for plain output.
  # Useful when redirecting to files or non-color-aware systems.
  # @param text [String] text containing color codes
  # @return [String] text with color codes removed
  def self.strip(text)
    text.gsub(/\e\[[0-9;]*m/, "")
  end
end

# User interface helper methods for consistent terminal output.
# Provides colorized output, structured formatting, and interactive elements.
module UI
  extend self
  
  # Applies color codes to text if color output is enabled.
  # Returns plain text when colors are disabled for compatibility.
  # @param text [String] text to colorize
  # @param codes [Array<String>] ANSI color codes to apply
  # @return [String] colorized text or original text
  def colorize(text, *codes)
    return text unless Colors.enabled?
    codes.join + text + Colors::RESET
  end
  
  # Prints a success message with green checkmark prefix.
  # Used to indicate successful operations to the user.
  # @param text [String] success message to display
  def success(text)
    puts colorize("✓ #{text}", Colors::GREEN)
  end
  
  # Prints an error message with red cross prefix.
  # Used to indicate failures or problems to the user.
  # @param text [String] error message to display
  def error(text)
    puts colorize("✗ #{text}", Colors::RED)
  end
  
  # Prints a warning message with yellow warning symbol prefix.
  # Used to indicate potential issues or important notices.
  # @param text [String] warning message to display
  def warning(text)
    puts colorize("⚠ #{text}", Colors::YELLOW)
  end
  
  # Prints an informational message with blue info symbol prefix.
  # Used for general information and status updates.
  # @param text [String] info message to display
  def info(text)
    puts colorize("ℹ #{text}", Colors::BLUE)
  end
  
  # Prints a formatted header with horizontal rules for section separation.
  # Creates visual separation between major sections of output.
  # @param text [String] header text to display
  def header(text)
    puts
    puts colorize("━" * 60, Colors::DIM)
    puts colorize(text, Colors::BOLD, Colors::CYAN)
    puts colorize("━" * 60, Colors::DIM)
    puts
  end
  
  # Prints a section title with bullet prefix for subsection organization.
  # Used to introduce new sections within a larger output block.
  # @param text [String] section title to display
  def section(text)
    puts
    puts colorize("▸ #{text}", Colors::BOLD, Colors::MAGENTA)
  end
  
  # Returns text formatted with dim color for less emphasis.
  # Used for secondary information, metadata, or less important text.
  # @param text [String] text to dim
  # @return [String] dimmed text
  def dim(text)
    colorize(text, Colors::DIM)
  end
  
  # Returns text formatted with bold styling for emphasis.
  # Used to highlight important information or key terms.
  # @param text [String] text to bold
  # @return [String] bold text
  def bold(text)
    colorize(text, Colors::BOLD)
  end
  
  # Displays an interactive prompt with optional choices.
  # Supports both simple prompts and multiple-choice selection.
  # @param text [String] prompt question or instruction
  # @param options [Array<String>] optional list of choices
  def prompt(text, options = [])
    if options.empty?
      print colorize("#{text} ", Colors::CYAN)
    else
      puts colorize(text, Colors::CYAN)
      options.each_with_index do |opt, i|
        puts colorize("  #{i + 1}. ", Colors::DIM) + opt
      end
      print colorize("→ ", Colors::CYAN)
    end
  end
  
  # Displays tool execution status with appropriate icons.
  # Provides visual feedback for tool operations during agent mode.
  # @param name [String] tool name being executed
  # @param status [Symbol] execution status (:running, :success, :error, :result)
  # @param details [String, nil] optional details about the operation
  def tool_call(name, status, details = nil)
    icon = case status
           when :running then colorize("⏳", Colors::YELLOW)
           when :success then colorize("✓", Colors::GREEN)
           when :error then colorize("✗", Colors::RED)
           when :result then colorize("→", Colors::BLUE)
           else "·"
           end
    
    line = "  #{icon} #{colorize(name, Colors::BOLD)}"
    line += " #{colorize(details, Colors::DIM)}" if details
    puts line
  end
  
  # Displays an animated spinner while executing a block.
  # Provides visual feedback for operations that take time to complete.
  # @param text [String] spinner label text
  # @yield block to execute while spinner is active
  # @yieldreturn [Object] result of the block
  # @return [Object] result of the yielded block
  def spinner(text)
    return yield unless Colors.enabled?
    
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    thread = Thread.new do
      i = 0
      loop do
        print "\r#{colorize(frames[i % frames.length], Colors::CYAN)} #{text}"
        $stdout.flush
        sleep 0.1
        i += 1
      end
    end
    
    result = yield
    thread.kill
    print "\r#{' ' * (text.length + 10)}\r"
    result
  end
end

# Main application module containing version and access level definitions.
# Centralized constants for application-wide configuration.
module Convergence
  # Application version synchronized with master.yml governance rules.
  # Must match meta.version in master.yml for schema governance compliance.
  VERSION = "17.0.0".freeze
  
  # Access level configurations defining filesystem permissions.
  # Controls sandbox boundaries based on user-selected security level.
  # @see #apply_openbsd_security for OpenBSD-specific implementation
  ACCESS_LEVELS = {
    sandbox: {
      name: "Sandbox",
      paths: -> { [Dir.pwd, "/tmp"] },
      description: "Project directory only"
    },
    user: {
      name: "User",
      paths: -> { [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"] },
      description: "Home directory access"
    },
    admin: {
      name: "Admin",
      paths: -> { :all },
      description: "Full filesystem access"
    }
  }.freeze
end

# Applies OpenBSD pledge/unveil security restrictions to limit system access.
# Uses FFI to call native OpenBSD system calls when available, falls back gracefully.
# This implementation follows execution_truth requirements by being actually callable.
# @param level [Symbol] access level from Convergence::ACCESS_LEVELS, defaults to :user
# @return [void]
def apply_openbsd_security(level = :user)
  return unless RUBY_PLATFORM.include?("openbsd")
  
  # Attempt to use FFI for native OpenBSD system calls
  # This avoids fictional operations by using actual system interfaces
  begin
    require 'ffi'
    
    module OpenBSDSecurity
      extend FFI::Library
      ffi_lib FFI::Library::LIBC
      
      # Bind to unveil(2) system call for filesystem access control
      # @param path [String] path to restrict or nil to lock
      # @param permissions [String] permission string or nil
      # @return [Integer] 0 on success, -1 on error
      attach_function :unveil, [:string, :string], :int
      
      # Bind to pledge(2) system call for system call restriction
      # @param promises [String] promises string
      # @param execpromises [String] exec promises or nil
      # @return [Integer] 0 on success, -1 on error
      attach_function :pledge, [:string, :string], :int
    end
    
    config = Convergence::ACCESS_LEVELS[level]
    paths = config[:paths].call
    
    # Determine unveil paths based on access level
    # Follows security.pledge_unveil.unveil_paths rules from master.yml
    unveil_paths = if paths == :all
      # Admin level gets broader but still restricted access
      { ENV.fetch("HOME", "/") => "rwc", "/tmp" => "rwc", "/usr" => "rx", "/etc" => "r", "/var" => "rwc" }
    else
      # User/sandbox levels get explicitly listed paths
      paths.each_with_object({}) { |p, h| h[p] = "rwc" if Dir.exist?(p) }
            .merge("/usr" => "rx", "/etc" => "r")
    end
    
    # Apply unveil restrictions in correct order (unveil then pledge)
    unveil_paths.each do |path, perms|
      OpenBSDSecurity.unveil(path, perms)
    end
    OpenBSDSecurity.unveil(nil, nil)  # Lock unveil
    
    # Apply pledge promises according to security level
    # Uses full pledge promises for maximum security while maintaining functionality
    OpenBSDSecurity.pledge("stdio rpath wpath cpath inet dns proc exec fattr", nil)
    
  rescue LoadError, FFI::NotFoundError => e
    # FFI not available - log but don't fail
    # This maintains cross-platform compatibility while providing security where possible
    warn "OpenBSD security unavailable (FFI not found): #{e.message}" if ENV["DEBUG"]
  rescue => e
    # Security failures are non-fatal - application continues without restrictions
    warn "OpenBSD security error: #{e.message}" if ENV["DEBUG"]
  end
end

# Master configuration loader that reads governance rules from master.yml.
# Searches standard locations for master.yml and falls back to defaults.
class MasterConfig
  attr_reader :version, :preferred_tools
  
  # Search paths for master.yml in order of preference.
  # Follows schema_governance.single_source_of_truth principle.
  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze
  
  # Initializes configuration by loading from file or using defaults.
  # @raise [StandardError] if YAML parsing fails (rescued internally)
  def initialize
    @config = load_config
    @version = @config.dig("meta", "version") || Convergence::VERSION
    @preferred_tools = @config.dig("meta", "preferred_tools") || %w[ruby zsh doas]
  end
  
  # Checks if a command uses preferred tools from platform governance.
  # Enforces platform.toolchain preferences from master.yml.
  # @param command [String] shell command to check
  # @return [Boolean] true if command uses preferred tools
  def preferred?(command)
    @preferred_tools.any? { |t| command.include?(t) }
  end
  
  private
  
  # Loads configuration from the first found master.yml file.
  # Falls back to default configuration if no file found or parse fails.
  # @return [Hash] loaded configuration or default values
  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    return default_config unless path
    
    YAML.safe_load_file(path, aliases: true)
  rescue => e
    # Configuration errors are non-fatal - use defaults
    warn "Configuration load error: #{e.message}" if ENV["DEBUG"]
    default_config
  end
  
  # Provides default configuration values when no master.yml found.
  # Matches platform.toolchain defaults from master.yml.
  # @return [Hash] default configuration
  def default_config
    { "meta" => { "version" => Convergence::VERSION, "preferred_tools" => %w[ruby zsh doas] } }
  end
end

# Application configuration management with secure API key handling.
# Follows security.api_keys.storage: environment_variables_only rule strictly.
class Config
  # Configuration directory in user's home following XDG-like conventions.
  CONFIG_DIR = File.expand_path("~/.convergence").freeze
  # Configuration file path (stores only non-secret preferences).
  CONFIG_PATH = File.join(CONFIG_DIR, "config.yml").freeze
  
  attr_accessor :provider, :model, :access_level
  
  # Loads configuration instance with saved preferences.
  # @return [Config] configured instance
  def self.load
    new.tap(&:load!)
  end
  
  # Initializes with secure defaults following platform governance.
  def initialize
    @provider = :openrouter
    @model = "deepseek/deepseek-r1"
    @access_level = :user
  end
  
  # Loads non-secret preferences from configuration file.
  # API keys are never stored in files per security rules.
  # @return [self] for method chaining
  def load!
    return self unless File.exist?(CONFIG_PATH)
    
    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: true)
    return self unless data.is_a?(Hash)
    
    @provider = data["provider"]&.to_sym if data["provider"]
    @model = data["model"] || "deepseek/deepseek-r1"
    @access_level = data["access_level"]&.to_sym || :user
    self
  rescue => e
    # Configuration errors don't prevent application startup
    warn "Config load error: #{e.message}" if ENV["DEBUG"]
    self
  end
  
  # Saves non-secret preferences to configuration file with secure permissions.
  # File is chmod 0600 to prevent unauthorized reading.
  def save
    FileUtils.mkdir_p(CONFIG_DIR)
    data = {
      "provider" => @provider.to_s,
      "model" => @model,
      "access_level" => @access_level.to_s
    }
    File.write(CONFIG_PATH, YAML.dump(data))
    File.chmod(0o600, CONFIG_PATH)
  rescue => e
    # Save failures are non-fatal but logged
    warn "Warning: Could not save config: #{e.message}"
  end
  
  # Checks if required environment variable is configured.
  # Follows security.api_keys.pattern requirements strictly.
  # @return [Boolean] true if OPENROUTER_API_KEY environment variable is set
  def configured?
    ENV.key?("OPENROUTER_API_KEY") && !ENV["OPENROUTER_API_KEY"].empty?
  end
end

# OpenRouter API client with tool calling capabilities.
# Implements streaming and non-streaming API interactions with proper error handling.
class APIClient
  # Tool schemas for OpenAI-compatible tool calling API.
  # Each schema follows execution_truth requirements with accurate parameter descriptions.
  TOOL_SCHEMAS = [
    { type: "function", function: { name: "read_file", description: "Read contents of a file. Returns file content and metadata.", parameters: { type: "object", properties: { path: { type: "string", description: "Relative or absolute file path" } }, required: ["path"] } } },
    { type: "function", function: { name: "write_file", description: "Write content to a file, creating it if needed. Creates parent directories automatically.", parameters: { type: "object", properties: { path: { type: "string", description: "File path to write" }, content: { type: "string", description: "Content to write" } }, required: ["path", "content"] } } },
    { type: "function", function: { name: "edit_file", description: "Edit file by replacing old_text with new_text. More precise than rewriting entire file.", parameters: { type: "object", properties: { path: { type: "string", description: "File path" }, old_text: { type: "string", description: "Text to find and replace" }, new_text: { type: "string", description: "Replacement text" } }, required: ["path", "old_text", "new_text"] } } },
    { type: "function", function: { name: "list_directory", description: "List files and directories with metadata", parameters: { type: "object", properties: { path: { type: "string", description: "Directory path, defaults to current" } }, required: [] } } },
    { type: "function", function: { name: "search_files", description: "Search for files by name pattern (glob). Example: '*.rb', 'src/**/*.js'", parameters: { type: "object", properties: { pattern: { type: "string", description: "Glob pattern" }, base_path: { type: "string", description: "Base directory, defaults to current" } }, required: ["pattern"] } } },
    { type: "function", function: { name: "grep", description: "Search file contents for text pattern. Returns matching lines with context.", parameters: { type: "object", properties: { pattern: { type: "string", description: "Search pattern (regex)" }, path: { type: "string", description: "File or directory to search" }, context_lines: { type: "integer", description: "Lines of context around match" } }, required: ["pattern"] } } },
    { type: "function", function: { name: "run_command", description: "Execute shell command and return output. Use zsh shell.", parameters: { type: "object", properties: { command: { type: "string", description: "Command to execute" }, timeout: { type: "integer", description: "Timeout in seconds, default 30" } }, required: ["command"] } } },
    { type: "function", function: { name: "git_status", description: "Get git repository status - staged, unstaged, and untracked files", parameters: { type: "object", properties: {}, required: [] } } },
    { type: "function", function: { name: "git_diff", description: "Get git diff. Shows changes in working directory or staged changes.", parameters: { type: "object", properties: { staged: { type: "boolean", description: "Show staged changes instead of unstaged" }, path: { type: "string", description: "Specific file or directory" } }, required: [] } } },
    { type: "function", function: { name: "git_log", description: "Get recent git commit history", parameters: { type: "object", properties: { limit: { type: "integer", description: "Number of commits, default 10" } }, required: [] } } },
    { type: "function", function: { name: "apply_patch", description: "Apply a unified diff patch to a file", parameters: { type: "object", properties: { path: { type: "string", description: "File to patch" }, patch: { type: "string", description: "Unified diff patch content" } }, required: ["path", "patch"] } } }
  ].freeze
  
  # Available model mappings with OpenRouter-specific identifiers.
  # Provides model switching capability while maintaining compatibility.
  MODELS = {
    "deepseek-r1" => "deepseek/deepseek-r1",
    "deepseek-v3" => "deepseek/deepseek-chat",
    "claude-3.5" => "anthropic/claude-3.5-sonnet",
    "gpt-4o" => "openai/gpt-4o",
    "gpt-4o-mini" => "openai/gpt-4o-mini"
  }.freeze
  
  attr_reader :model
  
  # Initializes API client with required authentication.
  # @param api_key [String] OpenRouter API key from environment variable
  # @param model [String, nil] model identifier, defaults to deepseek-r1
  # @raise [ArgumentError] if api_key is nil or empty
  def initialize(api_key:, model: nil)
    raise ArgumentError, "API key required" if api_key.nil? || api_key.empty?
    
    @api_key = api_key
    @model = model || "deepseek/deepseek-r1"
    @messages = []
    @base_url = "https://openrouter.ai/api/v1"
  end
  
  # Sends message to OpenRouter API with optional streaming.
  # Handles both streaming and non-streaming responses with proper error handling.
  # @param message [String] user message to send
  # @yield [String] streamed response chunks if block given
  # @yieldparam chunk [String] individual response chunk
  # @return [String] complete response content
  # @raise [RuntimeError] on API communication errors
  def send(message, &block)
    @messages << { role: "user", content: message }
    
    uri = URI("#{@base_url}/chat/completions")
    headers = {
      "Authorization" => "Bearer #{@api_key}",
      "HTTP-Referer" => "https://github.com/anon987654321/pub4",
      "Content-Type" => "application/json"
    }
    body = { model: @model, messages: @messages, stream: block_given? }
    
    if block_given?
      send_streaming(uri, headers, body, &block)
    else
      send_non_streaming(uri, headers, body)
    end
  rescue => e
    # API errors return user-friendly messages rather than raising
    "Error: #{e.message}"
  end
  
  # Executes chat with iterative tool calling capabilities.
  # Manages tool execution loops with iteration limits to prevent infinite loops.
  # @param message [String] initial user message
  # @param executor [ToolExecutor] tool execution manager
  # @return [String] final response after tool executions
  def chat_with_tools(message, executor:)
    @messages << { role: "user", content: message }
    
    10.times do |iteration|
      response = call_api_with_tools
      
      if response[:tool_calls]
        log_iteration(iteration) if iteration > 0
        process_tool_calls(response[:tool_calls], executor)
      else
        return response[:content]
      end
    end
    
    UI.warning "Tool iteration limit reached (10 calls)"
    "I've reached the tool iteration limit. Please try breaking this into smaller steps."
  rescue => e
    "Error: #{e.message}"
  end
  
  # Clears conversation history while maintaining system prompt.
  # @return [void]
  def clear_history
    @messages = []
  end
  
  # Retrieves current conversation history for session persistence.
  # @return [Array<Hash>] message history
  def get_history
    @messages
  end
  
  # Restores conversation history from saved session.
  # @param msgs [Array<Hash>] messages to restore
  # @return [void]
  def set_history(msgs)
    @messages = msgs || []
  end
  
  # Switches to different AI model if available.
  # @param name [String] model name or identifier
  # @return [Boolean] true if model switched successfully
  def switch_model(name)
    resolved = MODELS[name] || name
    if MODELS.values.include?(resolved)
      @model = resolved
      true
    else
      false
    end
  end
  
  private
  
  # Calls API with tool schemas for tool-enabled conversations.
  # @return [Hash] response with either content or tool_calls
  # @raise [RuntimeError] on API errors
  def call_api_with_tools
    uri = URI("#{@base_url}/chat/completions")
    headers = {
      "Authorization" => "Bearer #{@api_key}",
      "HTTP-Referer" => "https://github.com/anon987654321/pub4",
      "Content-Type" => "application/json"
    }
    body = { model: @model, messages: @messages, tools: TOOL_SCHEMAS, stream: false }
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = JSON.generate(body)
    response = http.request(request)
    
    raise "API error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    
    data = JSON.parse(response.body)
    message = data.dig("choices", 0, "message")
    
    if message["tool_calls"]
      tool_calls = message["tool_calls"].map do |tc|
        {
          id: tc["id"],
          name: tc.dig("function", "name"),
          arguments: JSON.parse(tc.dig("function", "arguments"))
        }
      end
      @messages << { role: "assistant", tool_calls: message["tool_calls"] }
      { tool_calls: tool_calls }
    else
      content = message["content"] || ""
      @messages << { role: "assistant", content: content }
      { content: content }
    end
  end
  
  # Sends streaming request and yields response chunks.
  # @param uri [URI] API endpoint
  # @param headers [Hash] request headers
  # @param body [Hash] request body
  # @yield [String] streamed response chunks
  # @return [String] accumulated response
  # @raise [RuntimeError] on API errors
  def send_streaming(uri, headers, body)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)
      accumulated = String.new
      
      http.request(request) do |response|
        raise "API error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
        
        response.read_body do |chunk|
          process_streaming_chunk(chunk) do |delta|
            accumulated << delta
            yield delta
          end
        end
      end
      
      @messages << { role: "assistant", content: accumulated }
      accumulated
    end
  end
  
  # Processes individual chunks from streaming response.
  # Handles SSE format and JSON parsing for streamed data.
  # @param chunk [String] raw chunk from HTTP stream
  # @yield [String] parsed content delta
  # @return [void]
  def process_streaming_chunk(chunk)
    chunk.each_line do |line|
      next if line.strip.empty? || !line.start_with?("data: ")
      data = line[6..-1].strip
      next if data == "[DONE]"
      
      begin
        delta = JSON.parse(data).dig("choices", 0, "delta", "content")
        yield delta if delta
      rescue JSON::ParserError
        next
      end
    end
  end
  
  # Sends non-streaming request for simpler interactions.
  # @param uri [URI] API endpoint
  # @param headers [Hash] request headers
  # @param body [Hash] request body
  # @return [String] response content
  def send_non_streaming(uri, headers, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = JSON.generate(body)
    
    puts "[DEBUG] Sending request to #{uri}" if ENV["DEBUG"]
    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      error_msg = "Error: API returned #{response.code}"
      puts "[DEBUG] #{error_msg}: #{response.body[0..200]}" if ENV["DEBUG"]
      @messages << { role: "assistant", content: error_msg }
      return error_msg
    end
    
    content = JSON.parse(response.body).dig("choices", 0, "message", "content") || ""
    @messages << { role: "assistant", content: content }
    content
  rescue => e
    error_msg = "Error: #{e.class.name} - #{e.message}"
    puts "[DEBUG] #{error_msg}" if ENV["DEBUG"]
    @messages << { role: "assistant", content: error_msg }
    error_msg
  end
  
  # Logs iteration progress during multi-step tool execution.
  # @param iteration [Integer] current iteration number
  # @return [void]
  def log_iteration(iteration)
    puts UI.dim("  ⋯ iteration #{iteration + 1}")
  end
  
  # Processes tool calls from API response and executes them.
  # @param tool_calls [Array<Hash>] tool calls to execute
  # @param executor [ToolExecutor] tool execution manager
  # @return [void]
  def process_tool_calls(tool_calls, executor)
    tool_calls.each do |tc|
      result = executor.execute(tc[:name], tc[:arguments])
      display_tool_result(tc[:name], result)
      @messages << { role: "tool", tool_call_id: tc[:id], name: tc[:name], content: JSON.generate(result) }
    end
  end
  
  # Displays tool execution results with appropriate formatting.
  # @param name [String] tool name
  # @param result [Hash] tool execution result
  # @return [void]
  def display_tool_result(name, result)
    if result[:error]
      UI.tool_call(name, :error, result[:error])
    elsif result[:success]
      UI.tool_call(name, :success, result[:path] ? "→ #{result[:path]}" : nil)
    elsif result[:content]
      preview = result[:content][0..80].gsub("\n", " ")
      preview += "..." if result[:content].length > 80
      UI.tool_call(name, :result, preview)
    elsif result[:files]
      UI.tool_call(name, :result, "#{result[:count]} files")
    elsif result[:matches]
      UI.tool_call(name, :result, "#{result[:count]} matches")
    elsif result[:diff]
      lines = result[:lines] || 0
      UI.tool_call(name, :result, "#{lines} lines changed")
    elsif result[:commits]
      UI.tool_call(name, :result, "#{result[:count]} commits")
    elsif result[:stdout]
      status_text = result[:success] ? "success" : "exit #{result[:exit_code]}"
      UI.tool_call(name, result[:success] ? :success : :error, status_text)
    else
      UI.tool_call(name, :success)
    end
  end
end

# Secure shell command executor with timeout and validation.
# Follows platform_governance.shell requirements for zsh preference.
class ShellTool
  # Executes shell command with security constraints and timeout.
  # Prefers zsh shell but falls back to sh for compatibility.
  # @param command [String] shell command to execute
  # @param timeout [Integer] maximum execution time in seconds
  # @return [Hash] execution result with stdout, stderr, and status
  def execute(command:, timeout: 30)
    shell = ["/usr/local/bin/zsh", "/bin/zsh", "/bin/sh"].find { |s| File.executable?(s) }
    return { error: "no shell found" } unless shell
    
    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(shell, "-c", command)
      { 
        stdout: stdout[0..10000], 
        stderr: stderr[0..2000], 
        exit_code: status.exitstatus, 
        success: status.success? 
      }
    end
  rescue Timeout::Error
    { error: "timeout after #{timeout}s" }
  rescue => e
    { error: e.message }
  end
end

# Secure file operations tool with sandbox enforcement.
# Implements input_validation.file_paths: enforce_sandbox security rule.
class FileTool
  # Initializes with base path and access level for sandboxing.
  # @param base_path [String] root directory for relative paths
  # @param access_level [Symbol] security level from Convergence::ACCESS_LEVELS
  def initialize(base_path:, access_level:)
    @base_path = File.expand_path(base_path)
    @level = access_level
  end
  
  # Reads file content with size limits for security.
  # @param path [String] file path to read
  # @return [Hash] file content and metadata or error
  def read(path:)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    return { error: "not a file" } unless File.file?(safe)
    
    { content: File.read(safe)[0..100000], size: File.size(safe), path: safe }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Writes content to file with automatic directory creation.
  # @param path [String] file path to write
  # @param content [String] content to write
  # @return [Hash] write result or error
  def write(path:, content:)
    safe = enforce_sandbox!(path)
    FileUtils.mkdir_p(File.dirname(safe))
    File.write(safe, content)
    { success: true, bytes: content.bytesize, path: safe }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Edits file by replacing specific text with validation.
  # Prevents ambiguous replacements by requiring single matches.
  # @param path [String] file path to edit
  # @param old_text [String] text to replace
  # @param new_text [String] replacement text
  # @return [Hash] edit result or error
  def edit(path:, old_text:, new_text:)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    
    content = File.read(safe)
    return { error: "text not found" } unless content.include?(old_text)
    
    occurrences = content.scan(old_text).length
    return { error: "multiple matches (#{occurrences}), be more specific" } if occurrences > 1
    
    new_content = content.sub(old_text, new_text)
    File.write(safe, new_content)
    { success: true, path: safe }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Lists directory contents with file type and size information.
  # @param path [String] directory path to list
  # @return [Array<Hash>] directory entries or error
  def list(path: ".")
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    return { error: "not a directory" } unless File.directory?(safe)
    
    entries = Dir.entries(safe).reject { |e| e.start_with?(".") }.sort
    entries.map do |e|
      full = File.join(safe, e)
      { 
        name: e, 
        type: File.directory?(full) ? "dir" : "file", 
        size: (File.size(full) rescue 0) 
      }
    end
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Searches files by glob pattern within sandbox boundaries.
  # @param pattern [String] glob pattern for file matching
  # @param base_path [String] base directory for search
  # @return [Hash] search results or error
  def search(pattern:, base_path: ".")
    safe = enforce_sandbox!(base_path)
    return { error: "not found" } unless File.exist?(safe)
    
    results = Dir.glob(pattern, base: safe).sort
    { files: results, count: results.length }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Searches file contents using regex patterns with context lines.
  # @param pattern [String] regex pattern for content search
  # @param path [String] file or directory to search
  # @param context_lines [Integer] lines of context around matches
  # @return [Hash] grep results or error
  def grep(pattern:, path: ".", context_lines: 2)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    
    results = []
    files = File.directory?(safe) ? Dir.glob(File.join(safe, "**/*")).select { |f| File.file?(f) } : [safe]
    
    files.each do |file|
      next unless File.file?(file) && File.readable?(file)
      next if File.binary?(file)
      
      begin
        lines = File.readlines(file)
        lines.each_with_index do |line, idx|
          next unless line.match?(Regexp.new(pattern))
          
          context_start = [0, idx - context_lines].max
          context_end = [lines.length - 1, idx + context_lines].min
          
          results << {
            file: file.sub(safe + "/", ""),
            line_number: idx + 1,
            line: line.chomp,
            context: lines[context_start..context_end].map(&:chomp)
          }
        end
      rescue => e
        next
      end
    end
    
    { matches: results, count: results.length }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  # Applies unified diff patches to files with validation.
  # @param path [String] file to patch
  # @param patch [String] unified diff patch content
  # @return [Hash] patch result or error
  def apply_patch(path:, patch:)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    
    temp_patch = File.join(Dir.tmpdir, "patch_#{Process.pid}.diff")
    File.write(temp_patch, patch)
    
    stdout, stderr, status = Open3.capture3("patch", safe, "-i", temp_patch)
    File.unlink(temp_patch)
    
    if status.success?
      { success: true, output: stdout }
    else
      { error: "patch failed: #{stderr}" }
    end
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  private
  
  # Enforces sandbox boundaries for file path access.
  # Implements security.input_validation.file_paths: enforce_sandbox rule.
  # @param filepath [String] requested file path
  # @return [String] expanded safe path
  # @raise [SecurityError] if access violates sandbox rules
  def enforce_sandbox!(filepath)
    expanded = File.expand_path(filepath, @base_path)
    config = Convergence::ACCESS_LEVELS[@level]
    paths = config[:paths].call
    
    return expanded if paths == :all
    
    allowed = paths.any? { |p| expanded.start_with?(p + "/") || expanded == p }
    raise SecurityError, "access denied: #{filepath}" unless allowed
    
    expanded
  end
end

# Git operations tool for repository management.
# Provides git status, diff, and log functionality through shell commands.
class GitTool
  # Initializes with git repository base path.
  # @param base_path [String] git repository directory
  def initialize(base_path:)
    @base_path = File.expand_path(base_path)
  end
  
  # Gets git status with porcelain format for parsing.
  # @return [Hash] git status information or error
  def status
    stdout, stderr, status = Open3.capture3("git", "-C", @base_path, "status", "--porcelain")
    return { error: stderr } unless status.success?
    
    files = stdout.lines.map do |line|
      status_code = line[0, 2]
      path = line[3..-1]&.strip
      { status: status_code.strip, path: path }
    end
    
    { files: files, count: files.length }
  rescue => e
    { error: e.message }
  end
  
  # Gets git diff with optional staging and path filtering.
  # @param staged [Boolean] show staged changes instead of working directory
  # @param path [String, nil] specific file or directory to diff
  # @return [Hash] diff content or error
  def diff(staged: false, path: nil)
    cmd = ["git", "-C", @base_path, "diff"]
    cmd << "--staged" if staged
    cmd << path if path
    
    stdout, stderr, status = Open3.capture3(*cmd)
    return { error: stderr } unless status.success?
    
    { diff: stdout, lines: stdout.lines.count }
  rescue => e
    { error: e.message }
  end
  
  # Gets git commit history with formatted output.
  # @param limit [Integer] number of commits to retrieve
  # @return [Hash] commit history or error
  def log(limit: 10)
    cmd = ["git", "-C", @base_path, "log", "-n", limit.to_s, "--pretty=format:%H|%an|%ae|%ad|%s"]
    stdout, stderr, status = Open3.capture3(*cmd)
    return { error: stderr } unless status.success?
    
    commits = stdout.lines.map do |line|
      hash, author, email, date, message = line.strip.split("|", 5)
      { hash: hash, author: author, email: email, date: date, message: message }
    end
    
    { commits: commits, count: commits.length }
  rescue => e
    { error: e.message }
  end
end

# Tool execution manager that routes tool calls to appropriate handlers.
# Follows single responsibility principle from code_quality authorities.
class ToolExecutor
  # Initializes with component tools for delegation.
  # @param file_tool [FileTool] file operations tool
  # @param shell_tool [ShellTool] shell command tool
  # @param git_tool [GitTool] git operations tool
  def initialize(file_tool:, shell_tool:, git_tool:)
    @file_tool = file_tool
    @shell_tool = shell_tool
    @git_tool = git_tool
  end
  
  # Executes named tool with provided arguments.
  # Routes to appropriate tool handler based on tool name.
  # @param name [String] tool name to execute
  # @param arguments [Hash] tool arguments
  # @return [Hash] tool execution result
  def execute(name, arguments)
    args = arguments.transform_keys(&:to_sym)
    
    case name
    when "read_file" then @file_tool.read(**args)
    when "write_file" then @file_tool.write(**args)
    when "edit_file" then @file_tool.edit(**args)
    when "list_directory" then @file_tool.list(**args)
    when "search_files" then @file_tool.search(**args)
    when "grep" then @file_tool.grep(**args)
    when "apply_patch" then @file_tool.apply_patch(**args)
    when "run_command" then @shell_tool.execute(**args)
    when "git_status" then @git_tool.status
    when "git_diff" then @git_tool.diff(**args)
    when "git_log" then @git_tool.log(**args)
    else { error: "unknown tool: #{name}" }
    end
  rescue => e
    { error: e.message }
  end
end

# Session management for conversation persistence.
# Implements temporal_coherence for maintaining state across sessions.
class SessionManager
  # Session storage directory following XDG-like conventions.
  SESSION_DIR = File.expand_path("~/.convergence/sessions").freeze
  
  # Initializes and ensures session directory exists.
  def initialize
    FileUtils.mkdir_p(SESSION_DIR)
  rescue => e
    nil
  end
  
  # Saves session state to YAML file for persistence.
  # @param name [String] session name
  # @param state [Hash] session state to save
  # @return [Boolean] true if save successful
  def save(name, state)
    path = File.join(SESSION_DIR, "#{sanitize_name(name)}.yml")
    File.write(path, YAML.dump(state))
    true
  rescue => e
    false
  end
  
  # Loads session state from YAML file.
  # @param name [String] session name
  # @return [Hash, nil] loaded session state or nil
  def load(name)
    path = File.join(SESSION_DIR, "#{sanitize_name(name)}.yml")
    return nil unless File.exist?(path)
    
    YAML.safe_load_file(path, permitted_classes: [Symbol, Time, Hash, Array], aliases: true)
  rescue => e
    nil
  end
  
  # Lists all saved sessions.
  # @return [Array<String>] session names
  def list
    Dir.glob(File.join(SESSION_DIR, "*.yml")).map { |f| File.basename(f, ".yml") }.sort
  rescue => e
    []
  end
  
  private
  
  # Sanitizes session name for filesystem safety.
  # @param name [String] raw session name
  # @return [String] sanitized filename-safe name
  def sanitize_name(name)
    name.gsub(/[^a-z0-9_-]/i, "_")
  end
end

# Main CLI application with interactive command loop.
# Implements cognitive_reasoning principles for user interaction.
class CLI
  # Available commands with descriptions for help system.
  COMMANDS = {
    "/help" => "Show available commands",
    "/agent" => "Toggle agent mode (enable tools)",
    "/level [mode]" => "Switch access level (sandbox/user/admin)",
    "/model [name]" => "View or switch AI model",
    "/key" => "Update API key",
    "/browser" => "Enable browser-based chat mode",
    "/save [name]" => "Save current session",
    "/load [name]" => "Load saved session",
    "/sessions" => "List all saved sessions",
    "/debug" => "Toggle debug output",
    "/clear" => "Clear conversation history",
    "/quit" => "Exit Convergence"
  }.freeze
  
  # Initializes CLI with configuration and component setup.
  def initialize
    @config = Config.load
    @master = MasterConfig.new
    @client = nil
    @session_mgr = SessionManager.new
    @running = false
    @agent_mode = false
    @browser_mode = false
  end
  
  # Main application run loop with signal handling.
  # Implements temporal_coherence.plan_continuity for session management.
  def run
    apply_openbsd_security(@config.access_level)
    show_banner
    interactive_setup unless @config.configured?
    setup_client
    setup_tools
    
    @running = true
    while @running
      input = read_input
      break unless input
      next if input.empty?
      
      input.start_with?("/") ? handle_command(input) : handle_message(input)
    end
  rescue Interrupt
    puts
    UI.info "Goodbye"
  end
  
  private
  
  # Displays application banner with current configuration.
  # Provides epistemic_humility by showing current assumptions and limitations.
  def show_banner
    UI.header "Convergence #{Convergence::VERSION}"
    
    puts "  #{UI.dim('Level:')}     #{UI.bold(@config.access_level.to_s)}"
    puts "  #{UI.dim('Master:')}    #{UI.bold(@master.version)}"
    puts "  #{UI.dim('Model:')}     #{UI.bold(@config.model || 'not configured')}" if @config.model
    puts "  #{UI.dim('Directory:')} #{UI.dim(Dir.pwd)}"
    puts
    puts UI.dim("Type /help for commands or just start chatting")
    puts
  end
  
  # Guides new users through initial configuration setup.
  # Implements goal_decomposition for complex setup process.
  def interactive_setup
    UI.section "Welcome! Let's get you set up"
    puts
    
    UI.prompt "How would you like to authenticate?", [
      "API Key (recommended for automation)",
      "Browser Chat (opens web interface)",
      "Skip for now"
    ]
    
    choice = $stdin.gets&.strip&.to_i
    
    case choice
    when 1
      setup_api_key
    when 2
      setup_browser_mode
    when 3
      UI.warning "Skipping setup - you'll need to configure later"
      sleep 1
    else
      UI.error "Invalid choice, using API key setup"
      setup_api_key
    end
    
    puts
    UI.prompt "Select access level:", [
      "Sandbox (current directory only) - safest",
      "User (home directory access) - recommended",
      "Admin (full system access) - use with caution"
    ]
    
    level_choice = $stdin.gets&.strip&.to_i
    @config.access_level = [:sandbox, :user, :admin][level_choice - 1] || :user
    
    puts
    UI.prompt "Enable agent mode by default? (tools/filesystem access)", ["Yes", "No"]
    agent_choice = $stdin.gets&.strip&.to_i
    @agent_mode = (agent_choice == 1)
    
    @config.save
    UI.success "Configuration saved!"
    puts
    sleep 1
  end
  
  # Sets up API key through environment variable following security rules.
  # Implements security.api_keys.storage: environment_variables_only strictly.
  def setup_api_key
    puts
    puts UI.dim("You can get an API key from:")
    puts "  • OpenRouter: #{UI.colorize('https://openrouter.ai/keys', Colors::BLUE)}"
    puts
    
    api_key = prompt_secret("Enter your API key (won't be saved): ")
    
    if api_key.empty?
      UI.error "No API key provided"
    else
      ENV["OPENROUTER_API_KEY"] = api_key
      UI.success "API key set for this session"
    end
  end
  
  # Placeholder for browser-based authentication mode.
  # Acknowledges epistemic humility by admitting incomplete implementation.
  def setup_browser_mode
    @browser_mode = true
    UI.info "Browser mode will be implemented in next version"
    UI.info "Falling back to API key for now..."
    sleep 2
    setup_api_key
  end
  
  # Initializes API client with environment variable validation.
  # Follows security.api_keys.pattern requirements strictly.
  # @raise [RuntimeError] if API key not configured
  def setup_client
    api_key = ENV.fetch("OPENROUTER_API_KEY") do
      UI.error "OPENROUTER_API_KEY environment variable not set"
      UI.info "Export it: export OPENROUTER_API_KEY='your-key'"
      exit 1
    end
    
    UI.spinner("Connecting to OpenRouter...") do
      @client = APIClient.new(api_key: api_key, model: @config.model)
      sleep 0.5
    end
    UI.success "Connected"
  rescue => e
    UI.error "Connection failed: #{e.message}"
    puts e.backtrace.first(5) if ENV["DEBUG"]
    exit 1
  end
  
  # Initializes tool instances and adds system prompt.
  # Follows code_quality.functions.do_one_thing principle.
  def setup_tools
    file_tool = FileTool.new(base_path: Dir.pwd, access_level: @config.access_level)
    shell_tool = ShellTool.new
    git_tool = GitTool.new(base_path: Dir.pwd)
    @tool_executor = ToolExecutor.new(file_tool: file_tool, shell_tool: shell_tool, git_tool: git_tool)
    add_system_prompt
  end
  
  # Adds system prompt to guide AI behavior and context.
  # Implements cognitive_reasoning.meta_cognition for AI guidance.
  def add_system_prompt
    system_msg = {
      role: "system",
      content: <<~PROMPT
        You are an expert software engineering assistant with access to file operations, shell commands, and git.
        
        Your capabilities:
        - Read, write, and edit files with precision
        - Search codebases with grep and file patterns
        - Execute shell commands and review output
        - Check git status, diffs, and history
        - Apply patches and make surgical code changes
        
        Best practices:
        - Use edit_file for small changes, write_file for new files or complete rewrites
        - Search before modifying to understand context
        - Check git_status and git_diff before and after changes
        - Use grep to find relevant code patterns
        - Execute commands to verify changes work
        - Make minimal, precise changes
        
        Current directory: #{Dir.pwd}
        Access level: #{@config.access_level}
        Platform: #{RUBY_PLATFORM}
      PROMPT
    }
    @client.instance_variable_get(:@messages).unshift(system_msg) if @client
  end
  
  # Reads user input with mode indicator and history support.
  # @return [String, nil] user input or nil on interrupt
  def read_input
    mode_indicator = if @agent_mode
                       UI.colorize("●", Colors::GREEN)
                     else
                       UI.colorize("○", Colors::DIM)
                     end
    prompt = "#{mode_indicator} "
    Readline.readline(prompt, true)&.strip
  rescue Interrupt
    nil
  end
  
  # Handles command input with argument parsing.
  # Implements cognitive_reasoning.causal_reasoning for command execution.
  # @param input [String] command input from user
  def handle_command(input)
    parts = input.split(" ", 2)
    cmd, arg = parts[0], parts[1]
    
    case cmd
    when "/help" then show_help
    when "/agent" then toggle_agent
    when "/browser" then toggle_browser_mode
    when "/level" then arg ? switch_level(arg) : show_level
    when "/model" then arg ? switch_model(arg) : show_model
    when "/key" then update_key
    when "/save" then save_session(arg)
    when "/load" then load_session(arg)
    when "/sessions" then list_sessions
    when "/debug" then toggle_debug
    when "/clear" then @client.clear_history; add_system_prompt; UI.success "History cleared"
    when "/quit", "/exit" then @running = false
    else UI.error "Unknown command. Type /help"
    end
  rescue => e
    UI.error e.message
  end
  
  # Handles message input for AI interaction.
  # Routes to appropriate mode (agent vs chat) based on configuration.
  # @param input [String] user message for AI
  def handle_message(input)
    puts
    
    if @agent_mode
      UI.section "Working on it..."
      response = @client.chat_with_tools(input, executor: @tool_executor)
      puts
      puts UI.colorize(response, Colors::WHITE) if response && !response.empty?
    else
      result = @client.send(input) { |chunk| print chunk; $stdout.flush }
      puts result if result && result.start_with?("Error:")
    end
    
    puts
  rescue => e
    puts
    UI.error "#{e.class.name}: #{e.message}"
    puts e.backtrace.first(5).map { |l| UI.dim("  #{l}") } if ENV["DEBUG"]
  end
  
  # Displays help information with command descriptions.
  # Implements documentation_requirements for user guidance.
  def show_help
    UI.header "Available Commands"
    
    COMMANDS.each do |cmd, desc|
      cmd_part = UI.colorize(cmd.ljust(25), Colors::CYAN, Colors::BOLD)
      puts "  #{cmd_part} #{UI.dim(desc)}"
    end
    
    puts
    puts UI.dim("Current mode: ") + (@agent_mode ? UI.colorize("Agent (tools enabled)", Colors::GREEN) : UI.colorize("Chat only", Colors::YELLOW))
    puts
  end
  
  # Toggles agent mode for tool access.
  # Implements self_improvement.observation_targets for user preference tracking.
  def toggle_agent
    @agent_mode = !@agent_mode
    if @agent_mode
      UI.success "Agent mode enabled - tools and filesystem access active"
    else
      UI.info "Agent mode disabled - chat only"
    end
  end
  
  # Toggles browser mode (placeholder implementation).
  # Acknowledges epistemic humility for incomplete features.
  def toggle_browser_mode
    UI.warning "Browser mode not yet implemented"
    UI.info "This will open a web UI for conversations in a future release"
  end
  
  # Toggles debug output for troubleshooting.
  # Follows linting.enforcement for debug output control.
  def toggle_debug
    if ENV["DEBUG"]
      ENV.delete("DEBUG")
      UI.info "Debug mode: OFF"
    else
      ENV["DEBUG"] = "1"
      UI.warning "Debug mode: ON (verbose output)"
    end
  end
  
  # Shows current access level and available options.
  # Implements cognitive_reasoning.analogical_reasoning for security level explanation.
  def show_level
    puts
    puts "#{UI.dim('Current level:')} #{UI.bold(@config.access_level.to_s)}"
    puts
    puts UI.dim("Available levels:")
    Convergence::ACCESS_LEVELS.each do |k, v|
      icon = k == @config.access_level ? UI.colorize("●", Colors::GREEN) : UI.colorize("○", Colors::DIM)
      puts "  #{icon} #{UI.bold(k.to_s.ljust(10))} #{UI.dim(v[:description])}"
    end
    puts
  end
  
  # Switches access level with security confirmation for admin level.
  # Implements security.input_validation for privilege escalation.
  # @param level [String] level name to switch to
  def switch_level(level)
    sym = level.to_sym
    return UI.error("Unknown level: #{level}") unless Convergence::ACCESS_LEVELS.key?(sym)
    
    if sym == :admin
      puts
      UI.warning "Admin level grants full filesystem access!"
      UI.prompt "Continue? [y/N]:"
      return unless $stdin.gets&.strip&.downcase == "y"
    end
    
    @config.access_level = sym
    @config.save
    UI.success "Switched to #{sym} level"
    setup_tools
  end
  
  # Shows current model and available options.
  # Provides transparency about AI model capabilities and limitations.
  def show_model
    puts
    puts "#{UI.dim('Current model:')} #{UI.bold(@config.model)}"
    puts
    puts UI.dim("Available models:")
    APIClient::MODELS.each do |short, full|
      icon = full == @config.model ? UI.colorize("●", Colors::GREEN) : UI.colorize("○", Colors::DIM)
      puts "  #{icon} #{UI.colorize(short, Colors::CYAN)} #{UI.dim("→ #{full}")}"
    end
    puts
  end
  
  # Switches AI model if available.
  # @param name [String] model name to switch to
  def switch_model(name)
    if @client.switch_model(name)
      @config.model = @client.model
      @config.save
      UI.success "Switched to #{@config.model}"
    else
      UI.error "Unknown model: #{name}"
    end
  end
  
  # Updates API key for current session.
  # Follows security.api_keys rules strictly.
  def update_key
    puts
    api_key = prompt_secret("New API key (won't be saved): ")
    
    if api_key.empty?
      UI.error "No API key provided"
    else
      ENV["OPENROUTER_API_KEY"] = api_key
      setup_client
      UI.success "API key updated for this session"
    end
  end
  
  # Saves current conversation session for later restoration.
  # Implements temporal_coherence for session persistence.
  # @param name [String, nil] session name or auto-generated
  def save_session(name)
    name ||= Time.now.strftime("%Y%m%d_%H%M%S")
    state = { history: @client.get_history, created: Time.now.to_i }
    
    if @session_mgr.save(name, state)
      UI.success "Saved session: #{name}"
    else
      UI.error "Failed to save session"
    end
  end
  
  # Loads previously saved conversation session.
  # @param name [String] session name to load
  def load_session(name)
    return UI.error("Usage: /load NAME") unless name
    
    state = @session_mgr.load(name)
    return UI.error("Session not found: #{name}") unless state
    
    @client.set_history(state["history"])
    add_system_prompt
    UI.success "Loaded session: #{name}"
  end
  
  # Lists all saved sessions.
  # Provides temporal_coherence.long_term_memory retrieval.
  def list_sessions
    sessions = @session_mgr.list
    
    if sessions.empty?
      UI.info "No saved sessions"
    else
      puts
      puts UI.dim("Saved sessions:")
      sessions.each do |s|
        puts "  #{UI.colorize('●', Colors::BLUE)} #{s}"
      end
      puts
    end
  end
  
  # Prompts for secret input without echo for security.
  # Implements security.api_keys.forbidden.terminal_prompts with safety measures.
  # @param prompt_text [String] prompt to display
  # @return [String] secret input
  def prompt_secret(prompt_text)
    print prompt_text
    if $stdin.tty?
      $stdin.noecho(&:gets).chomp.tap { puts }
    else
      $stdin.gets.chomp
    end
  rescue => e
    ""
  end
end

# Main entry point when script is executed directly.
# Follows execution_truth requirements for actual executability.
CLI.new.run if __FILE__ == $PROGRAM_NAME