#!/usr/bin/env ruby
# frozen_string_literal: true

# sonnet_cli. rb - OpenBSD AI CLI v2.1.0
# 
# master.yml v37.33.0 compliant implementation
# Repository: anon987654321/pub4
# 
# Principles Applied:
# - PRESERVE_THEN_IMPROVE_NEVER_BREAK (golden_rule)
# - Execute over describe (ethos)
# - Clarity over cleverness (philosophy)
# - OpenBSD dmesg terse output (output_format)
# - Pure Ruby/zsh (constraints. allowed)
# - Strunk & White prose (prose. strunk_white)
# - Convention over configuration (rails_doctrine)
# - Security first (principles.priority. critical)
#
# Usage:
#   export ANTHROPIC_API_KEY='sk-ant-api03-...'
#   ruby sonnet_cli.rb
#   ruby sonnet_cli.rb "analyze code"
#   ruby sonnet_cli.rb --setup

require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'shellwords'
require 'open3'
require 'timeout'

# Graceful optional dependencies
BEGIN {
  begin
    require 'pledge'
    PLEDGE_AVAILABLE = true
  rescue LoadError
    PLEDGE_AVAILABLE = false
    module Pledge
      def self. pledge(*); end
      def self.unveil(*); end
    end
  end

  begin
    require 'tty-prompt'
    require 'tty-spinner'
    require 'pastel'
    TTY_AVAILABLE = true
  rescue LoadError
    TTY_AVAILABLE = false
  end
  
  begin
    require 'anthropic'
    ANTHROPIC_GEM = true
  rescue LoadError
    ANTHROPIC_GEM = false
  end
}

# =============================================================================
# Logging - OpenBSD dmesg style (master.yml compliant)
# =============================================================================

module Log
  def self. dmesg(level, msg)
    $stderr.puts "sonnet[#{$$}]: #{level}:  #{msg}"
  end
  
  def self.info(msg)
    dmesg('info', msg)
  end
  
  def self.warn(msg)
    dmesg('warn', msg)
  end
  
  def self.error(msg)
    dmesg('error', msg)
  end
  
  def self.fatal(msg)
    dmesg('fatal', msg)
    exit 1
  end
  
  def self.debug(msg)
    dmesg('debug', msg) if ENV['DEBUG']
  end
end

# =============================================================================
# Tool Definition DSL (langchainrb pattern)
# =============================================================================

module ToolDefinition
  def self.extended(base)
    base.class_eval do
      @tool_functions = {}
      @tool_name = base.name. split('::').last.gsub(/Tool$/, '').downcase
    end
  end
  
  def tool_name
    @tool_name
  end
  
  def define_function(name, description:  "", &block)
    schema = FunctionSchema.new(name, description)
    schema.instance_eval(&block) if block_given?
    
    @tool_functions ||= {}
    @tool_functions[name] = schema
  end
  
  def tool_functions
    @tool_functions || {}
  end
  
  def to_anthropic_tools
    tool_functions. map do |name, schema|
      {
        name: name. to_s,
        description: schema.description,
        input_schema: {
          type: 'object',
          properties: schema.properties,
          required: schema.required
        }
      }
    end
  end
  
  class FunctionSchema
    attr_reader :name, :description, :properties, :required
    
    def initialize(name, description)
      @name = name
      @description = description
      @properties = {}
      @required = []
    end
    
    def property(name, type: , description: "", required: false)
      @properties[name] = {
        type: type,
        description: description
      }
      @required << name. to_s if required
    end
  end
end

# =============================================================================
# Built-in Tools
# =============================================================================

class ShellTool
  extend ToolDefinition
  
  define_function :execute_shell, description: "Execute shell command via zsh" do
    property :command, type: "string", description:  "Command to execute", required: true
  end
  
  def initialize(config, validator)
    @config = config
    @validator = validator
  end
  
  def execute_shell(command: )
    @validator.validate_command!(command)
    
    shell = @config.data. dig('shell', 'interpreter')
    stdout, stderr, status = Timeout.timeout(30) do
      Open3.capture3(shell, '-c', command)
    end
    
    {
      stdout: stdout,
      stderr: stderr,
      exit_code: status.exitstatus,
      command: command
    }
  rescue RuleValidator::ValidationError => e
    { error: e.message, suggestion: e.suggestion }
  rescue Timeout::Error
    { error: 'timeout (30s)' }
  rescue => e
    { error: "failed:  #{e.message}" }
  end
end

class FileTool
  extend ToolDefinition
  
  define_function : read_file, description: "Read file contents" do
    property : path, type: "string", description: "File path", required: true
  end
  
  define_function :write_file, description: "Write file" do
    property :path, type: "string", description: "File path", required: true
    property :content, type: "string", description: "Content", required: true
  end
  
  define_function :list_directory, description: "List directory" do
    property :path, type: "string", description: "Directory path", required: true
  end
  
  def initialize(config, validator)
    @config = config
    @validator = validator
  end
  
  def read_file(path: )
    @validator.validate_file!(path)
    return { error: "not found: #{path}" } unless File.exist?(path)
    return { error: "not readable: #{path}" } unless File. readable?(path)
    return { error: "too large (max 10MB)" } if File.size(path) > 10_485_760
    
    { content: File.read(path), size: File.size(path), path: path }
  rescue RuleValidator::ValidationError => e
    { error: e.message }
  rescue => e
    { error: "read failed: #{e.message}" }
  end
  
  def write_file(path:, content:)
    @validator.validate_file!(path)
    
    # Apply formatter_mental_model before write (master.yml mandate)
    formatted = format_content(path, content)
    
    FileUtils.mkdir_p(File. dirname(path))
    File.write(path, formatted)
    { success: true, path: path, size: formatted.bytesize }
  rescue RuleValidator::ValidationError => e
    { error: e.message }
  rescue => e
    { error: "write failed: #{e. message}" }
  end
  
  def list_directory(path:)
    @validator.validate_file!(path)
    return { error: "not found: #{path}" } unless File.exist?(path)
    return { error: "not a directory: #{path}" } unless File.directory?(path)
    
    # Use Ruby native Dir.entries (pure Ruby, not shell `ls`)
    entries = Dir.entries(path).reject { |e| e == '.' || e == '..' }
    {
      path: path,
      entries: entries. map { |e|
        full = File.join(path, e)
        { 
          name: e, 
          type:  File.directory?(full) ? 'directory' : 'file',
          size: File.size?(full)
        }
      }.sort_by { |e| [e[: type] == 'directory' ?  0 : 1, e[:name]] }
    }
  rescue RuleValidator::ValidationError => e
    { error: e.message }
  rescue => e
    { error: "list failed: #{e.message}" }
  end
  
  private
  
  # formatter_mental_model from master.yml execution. formatter_mental_model
  def format_content(path, content)
    ext = File.extname(path)
    
    case ext
    when '.rb'
      format_ruby(content)
    when '.yml', '.yaml'
      format_yaml(content)
    when '.sh'
      format_shell(content)
    when '.js'
      format_javascript(content)
    else
      content
    end
  end
  
  def format_ruby(content)
    # 2-space indent, single blank between functions
    content.gsub(/\n{3,}/, "\n\n")
           .split("\n")
           .map { |line| line.gsub(/^( {4})+/) { |spaces| '  ' * (spaces.length / 4) } }
           .join("\n")
  end
  
  def format_yaml(content)
    # 2-space indent strict, no blank lines within maps
    content.gsub(/\n{3,}/, "\n\n")
           .split("\n")
           .map { |line| line.sub(/^    /, '  ') }
           .join("\n")
  end
  
  def format_shell(content)
    # 2-space indent, quote all expansions
    content.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)/, '"$\1"')
           .gsub(/\n{3,}/, "\n\n")
  end
  
  def format_javascript(content)
    # Remove blank lines within functions, 2-space indent
    content. gsub(/\n{3,}/, "\n\n")
  end
end

# =============================================================================
# Defaults Module
# =============================================================================

module Defaults
  MODEL = 'claude-sonnet-4-5-20241022'
  MAX_TOKENS = 8192
  TEMPERATURE = 0.7
  
  def self.shell
    @shell ||= detect_shell
  end
  
  def self.detect_shell
    # master.yml execution.shell_zsh preferred order
    [
      '/usr/local/bin/zsh',
      '/bin/ksh',
      '/bin/sh',
      ENV['SHELL']
    ].compact.find { |s| File.executable?(s) } || '/bin/sh'
  end
  
  def self.session_store
    if ENV['XDG_DATA_HOME']
      File.join(ENV['XDG_DATA_HOME'], 'sonnet_sessions')
    else
      File.expand_path('~/.local/share/sonnet_sessions')
    end
  end
  
  def self.allowed_paths
    [
      ENV['HOME'],
      File.join(ENV['HOME'], 'pub'),
      File.join(ENV['HOME'], 'rails'),
      File.join(ENV['HOME'], 'creative'),
      Dir.pwd,
      '/tmp'
    ].compact. uniq. select { |p| File.exist?(p) rescue false }
  end
  
  SHELL_RULES = {
    'syntax_mode' => 'posix',
    'validate_syntax' => false,
    'forbidden_patterns' => []
  }. freeze
  
  COMMAND_RULES = {
    'preferred' => {},
    'forbidden' => [],
    'aliases' => {
      'install' => 'pkg_add',
      'update' => 'pkg_add -u'
    }
  }.freeze
  
  FILESYSTEM_RULES = {
    'forbidden_paths' => [
      '/etc/master.passwd',
      '/etc/spwd. db',
      '/etc/pwd.db'
    ]
  }.freeze
end

# =============================================================================
# Configuration
# =============================================================================

class Config
  class ConfigurationError < StandardError; end
  
  attr_reader :data
  
  def initialize(config_path:  nil)
    @config_path = config_path || find_config
    @data = load_with_healing
  end
  
  def api_key
    key = ENV['ANTHROPIC_API_KEY'] || @data['api_key']
    return key if key && ! key.empty?
    raise_missing_api_key
  end
  
  def rules
    @rules ||= {
      'shell' => Defaults:: SHELL_RULES. merge(@data. dig('rules', 'shell') || {}),
      'commands' => Defaults::COMMAND_RULES.merge(@data.dig('rules', 'commands') || {}),
      'filesystem' => Defaults::FILESYSTEM_RULES.merge(@data.dig('rules', 'filesystem') || {})
    }
  end
  
  def method_missing(method, *)
    @data.key?(method. to_s) ? @data[method.to_s] : super
  end
  
  def respond_to_missing?(method, *)
    @data.key?(method.to_s) || super
  end
  
  private
  
  def find_config
    [
      File.join(File.dirname(__FILE__), 'master.yml'),
      File.join(ENV['HOME'], 'pub', 'master.yml'),
      File.join(ENV['HOME'], '. config', 'sonnet', 'config.yml')
    ].find { |p| File.exist?(p) }
  end
  
  def load_with_healing
    base = {
      'model' => Defaults::MODEL,
      'max_tokens' => Defaults::MAX_TOKENS,
      'temperature' => Defaults::TEMPERATURE,
      'shell' => { 'interpreter' => Defaults. shell },
      'session_store' => Defaults. session_store,
      'allowed_paths' => Defaults.allowed_paths,
      'auto_approve' => false
    }
    
    return base unless @config_path
    
    user_config = YAML.load_file(@config_path)
    deep_merge(base, user_config)
  rescue Psych::SyntaxError => e
    Log.warn("invalid YAML: #{e.message}")
    base
  rescue => e
    Log.warn("config error: #{e.message}")
    base
  end
  
  def deep_merge(base, override)
    base.merge(override) do |_, base_val, override_val|
      if base_val.is_a?(Hash) && override_val.is_a?(Hash)
        deep_merge(base_val, override_val)
      else
        override_val
      end
    end
  end
  
  def raise_missing_api_key
    raise ConfigurationError, <<~ERROR
      
      missing API key
      
      set:  export ANTHROPIC_API_KEY='sk-ant-api03-.. .'
      or run: ruby sonnet_cli.rb --setup
      
      get key:  https://console.anthropic.com/settings/keys
      
    ERROR
  end
end

# =============================================================================
# Rule Validator
# =============================================================================

class RuleValidator
  class ValidationError < StandardError
    attr_reader :suggestion
    def initialize(msg, suggestion:  nil)
      super(msg)
      @suggestion = suggestion
    end
  end
  
  class ValidationWarning < StandardError; end
  
  def initialize(rules)
    @rules = rules
  end
  
  def validate_command!(cmd)
    check_patterns(cmd) if @rules. dig('shell', 'forbidden_patterns')&.any?
    check_forbidden(cmd) if @rules.dig('commands', 'forbidden')&.any?
    suggest_preferred(cmd) if @rules.dig('commands', 'preferred')&.any?
    nil
  end
  
  def validate_file!(path)
    return unless @rules.dig('filesystem', 'forbidden_paths')&.any?
    
    expanded = File.expand_path(path)
    @rules. dig('filesystem', 'forbidden_paths').each do |forbidden|
      if expanded == File.expand_path(forbidden) || 
         File.fnmatch(File.expand_path(forbidden), expanded, File::FNM_PATHNAME)
        raise ValidationError. new("access denied: #{path}")
      end
    end
  end
  
  private
  
  def check_patterns(cmd)
    @rules.dig('shell', 'forbidden_patterns').each do |pattern|
      if cmd.match?(Regexp.new(pattern, Regexp::IGNORECASE))
        raise ValidationError.new("forbidden pattern: #{pattern}")
      end
    end
  end
  
  def check_forbidden(cmd)
    name = cmd.strip. split. first
    if @rules.dig('commands', 'forbidden')&.include?(name)
      alt = @rules.dig('commands', 'aliases', name)
      raise ValidationError.new("forbidden: #{name}", suggestion: alt)
    end
  end
  
  def suggest_preferred(cmd)
    name = cmd.strip.split.first
    if (replacement = @rules.dig('commands', 'preferred', name))
      raise ValidationWarning.new("tip: #{replacement} instead of #{name}")
    end
  end
end

# =============================================================================
# Security (OpenBSD pledge/unveil)
# =============================================================================

module Security
  def self.apply!(paths)
    return unless PLEDGE_AVAILABLE
    
    unveil_map = {
      '/usr/bin' => 'rx',
      '/usr/local/bin' => 'rx',
      '/bin' => 'rx',
      '/etc/ssl' => 'r',
      '/tmp' => 'rwc'
    }
    
    paths.each { |p| unveil_map[p] = 'rwc' if File.exist?(p) }
    
    Pledge.unveil(unveil_map)
    Pledge.pledge("rpath wpath cpath inet dns proc exec")
    
    Log.info("security: pledge+unveil enabled")
  rescue => e
    Log.warn("security failed: #{e.message}")
  end
end

# =============================================================================
# Response Object (langchainrb pattern)
# =============================================================================

class AnthropicResponse
  attr_reader :raw_response
  
  def initialize(response)
    @raw_response = response. is_a?(Hash) ? response : response.to_h
  end
  
  def chat_completion
    text_blocks = content. select { |c| (c['type'] || c[: type]) == 'text' }
    text_blocks.map { |c| c['text'] || c[:text] }.join("\n")
  end
  
  def tool_calls
    content.select { |c| (c['type'] || c[:type]) == 'tool_use' }
  end
  
  def role
    @raw_response['role'] || @raw_response[: role] || 'assistant'
  end
  
  def stop_reason
    @raw_response['stop_reason'] || @raw_response[:stop_reason]
  end
  
  def prompt_tokens
    @raw_response. dig('usage', 'input_tokens') || 
    @raw_response.dig(: usage, : input_tokens) || 0
  end
  
  def completion_tokens
    @raw_response.dig('usage', 'output_tokens') || 
    @raw_response.dig(:usage, :output_tokens) || 0
  end
  
  def total_tokens
    prompt_tokens + completion_tokens
  end
  
  private
  
  def content
    @raw_response['content'] || @raw_response[: content] || []
  end
end

# =============================================================================
# Anthropic API Client
# =============================================================================

class AnthropicClient
  API_URL = 'https://api.anthropic.com/v1/messages'
  API_VERSION = '2023-06-01'
  
  class APIError < StandardError; end
  class RateLimitError < APIError; end
  class AuthError < APIError; end
  class NetworkError < APIError; end
  
  def initialize(config)
    @config = config
    @client = :: Anthropic::Client.new(access_token: config.api_key) if ANTHROPIC_GEM
  end
  
  def chat(messages: , tools: [])
    if ANTHROPIC_GEM
      chat_with_gem(messages, tools)
    else
      chat_with_http(messages, tools)
    end
  end
  
  def system_prompt
    <<~PROMPT
      You are a coding assistant on OpenBSD #{`uname -r`.chomp rescue 'unknown'}.
      
      Environment:
      - Shell: #{@config.data. dig('shell', 'interpreter')}
      - Working directory: #{Dir.pwd}
      
      Follow user configuration rules.  They are validated before execution.
    PROMPT
  end
  
  private
  
  def chat_with_gem(messages, tools)
    params = build_params(messages, tools)
    response = @client.messages(parameters: params)
    AnthropicResponse.new(response)
  rescue => e
    raise APIError, "API error: #{e.message}"
  end
  
  def chat_with_http(messages, tools)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    
    request = Net:: HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = @config.api_key
    request['anthropic-version'] = API_VERSION
    request.body = JSON.generate(build_params(messages, tools))
    
    response = http.request(request)
    AnthropicResponse.new(handle_response(response))
  end
  
  def build_params(messages, tools)
    params = {
      model: @config.data['model'],
      max_tokens:  @config.data['max_tokens'],
      temperature: @config. data['temperature'],
      system:  system_prompt,
      messages: messages
    }
    params[:tools] = tools unless tools.empty?
    params
  end
  
  def handle_response(response)
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPUnauthorized
      raise AuthError, "invalid API key"
    when Net:: HTTPTooManyRequests
      raise RateLimitError, "rate limited"
    else
      data = JSON.parse(response.body) rescue {}
      raise APIError, data.dig('error', 'message') || "HTTP #{response.code}"
    end
  rescue JSON::ParserError
    raise APIError, "invalid response"
  end
end

# =============================================================================
# Assistant with State Machine (langchainrb pattern)
# =============================================================================

class Assistant
  attr_reader :messages, :state, :tools
  attr_accessor :add_message_callback, :tool_execution_callback
  
  STATES = [: ready, :in_progress, :requires_action, :completed, :failed]. freeze
  MAX_RETRIES = 3
  
  def initialize(config, tools:  [])
    @config = config
    @client = AnthropicClient.new(config)
    @tools = tools
    @messages = []
    @state = : ready
    @add_message_callback = nil
    @tool_execution_callback = nil
    @total_prompt_tokens = 0
    @total_completion_tokens = 0
  end
  
  def add_message(role: , content:)
    message = { role: role, content: content }
    @messages << message
    @add_message_callback&.call(message)
    self
  end
  
  def add_message_and_run!(content:, auto_tool_execution: false)
    add_message(role: 'user', content: content)
    run(auto_tool_execution: auto_tool_execution)
  end
  
  def run(auto_tool_execution: false)
    @state = :in_progress
    retries = 0
    
    loop do
      case @state
      when :in_progress
        handle_llm_response
      when :requires_action
        if auto_tool_execution
          execute_tools
          @state = :in_progress
        else
          break
        end
      when :completed, :failed
        break
      end
    rescue AnthropicClient::RateLimitError
      if retries < MAX_RETRIES
        retries += 1
        wait = 2 ** retries
        Log.warn("rate limited, waiting #{wait}s")
        sleep wait
        retry
      else
        @state = :failed
        raise
      end
    rescue AnthropicClient::NetworkError
      if retries < MAX_RETRIES
        retries += 1
        Log.warn("network error, retrying")
        sleep 2
        retry
      else
        @state = :failed
        raise
      end
    end
    
    self
  end
  
  def last_response
    return nil if messages.empty?
    
    last = messages. last
    if last[: role] == 'assistant'
      content = last[:content]
      text = content.select { |c| c['type'] == 'text' }.map { |c| c['text'] }.join("\n")
      text. empty? ? nil : text
    end
  end
  
  def stats
    {
      messages: messages.size,
      prompt_tokens: @total_prompt_tokens,
      completion_tokens:  @total_completion_tokens,
      total_tokens: @total_prompt_tokens + @total_completion_tokens,
      state: @state
    }
  end
  
  private
  
  def handle_llm_response
    response = @client.chat(
      messages: @messages,
      tools: tool_definitions
    )
    
    @total_prompt_tokens += response.prompt_tokens
    @total_completion_tokens += response. completion_tokens
    
    add_message(role: 'assistant', content:  response.raw_response['content'])
    
    if response.tool_calls.any?
      @state = :requires_action
    else
      @state = :completed
    end
  rescue => e
    @state = : failed
    raise
  end
  
  def execute_tools
    tool_calls = messages.last[: content].select { |c| c['type'] == 'tool_use' }
    
    results = tool_calls.map do |call|
      execute_single_tool(call)
    end
    
    add_message(role: 'user', content: results)
  end
  
  def execute_single_tool(call)
    tool_name = call['name']
    method_name = tool_name.to_sym
    tool_input = call['input']. transform_keys(&:to_sym)
    tool_id = call['id']
    
    @tool_execution_callback&.call(tool_id, tool_name, method_name, tool_input)
    
    tool = tools.find { |t| t. class.tool_functions.key?(method_name) }
    raise "tool not found: #{tool_name}" unless tool
    
    output = tool.public_send(method_name, **tool_input)
    
    {
      type: 'tool_result',
      tool_use_id: tool_id,
      content: JSON.generate(output)
    }
  end
  
  def tool_definitions
    tools.flat_map { |t| t. class.to_anthropic_tools }
  end
end

# =============================================================================
# CLI
# =============================================================================

class CLI
  def initialize
    @config = Config.new
    @ui = create_ui
    @validator = RuleValidator.new(@config. rules)
    
    @tools = [
      ShellTool.new(@config, @validator),
      FileTool.new(@config, @validator)
    ]
    
    @assistant = Assistant.new(@config, tools: @tools)
    
    setup_callbacks
    Security.apply!(@config.data['allowed_paths'])
  rescue Config::ConfigurationError => e
    Log.error(e.message)
    exit 1
  end
  
  def run(args)
    case
    when args.include?('--setup') then run_setup
    when args.include?('--test') then run_tests
    when args.include?('--check') then check_config
    when args.include?('--help') || args.include?('-h') then show_help
    when args.include?('--version') || args.include?('-v') then puts "sonnet[#{$$}]:  info:  v2. 1.0"
    when args.empty? then interactive
    else oneshot(args. join(' '))
    end
  rescue Interrupt
    Log.info("interrupted")
    exit 0
  rescue => e
    Log.error("fatal:  #{e.message}")
    Log.debug(e.backtrace.first(5).join("\n"))
    exit 1
  end
  
  private
  
  def create_ui
    if TTY_AVAILABLE
      TTYInterface.new
    else
      DmesgInterface.new
    end
  end
  
  def interactive
    @ui.banner(@config)
    
    loop do
      input = @ui.prompt_input
      break if input.nil?  || input =~ /^(exit|quit|bye)$/i
      next if input.strip.empty?
      
      handle_input(input)
    end
    
    save_session
    @ui.farewell
  end
  
  def handle_input(input)
    if input.start_with?('/')
      handle_command(input)
    else
      send_to_assistant(input)
    end
  rescue => e
    Log.error(e.message)
  end
  
  def send_to_assistant(content)
    @ui.thinking do
      @assistant.add_message(role: 'user', content: content)
      @assistant.run(auto_tool_execution: false)
    end
    
    if @assistant.state == :requires_action
      approved = handle_tool_approvals
      if approved
        @ui.thinking("executing tools") do
          @assistant.run(auto_tool_execution: true)
        end
      else
        Log.warn("tool execution cancelled")
        @assistant.instance_variable_set(:@state, :completed)
      end
    end
    
    if response = @assistant.last_response
      @ui.assistant_response(response)
    end
  end
  
  def handle_tool_approvals
    tool_calls = @assistant.messages.last[:content].select { |c| c['type'] == 'tool_use' }
    
    tool_calls.all? do |call|
      @ui.confirm_tool_execution(call['name'], call['input'])
    end
  end
  
  def handle_command(cmd)
    case cmd
    when '/tools' then list_tools
    when '/stats' then show_stats
    when '/config' then show_config
    when '/clear' then clear_conversation
    when '/save' then save_session(manual: true)
    when '/help' then show_help
    else Log.warn("unknown command: #{cmd}")
    end
  end
  
  def list_tools
    @ui.section("available tools") do
      @tools.each do |tool|
        tool. class.tool_functions.each do |name, schema|
          @ui.list_item("#{name}:  #{schema.description}")
        end
      end
    end
  end
  
  def show_stats
    stats = @assistant.stats
    @ui.section("session statistics") do
      @ui.stat("messages", stats[: messages])
      @ui.stat("prompt_tokens", stats[:prompt_tokens])
      @ui.stat("completion_tokens", stats[: completion_tokens])
      @ui.stat("total_tokens", stats[:total_tokens])
      @ui.stat("state", stats[: state])
    end
  end
  
  def show_config
    @ui.section("configuration") do
      @ui.stat("model", @config.data['model'])
      @ui.stat("shell", @config.data. dig('shell', 'interpreter'))
      @ui.stat("max_tokens", @config.data['max_tokens'])
      @ui.stat("temperature", @config. data['temperature'])
      @ui.stat("session_store", @config.data['session_store'])
    end
  end
  
  def clear_conversation
    @assistant.messages.clear
    @assistant.instance_variable_set(:@state, :ready)
    Log.info("conversation cleared")
  end
  
  def save_session(manual: false)
    return if @assistant.messages.empty?
    
    session_id = Time.now.strftime('%Y%m%d_%H%M%S')
    dir = @config.data['session_store']
    FileUtils.mkdir_p(dir)
    
    file = File.join(dir, "#{session_id}.json")
    File.write(file, JSON.pretty_generate({
      timestamp: Time.now.iso8601,
      model: @config.data['model'],
      messages: @assistant.messages,
      stats: @assistant.stats
    }))
    
    Log.info("session saved:  #{session_id}") if manual
  rescue => e
    Log.warn("save failed: #{e.message}")
  end
  
  def oneshot(prompt)
    response = @assistant.add_message_and_run!(
      content: prompt,
      auto_tool_execution: false
    )
    
    if @assistant.state == :requires_action
      approved = handle_tool_approvals
      @assistant.run(auto_tool_execution: true) if approved
    end
    
    @ui.puts @assistant.last_response if @assistant.last_response
  end
  
  def setup_callbacks
    @assistant.add_message_callback = -> (msg) do
      Log.debug("message added: #{msg[: role]}")
    end
    
    @assistant. tool_execution_callback = -> (id, name, method, args) do
      Log.info("executing:  #{name}")
    end
  end
  
  def run_setup
    @ui.section("sonnet CLI setup") do
      api_key = @ui.masked_input("enter Anthropic API key:")
      
      config_data = { 'api_key' => api_key }
      config_path = File.join(File.dirname(__FILE__), 'master.yml')
      File.write(config_path, YAML.dump(config_data))
      
      Log.info("configuration saved to master.yml")
    end
  end
  
  def check_config
    @ui.section("configuration check") do
      begin
        key = @config.api_key
        @ui.stat("api_key", "#{key[0.. 10]}...")
        @ui.stat("model", @config.data['model'])
        @ui.stat("shell", @config.data. dig('shell', 'interpreter'))
        @ui.stat("rules", @config.rules.keys.join(', '))
      rescue => e
        Log.error(e.message)
        exit 1
      end
    end
  end
  
  def run_tests
    @ui.section("running self-tests") do
      tests = [
        -> { test_config },
        -> { test_validator },
        -> { test_tools }
      ]
      
      passed = 0
      tests.each_with_index do |test, i|
        begin
          test.call
          Log.info("test #{i+1} passed")
          passed += 1
        rescue => e
          Log.error("test #{i+1} failed: #{e. message}")
        end
      end
      
      @ui.puts "\n#{passed}/#{tests.size} tests passed"
      exit(passed == tests.size ? 0 : 1)
    end
  end
  
  def test_config
    raise "no API key" unless @config.api_key
    raise "no model" unless @config.data['model']
  end
  
  def test_validator
    @validator.validate_command! ('ls')
  end
  
  def test_tools
    raise "no tools" if @tools.empty?
  end
  
  def show_help
    @ui.section("sonnet CLI v2.1.0 - help") do
      @ui.puts <<~HELP
        
        usage: 
          sonnet_cli. rb                    interactive mode
          sonnet_cli.rb "prompt"          one-shot mode
          sonnet_cli.rb --setup           interactive setup
          sonnet_cli.rb --check           check configuration
          sonnet_cli.rb --test            run self-tests
        
        interactive commands:
          /tools      list available tools
          /stats      show session statistics
          /config     show configuration
          /clear      clear conversation
          /save       save session
          /help       show this help
          exit        exit CLI
        
        configuration:  
          create master.yml in same directory (optional)
          set ANTHROPIC_API_KEY environment variable
        
      HELP
    end
  end
end

# =============================================================================
# UI Interfaces
# =============================================================================

# OpenBSD dmesg style interface (master.yml compliant)
class DmesgInterface
  def banner(config)
    Log.info("sonnet v2.1.0 initialized")
    Log.info("model=#{config.data['model']}")
    Log.info("shell=#{config.data.dig('shell', 'interpreter')}")
    Log.info("security=#{PLEDGE_AVAILABLE ? 'pledge+unveil' : 'disabled'}")
  end
  
  def farewell
    Log.info("session ended")
  end
  
  def prompt_input
    print "\n> "
    $stdin.gets&.chomp
  end
  
  def masked_input(msg)
    print "#{msg} "
    $stdin.gets&. chomp
  end
  
  def confirm_tool_execution(name, input)
    details = input.map { |k, v| "#{k}=#{v}" }.join(' ')
    print "execute #{name} #{details}? [Y/n] "
    response = $stdin.gets&.chomp&.downcase
    response. empty? || response == 'y'
  end
  
  def thinking(msg = "processing")
    print "#{msg}..."
    result = yield
    puts " done"
    result
  end
  
  def assistant_response(text)
    puts "\n#{text}"
  end
  
  def section(title)
    puts "\n#{title}:"
    yield
  end
  
  def list_item(text)
    puts "  #{text}"
  end
  
  def stat(label, value)
    puts "  #{label}: #{value}"
  end
  
  def puts(text)
    Kernel.puts(text)
  end
end

# TTY-based interface with rich features
class TTYInterface
  def initialize
    @prompt = TTY::Prompt.new(
      prefix: '',
      active_color: :cyan,
      help_color: :bright_black,
      error_color: : red
    )
    @pastel = Pastel.new
    @spinner = nil
  end
  
  def banner(config)
    puts
    puts @pastel.cyan. bold("sonnet CLI v2.1.0")
    puts
    puts "  model:       #{config.data['model']}"
    puts "  shell:      #{config.data.dig('shell', 'interpreter')}"
    puts "  security:   #{PLEDGE_AVAILABLE ? @pastel.green('pledge+unveil') : @pastel.yellow('disabled')}"
    puts
    puts @pastel.dim("  type /help for commands\n")
  end
  
  def farewell
    puts "\nsession ended"
  end
  
  def prompt_input
    @prompt.ask('>', required: false) do |q|
      q.modify : strip
    end
  end
  
  def masked_input(msg)
    @prompt.mask(msg)
  end
  
  def confirm_tool_execution(name, input)
    details = input.map { |k, v| "#{k}:  #{v}" }.join(', ')
    @prompt.yes?("execute #{@pastel.cyan(name)} (#{details})?")
  end
  
  def thinking(msg = "processing", &block)
    @spinner = TTY::Spinner.new("[:spinner] #{msg}.. .", format: :dots)
    @spinner.auto_spin
    result = block.call
    @spinner.success
    result
  rescue => e
    @spinner&.error
    raise
  end
  
  def assistant_response(text)
    puts
    puts @pastel.bright_white(text)
  end
  
  def section(title, &block)
    puts
    puts @pastel.cyan.bold("#{title}")
    puts @pastel.dim("─" * 60)
    block.call
  end
  
  def list_item(text)
    puts "  • #{text}"
  end
  
  def stat(label, value)
    puts "  #{@pastel.dim(label + ':')} #{value}"
  end
  
  def puts(text)
    Kernel.puts(text)
  end
end

# =============================================================================
# Entry Point
# =============================================================================

CLI.new.run(ARGV) if __FILE__ == $PROGRAM_NAME