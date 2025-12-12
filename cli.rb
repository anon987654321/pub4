#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'shellwords'
require 'open3'
require 'timeout'

BEGIN {
  begin
    require 'pledge'
    PLEDGE_AVAILABLE = true
  rescue LoadError
    PLEDGE_AVAILABLE = false
    module Pledge
      def self.pledge(*); end
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

module Log
  def self. dmesg(level, msg)
    $stderr.puts "sonnet[#{$$}]: #{level}: #{msg}"
  end

  def self.info(msg) = dmesg('info', msg)
  def self.warn(msg) = dmesg('warn', msg)
  def self.error(msg) = dmesg('error', msg)
  def self.fatal(msg) = (dmesg('fatal', msg); exit 1)
  def self.debug(msg) = dmesg('debug', msg) if ENV['DEBUG']
end

module ToolDefinition
  def self.extended(base)
    base.class_eval do
      @tool_functions = {}
      @tool_name = base.name. split('::').last.gsub(/Tool$/, '').downcase
    end
  end

  attr_reader :tool_name

  def define_function(name, description:  "", &block)
    schema = FunctionSchema.new(name, description)
    schema.instance_eval(&block) if block_given?
    @tool_functions ||= {}
    @tool_functions[name] = schema
  end

  def tool_functions = @tool_functions || {}

  def to_anthropic_tools
    tool_functions.map do |name, schema|
      build_tool_schema(name, schema)
    end
  end

  def build_tool_schema(name, schema)
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

  class FunctionSchema
    attr_reader :name, :description, :properties, :required

    def initialize(name, description)
      @name = name
      @description = description
      @properties = {}
      @required = []
    end

    def property(name, type: , description: "", required: false)
      @properties[name] = { type: type, description: description }
      @required << name. to_s if required
    end
  end
end

class ShellTool
  extend ToolDefinition

  define_function :execute_shell, description: "Execute shell command via zsh" do
    property :command, type: "string", description: "Command to execute", required: true
  end

  def initialize(config, validator)
    @config = config
    @validator = validator
  end

  def execute_shell(command: )
    @validator.validate_command!(command)
    shell = @config.data. dig('shell', 'interpreter')
    stdout, stderr, status = Timeout.timeout(30) { Open3.capture3(shell, '-c', command) }
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus, command: command }
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

  define_function :read_file, description: "Read file contents" do
    property :path, type: "string", description:  "File path", required: true
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
    return { error: "not found: #{path}" } unless File. exist?(path)
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
    formatted = format_content(path, content)
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
    entries = Dir.entries(path).reject { |e| e == '.' || e == '..' }
    {
      path: path,
      entries: entries. map { |e|
        full = File.join(path, e)
        { name: e, type: File.directory?(full) ? 'directory' : 'file', size: File.size?(full) }
      }. sort_by { |e| [e[:type] == 'directory' ? 0 : 1, e[:name]] }
    }
  rescue RuleValidator::ValidationError => e
    { error: e.message }
  rescue => e
    { error: "list failed: #{e.message}" }
  end

  private

  def format_content(path, content)
    ext = File.extname(path)
    case ext
    when '. rb' then content.gsub(/\n{3,}/, "\n\n").split("\n").map { |line| line.gsub(/^( {4})+/) { '  ' * ($&.length / 4) } }.join("\n")
    when '.yml', '.yaml' then content.gsub(/\n{3,}/, "\n\n").split("\n").map { |line| line.sub(/^    /, '  ') }.join("\n")
    when '.sh' then content.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)/, '"$\1"').gsub(/\n{3,}/, "\n\n")
    when '.js' then content.gsub(/\n{3,}/, "\n\n")
    else content
    end
  end
end

module Defaults
  MODEL = 'claude-sonnet-4-20250514'
  MAX_TOKENS = 8192
  TEMPERATURE = 0.7

  def self.shell
    @shell ||= ['/usr/local/bin/zsh', '/bin/ksh', '/bin/sh', ENV['SHELL']].compact.find { |s| File.executable?(s) } || '/bin/sh'
  end

  def self.session_store
    ENV['XDG_DATA_HOME'] ?  File.join(ENV['XDG_DATA_HOME'], 'convergence_sessions') : File.expand_path('~/.local/share/convergence_sessions')
  end

  def self. allowed_paths
    [ENV['HOME'], File.join(ENV['HOME'], 'pub'), File.join(ENV['HOME'], 'rails'), Dir.pwd, '/tmp']. compact. uniq. select { |p| File.exist?(p) rescue false }
  end

  SHELL_RULES = { 'syntax_mode' => 'posix', 'validate_syntax' => false, 'forbidden_patterns' => [] }.freeze
  COMMAND_RULES = { 'preferred' => {}, 'forbidden' => [], 'aliases' => { 'install' => 'pkg_add', 'update' => 'pkg_add -u' } }.freeze
  FILESYSTEM_RULES = { 'forbidden_paths' => ['/etc/master.passwd', '/etc/spwd.db', '/etc/pwd.db'] }.freeze
end

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
    raise ConfigurationError, <<~ERROR

      missing API key
      set:  export ANTHROPIC_API_KEY='sk-ant-api03-.. .'
      or run: ruby cli.rb --setup
      get key:  https://console.anthropic.com/settings/keys

    ERROR
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

  def respond_to_missing?(method, *) = @data.key?(method.to_s) || super

  private

  def find_config
    [File.join(File.dirname(__FILE__), 'master.yml'), File.join(ENV['HOME'], 'pub', 'master.yml'), File.join(ENV['HOME'], '. config', 'convergence', 'config. yml')].find { |p| File.exist?(p) }
  end

  def load_with_healing
    base = {
      'model' => Defaults::MODEL,
      'max_tokens' => Defaults::MAX_TOKENS,
      'temperature' => Defaults::TEMPERATURE,
      'shell' => { 'interpreter' => Defaults. shell },
      'session_store' => Defaults.session_store,
      'allowed_paths' => Defaults.allowed_paths,
      'auto_approve' => false
    }
    return base unless @config_path
    user_config = YAML.load_file(@config_path, permitted_classes: [Symbol])
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
      base_val.is_a?(Hash) && override_val.is_a?(Hash) ? deep_merge(base_val, override_val) : override_val
    end
  end
end

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
    @rules.dig('filesystem', 'forbidden_paths').each do |forbidden|
      raise ValidationError. new("access denied: #{path}") if expanded == File.expand_path(forbidden) || File.fnmatch(File.expand_path(forbidden), expanded, File::FNM_PATHNAME)
    end
  end

  private

  def check_patterns(cmd)
    @rules.dig('shell', 'forbidden_patterns').each do |pattern|
      raise ValidationError.new("forbidden pattern: #{pattern}") if cmd.match?(Regexp.new(pattern, Regexp::IGNORECASE))
    end
  end

  def check_forbidden(cmd)
    name = cmd.strip.split. first
    if @rules.dig('commands', 'forbidden')&.include?(name)
      alt = @rules.dig('commands', 'aliases', name)
      raise ValidationError.new("forbidden: #{name}", suggestion: alt)
    end
  end

  def suggest_preferred(cmd)
    name = cmd.strip.split.first
    raise ValidationWarning.new("tip: #{replacement} instead of #{name}") if (replacement = @rules.dig('commands', 'preferred', name))
  end
end

module Security
  def self.apply!(paths)
    return unless PLEDGE_AVAILABLE
    unveil_map = { '/usr/bin' => 'rx', '/usr/local/bin' => 'rx', '/bin' => 'rx', '/etc/ssl' => 'r', '/tmp' => 'rwc' }
    paths.each { |p| unveil_map[p] = 'rwc' if File.exist?(p) }
    Pledge.unveil(unveil_map)
    Pledge.pledge("rpath wpath cpath inet dns proc exec")
    Log.info("security: pledge+unveil enabled")
  rescue => e
    Log.warn("security failed: #{e.message}")
  end
end

class AnthropicResponse
  attr_reader :raw_response

  def initialize(response)
    @raw_response = response. is_a?(Hash) ? response : response.to_h
  end

  def chat_completion
    content. select { |c| (c['type'] || c[: type]) == 'text' }.map { |c| c['text'] || c[: text] }.join("\n")
  end

  def tool_calls = content.select { |c| (c['type'] || c[:type]) == 'tool_use' }
  def role = @raw_response['role'] || @raw_response[:role] || 'assistant'
  def stop_reason = @raw_response['stop_reason'] || @raw_response[: stop_reason]
  def prompt_tokens = @raw_response. dig('usage', 'input_tokens') || @raw_response. dig(: usage, : input_tokens) || 0
  def completion_tokens = @raw_response.dig('usage', 'output_tokens') || @raw_response.dig(:usage, :output_tokens) || 0
  def total_tokens = prompt_tokens + completion_tokens

  private

  def content = @raw_response['content'] || @raw_response[: content] || []
end

class AnthropicClient
  API_URL = 'https://api.anthropic.com/v1/messages'
  API_VERSION = '2023-06-01'

  class APIError < StandardError; end
  class RateLimitError < APIError; end
  class AuthError < APIError; end
  class NetworkError < APIError; end

  SYSTEM_PROMPT = "You are CONVERGENCE CLI - an AI coding assistant. Follow user configuration rules validated before execution."

  def initialize(config)
    @config = config
    @client = :: Anthropic::Client.new(access_token: config.api_key) if ANTHROPIC_GEM
  end

  def chat(messages: , tools: [])
    ANTHROPIC_GEM ? chat_with_gem(messages, tools) : chat_with_http(messages, tools)
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
    request = Net::HTTP::Post.new(uri. path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = @config.api_key
    request['anthropic-version'] = API_VERSION
    request.body = JSON.generate(build_params(messages, tools))
    response = http.request(request)
    AnthropicResponse.new(handle_response(response))
  end

  def build_params(messages, tools)
    params = { model: @config.data['model'], max_tokens: @config.data['max_tokens'], temperature: @config.data['temperature'], system: SYSTEM_PROMPT, messages: messages }
    params[: tools] = tools unless tools.empty?
    params
  end

  def handle_response(response)
    case response
    when Net::HTTPSuccess then JSON.parse(response.body)
    when Net::HTTPUnauthorized then raise AuthError, "invalid API key"
    when Net:: HTTPTooManyRequests then raise RateLimitError, "rate limited"
    else
      data = JSON.parse(response.body) rescue {}
      raise APIError, data.dig('error', 'message') || "HTTP #{response.code}"
    end
  rescue JSON::ParserError
    raise APIError, "invalid response"
  end
end

class Assistant
  attr_reader :messages, :state, :tools
  attr_accessor :add_message_callback, :tool_execution_callback

  STATES = [: completed, :failed, :in_progress, :ready, :requires_action]. freeze
  MAX_RETRIES = 3

  def initialize(config, tools: [])
    @config = config
    @client = AnthropicClient.new(config)
    @tools = tools
    @messages = []
    @state = :ready
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
      handle_state_transition(auto_tool_execution)
      break if @state == :completed || @state == :failed
    rescue AnthropicClient::RateLimitError
      handle_rate_limit(retries)
      retries += 1
    rescue AnthropicClient::NetworkError
      handle_network_error(retries)
      retries += 1
    end
    self
  end

  def handle_state_transition(auto_execute)
    case @state
    when :in_progress then handle_llm_response
    when :requires_action
      if auto_execute
        execute_tools
        @state = :in_progress
      end
    end
  end

  def handle_rate_limit(retries)
    raise if retries >= MAX_RETRIES
    wait = 2 ** (retries + 1)
    Log.warn("rate limited, waiting #{wait}s")
    sleep wait
  end

  def handle_network_error(retries)
    raise if retries >= MAX_RETRIES
    Log.warn("network error, retrying")
    sleep 2
  end

  def last_response
    return nil if messages.empty?
    last = messages. last
    return nil unless last[: role] == 'assistant'
    content = last[:content]
    text = content.select { |c| c['type'] == 'text' }.map { |c| c['text'] }. join("\n")
    text. empty? ? nil : text
  end

  def stats
    { messages: messages.size, prompt_tokens: @total_prompt_tokens, completion_tokens: @total_completion_tokens, total_tokens: @total_prompt_tokens + @total_completion_tokens, state: @state }
  end

  def complete!  = @state = :completed

  private

  def handle_llm_response
    response = @client.chat(messages: @messages, tools: tool_definitions)
    @total_prompt_tokens += response.prompt_tokens
    @total_completion_tokens += response. completion_tokens
    add_message(role: 'assistant', content:  response.raw_response['content'])
    @state = response.tool_calls.any? ? :requires_action : : completed
  rescue => e
    @state = : failed
    raise
  end

  def execute_tools
    tool_calls = messages.last[: content].select { |c| c['type'] == 'tool_use' }
    results = tool_calls.map { |call| execute_single_tool(call) }
    add_message(role: 'user', content: results)
  end

  def execute_single_tool(call)
    tool_name = call['name']
    method_name = tool_name.to_sym
    tool_input = call['input']. transform_keys(&:to_sym)
    tool_id = call['id']
    @tool_execution_callback&.call(tool_id, tool_name, method_name, tool_input)
    tool = tools.find { |t| t. class. tool_functions.key?(method_name) }
    raise "tool not found: #{tool_name}" unless tool
    output = tool.public_send(method_name, **tool_input)
    { type: 'tool_result', tool_use_id: tool_id, content: JSON.generate(output) }
  end

  def tool_definitions = tools.flat_map { |t| t.class.to_anthropic_tools }
end

class CLI
  def initialize
    @config = Config.new
    @ui = TTY_AVAILABLE ? TTYInterface. new : DmesgInterface.new
    @validator = RuleValidator.new(@config. rules)
    @tools = [ShellTool. new(@config, @validator), FileTool.new(@config, @validator)]
    @assistant = Assistant. new(@config, tools: @tools)
    setup_callbacks
    Security.apply! (@config.data['allowed_paths'])
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
    when args.include?('--version') || args.include?('-v') then puts "convergence[#{$$}]:  info:  v2. 2.0"
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

  def interactive
    @ui.banner(@config)
    loop do
      input = @ui.prompt_input
      break if input.nil? || input =~ /\A(exit|quit|bye)\z/i
      next if input.strip.empty?
      handle_input(input)
    end
    save_session
    @ui.farewell
  end

  def handle_input(input)
    input. start_with?('/') ? handle_command(input) : send_to_assistant(input)
  rescue => e
    Log.error(e.message)
  end

  def send_to_assistant(content)
    @ui.thinking { @assistant.add_message(role: 'user', content: content); @assistant.run(auto_tool_execution: false) }
    if @assistant.state == :requires_action
      approved = @assistant.messages.last[:content].select { |c| c['type'] == 'tool_use' }. all? { |call| @ui.confirm_tool_execution(call['name'], call['input']) }
      approved ? @ui.thinking("executing tools") { @assistant.run(auto_tool_execution: true) } : @assistant.complete!
    end
    @ui.assistant_response(@assistant.last_response) if @assistant.last_response
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
      @tools.each { |tool| tool.class.tool_functions.each { |name, schema| @ui.list_item("#{name}:  #{schema. description}") } }
    end
  end

  def show_stats
    stats = @assistant.stats
    @ui.section("session statistics") { stats.each { |k, v| @ui.stat(k. to_s, v) } }
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
    File.write(file, JSON.pretty_generate({ timestamp: Time.now. iso8601, model: @config.data['model'], messages: @assistant.messages, stats: @assistant.stats }))
    Log.info("session saved: #{session_id}") if manual
  rescue => e
    Log.warn("save failed: #{e.message}")
  end

  def oneshot(prompt)
    @assistant.add_message_and_run!(content: prompt, auto_tool_execution: false)
    if @assistant.state == :requires_action
      approved = @assistant. messages.last[:content].select { |c| c['type'] == 'tool_use' }.all? { |call| @ui. confirm_tool_execution(call['name'], call['input']) }
      @assistant.run(auto_tool_execution: true) if approved
    end
    @ui.puts @assistant.last_response if @assistant.last_response
  end

  def setup_callbacks
    @assistant.add_message_callback = ->(msg) { Log.debug("message added: #{msg[: role]}") }
    @assistant.tool_execution_callback = ->(id, name, method, args) { Log.info("executing:  #{name}") }
  end

  def run_setup
    @ui.section("CONVERGENCE CLI setup") do
      api_key = @ui.masked_input("enter Anthropic API key:")
      config_path = File.join(File.dirname(__FILE__), 'master.yml')
      File.write(config_path, YAML.dump({ 'api_key' => api_key }))
      Log.info("configuration saved to master.yml")
    end
  end

  def check_config
    @ui.section("configuration check") do
      key = @config.api_key
      @ui.stat("api_key", "#{key[0..10]}...")
      @ui.stat("model", @config.data['model'])
      @ui.stat("shell", @config.data. dig('shell', 'interpreter'))
      @ui.stat("rules", @config.rules.keys.join(', '))
    end
  rescue => e
    Log.error(e.message)
    exit 1
  end

  def run_tests
    @ui.section("running self-tests") do
      tests = [->{ raise "no API key" unless @config.api_key; raise "no model" unless @config.data['model'] }, ->{ @validator.validate_command! ('ls') }, ->{ raise "no tools" if @tools.empty? }]
      passed = tests.count { |test| (test.call; Log.info("test passed"); true) rescue (Log.error("test failed:  #{$!. message}"); false) }
      @ui.puts "\n#{passed}/#{tests.size} tests passed"
      exit(passed == tests.size ? 0 : 1)
    end
  end

  HELP_TEXT = <<~HELP

    usage:
      cli. rb                  interactive mode
      cli.rb "prompt"         one-shot mode
      cli.rb --setup          interactive setup
      cli.rb --check          check configuration
      cli.rb --test           run self-tests

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

  def show_help
    @ui.section("CONVERGENCE CLI v2.2.0 - help") { @ui.puts HELP_TEXT }
  end
end

class BaseInterface
  def banner(config)
    Log.info("CONVERGENCE v2.2.0 initialized")
    Log.info("model=#{config.data['model']}")
    Log.info("shell=#{config.data.dig('shell', 'interpreter')}")
    Log.info("security=#{PLEDGE_AVAILABLE ? 'pledge+unveil' : 'disabled'}")
  end

  def farewell = Log.info("session ended")
  def prompt_input = (print "\n> "; $stdin.gets&.chomp)
  def masked_input(msg) = (print "#{msg} "; $stdin.gets&.chomp)

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

  def assistant_response(text) = puts "\n#{text}"
  def section(title) = (puts "\n#{title}: "; yield)
  def list_item(text) = puts "  #{text}"
  def stat(label, value) = puts "  #{label}: #{value}"
  def puts(text) = Kernel.puts(text)
end

class DmesgInterface < BaseInterface; end

class TTYInterface < BaseInterface
  def initialize
    @prompt = TTY::Prompt.new(prefix: '', active_color: : cyan, help_color: :bright_black, error_color: :red)
    @pastel = Pastel.new
    @spinner = nil
  end

  def banner(config)
    puts
    puts @pastel.cyan. bold("CONVERGENCE CLI v2.2.0")
    puts
    puts "  model:       #{config.data['model']}"
    puts "  shell:      #{config.data.dig('shell', 'interpreter')}"
    puts "  security:   #{PLEDGE_AVAILABLE ? @pastel.green('pledge+unveil') : @pastel.yellow('disabled')}"
    puts
    puts @pastel.dim("  type /help for commands\n")
  end

  def farewell = puts "\nsession ended"
  def prompt_input = @prompt.ask('>', required: false) { |q| q.modify : strip }
  def masked_input(msg) = @prompt.mask(msg)

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

  def assistant_response(text) = (puts; puts @pastel.bright_white(text))

  def section(title, &block)
    puts
    puts @pastel.cyan.bold("#{title}")
    puts @pastel.dim("─" * 60)
    block.call
  end

  def list_item(text) = puts "  • #{text}"
  def stat(label, value) = puts "  #{@pastel.dim(label + ':')} #{value}"
end

CLI.new.run(ARGV) if __FILE__ == $PROGRAM_NAME