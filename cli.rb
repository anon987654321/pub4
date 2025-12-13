#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "json"
require "net/http"
require "uri"
require "fileutils"
require "shellwords"
require "open3"
require "timeout"

BEGIN {
  if RUBY_PLATFORM =~ /openbsd/
    require "pledge" or raise "pledge gem required: gem install ruby-pledge"
    Pledge.pledge("stdio rpath wpath cpath inet dns proc exec", nil)
    Pledge.unveil(ENV["HOME"], "rwc")
    Pledge.unveil("/tmp", "rwc")
    Pledge.unveil("/usr/local", "r")
    Pledge.unveil("/etc/ssl", "r")
    Pledge.unveil(nil, nil)
    PLEDGE_AVAILABLE = true
  else
    PLEDGE_AVAILABLE = false
  end

  begin
    require "tty-prompt"
    require "tty-spinner"
    require "pastel"
    TTY_AVAILABLE = true
  rescue LoadError
    TTY_AVAILABLE = false
  end

  begin
    require "anthropic"
    ANTHROPIC_GEM = true
  rescue LoadError
    ANTHROPIC_GEM = false
  end
}

module Log
  def self.structured(level:, msg:, **context)
    entry = {
      timestamp: Time.now.iso8601,
      pid: $$,
      level: level,
      message: msg
    }.merge(context)
    $stderr.puts JSON.generate(entry)
  end

  def self.info(msg, **ctx) = structured(level: "INFO", msg: msg, **ctx)
  def self.warn(msg, **ctx) = structured(level: "WARN", msg: msg, **ctx)
  def self.error(msg, **ctx) = structured(level: "ERROR", msg: msg, **ctx)
  def self.fatal(msg, **ctx) = (structured(level: "FATAL", msg: msg, **ctx); exit 1)
  def self.debug(msg, **ctx) = structured(level: "DEBUG", msg: msg, **ctx) if ENV["DEBUG"]
end

class CircuitBreaker
  class OpenError < StandardError; end

  def initialize(threshold: 5, timeout: 60)
    @failure_count = 0
    @threshold = threshold
    @timeout = timeout
    @last_failure = nil
    @state = :closed
  end

  def call
    raise OpenError, "circuit open (retry in #{retry_in}s)" if open?
    yield.tap { success }
  rescue => e
    failure
    raise
  end

  private

  def open? = @state == :open && Time.now - @last_failure < @timeout
  def retry_in = (@timeout - (Time.now - @last_failure)).ceil

  def success
    @failure_count = 0
    @state = :closed
  end

  def failure
    @failure_count += 1
    @last_failure = Time.now
    @state = :open if @failure_count >= @threshold
  end
end

class RetryWithBackoff
  def self.call(max_attempts: 3, base_delay: 1)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue => e
      if attempts < max_attempts
        delay = base_delay * (2 ** (attempts - 1))
        Log.warn("retry #{attempts}/#{max_attempts} in #{delay}s: #{e.message}")
        sleep delay
        retry
      else
        raise
      end
    end
  end
end

class Metrics
  def initialize
    @counters = Hash.new(0)
    @gauges = {}
    @timers = {}
  end

  def increment(name, value = 1)
    @counters[name] += value
  end

  def gauge(name, value)
    @gauges[name] = value
  end

  def time(name)
    start = Time.now
    yield
  ensure
    @timers[name] ||= []
    @timers[name] << (Time.now - start)
  end

  def cost_usd
    input = @gauges[:input_tokens] || 0
    output = @gauges[:output_tokens] || 0
    (input * 0.003 + output * 0.015) / 1000.0
  end

  def cost_nok
    cost_usd * 11.5
  end

  def report
    {
      counters: @counters,
      gauges: @gauges,
      timers: @timers.transform_values { |times|
        { count: times.size, mean: times.sum / times.size, max: times.max, min: times.min }
      },
      cost: { usd: cost_usd, nok: cost_nok }
    }
  end

  def to_json = JSON.generate(report)
end

module ToolDefinition
  def self.extended(base)
    base.class_eval do
      @tool_functions = {}
      @tool_name = extract_tool_name(base.name)
    end
  end

  def self.extract_tool_name(class_name)
    class_name.split("::").last.gsub(/Tool$/, "").downcase
  end

  attr_reader :tool_name

  def define_function(name, description: "", &block)
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
      name: name.to_s,
      description: schema.description,
      input_schema: {
        type: "object",
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

    def property(name, type:, description: "", required: false)
      @properties[name] = { type: type, description: description }
      @required << name.to_s if required
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

  def execute_shell(command:)
    @validator.validate_command!(command)
    shell = validate_shell_interpreter!
    result = execute_with_retry(shell, command)
    { stdout: result[:stdout], stderr: result[:stderr], exit_code: result[:status], command: command }
  rescue RuleValidator::ValidationError => e
    { error: e.message, suggestion: e.suggestion }
  rescue CircuitBreaker::OpenError => e
    { error: e.message }
  rescue => e
    { error: "failed: #{e.message}" }
  end

  private

  def validate_shell_interpreter!
    shell = @config.data.dig("shell", "interpreter")
    return shell if shell && File.executable?(shell)

    zsh = ["/usr/local/bin/zsh", "/bin/zsh"].find { |s| File.executable?(s) }
    return zsh if zsh

    Log.warn("zsh not found, falling back to #{shell}")
    shell
  end

  def execute_with_retry(shell, command)
    RetryWithBackoff.call(max_attempts: 2, base_delay: 0.5) do
      stdout, stderr, status = Timeout.timeout(30) { Open3.capture3(shell, "-c", command) }
      { stdout: stdout, stderr: stderr, status: status.exitstatus }
    end
  rescue Timeout::Error
    { stdout: "", stderr: "timeout (30s)", status: 124 }
  end
end

class FileTool
  extend ToolDefinition

  define_function :read_file, description: "Read file contents" do
    property :path, type: "string", description: "File path", required: true
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

  def read_file(path:)
    @validator.validate_file!(path)
    return { error: "not found: #{path}" } unless File.exist?(path)
    return { error: "not readable: #{path}" } unless File.readable?(path)
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

    if File.exist?(path)
      require "tempfile"
      Tempfile.create do |tmp|
        tmp.write(formatted)
        tmp.flush
        diff = `diff -u #{Shellwords.escape(path)} #{tmp.path} 2>/dev/null`
        unless diff.empty?
          Log.info("file_diff", path: path, lines: diff.lines.count)
          puts "
Diff preview:
#{diff}"
        end
      end
    end

    File.write(path, formatted)
    { success: true, path: path, size: formatted.bytesize }
  rescue RuleValidator::ValidationError => e
    { error: e.message }
  rescue => e
    { error: "write failed: #{e.message}" }
  end

  def list_directory(path:)
    @validator.validate_file!(path)
    return { error: "not found: #{path}" } unless File.exist?(path)
    return { error: "not a directory: #{path}" } unless File.directory?(path)
    entries = Dir.entries(path).reject { |e| e == "." || e == ".." }
    {
      path: path,
      entries: entries.map { |e|
        full = File.join(path, e)
        { name: e, type: File.directory?(full) ? "directory" : "file", size: File.size?(full) }
      }.sort_by { |e| [e[:type] == "directory" ? 0 : 1, e[:name]] }
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
    when ".rb" then content.gsub(/
{3,}/, "

").split("
").map { |line| line.gsub(/^( {4})+/) { "  " * ($&.length / 4) } }.join("
")
    when ".yml", ".yaml" then content.gsub(/
{3,}/, "

").split("
").map { |line| line.sub(/^    /, "  ") }.join("
")
    when ".sh" then content.gsub(/$([A-Za-z_][A-Za-z0-9_]*)/, '"$"').gsub(/
{3,}/, "

")
    when ".js" then content.gsub(/
{3,}/, "

")
    else content
    end
  end
end

module Defaults
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 8192
  TEMPERATURE = 0.7

  def self.shell
    @shell ||= ["/usr/local/bin/zsh", "/bin/ksh", "/bin/sh", ENV["SHELL"]].compact.find { |s| File.executable?(s) } || "/bin/sh"
  end

  def self.session_store
    ENV["XDG_DATA_HOME"] ? File.join(ENV["XDG_DATA_HOME"], "convergence_sessions") : File.expand_path("~/.local/share/convergence_sessions")
  end

  def self.allowed_paths
    [ENV["HOME"], File.join(ENV["HOME"], "pub"), File.join(ENV["HOME"], "rails"), Dir.pwd, "/tmp"].compact.uniq.select { |p| File.exist?(p) rescue false }
  end
end

class Config
  class ConfigurationError < StandardError; end

  attr_reader :data

  def initialize(config_path: nil)
    @config_path = config_path || resolve_canonical_path
    @data = load_with_healing
    validate!
  end

  def api_key
    key = ENV["ANTHROPIC_API_KEY"] || @data["api_key"]
    return key if key && !key.empty?
    raise ConfigurationError, <<~ERROR

      missing API key
      set: export ANTHROPIC_API_KEY="sk-ant-api03-..."
      or run: ruby cli.rb --setup
      get key: https://console.anthropic.com/settings/keys

    ERROR
  end

  def validate!
    errors = []
    errors << "missing api_key" unless api_key rescue true
    errors << "invalid model" unless data["model"]&.start_with?("claude-")
    errors << "shell not executable: #{data.dig("shell", "interpreter")}" unless File.executable?(data.dig("shell", "interpreter") || "")
    errors << "invalid max_tokens: #{data["max_tokens"]}" unless data["max_tokens"].is_a?(Integer) && data["max_tokens"].between?(1, 200_000)
    errors << "invalid temperature: #{data["temperature"]}" unless data["temperature"].is_a?(Numeric) && data["temperature"].between?(0, 1)

    raise ConfigurationError, "validation failed:
#{errors.map { |e| "  - #{e}" }.join("
")}" if errors.any?

    Log.info("config validated", errors: errors.size)
  end

  def rules
    @rules ||= {
      "shell" => @data.dig("shell", "rules") || {},
      "commands" => @data.dig("commands", "rules") || {},
      "filesystem" => @data.dig("filesystem", "rules") || {}
    }
  end

  private

  def resolve_canonical_path
    candidates = [
      File.expand_path("~/pub/master.yml"),
      File.join(Dir.pwd, "master.yml"),
      File.join(File.dirname(__FILE__), "master.yml")
    ]

    candidates.find { |path| File.exist?(path) } ||
      raise(ConfigurationError, "master.yml not found in: #{candidates.join(", ")}")
  end

  def load_with_healing
    raw = YAML.load_file(@config_path)
    heal_missing_sections(raw)
  rescue Errno::ENOENT
    Log.warn("config not found: #{@config_path}, using defaults")
    default_config
  rescue Psych::SyntaxError => e
    Log.fatal("config syntax error: #{e.message}")
  end

  def heal_missing_sections(config)
    config["model"] ||= Defaults::MODEL
    config["max_tokens"] ||= Defaults::MAX_TOKENS
    config["temperature"] ||= Defaults::TEMPERATURE
    config["session_store"] ||= Defaults.session_store
    config["shell"] ||= {}
    config["shell"]["interpreter"] ||= Defaults.shell
    config["shell"]["rules"] ||= {}
    config["commands"] ||= {}
    config["commands"]["rules"] ||= {}
    config["filesystem"] ||= {}
    config["filesystem"]["rules"] ||= {}
    config["filesystem"]["allowed_paths"] ||= Defaults.allowed_paths
    config
  end

  def default_config
    {
      "model" => Defaults::MODEL,
      "max_tokens" => Defaults::MAX_TOKENS,
      "temperature" => Defaults::TEMPERATURE,
      "session_store" => Defaults.session_store,
      "shell" => {
        "interpreter" => Defaults.shell,
        "rules" => {}
      },
      "commands" => {
        "rules" => {}
      },
      "filesystem" => {
        "rules" => {},
        "allowed_paths" => Defaults.allowed_paths
      }
    }
  end
end

class RuleValidator
  class ValidationError < StandardError
    attr_reader :suggestion

    def initialize(message, suggestion: nil)
      super(message)
      @suggestion = suggestion
    end
  end

  def initialize(config)
    @config = config
  end

  def validate_command!(command)
    banned = ["python", "bash", "sed", "awk", "wc", "head", "tail", "find", "sudo"]
    banned.each do |tool|
      if command.match?(/#{Regexp.escape(tool)}/)
        suggestion = case tool
                     when "python" then "use ruby instead"
                     when "bash" then "use zsh instead"
                     when "wc" then 'use zsh: ${#${(f)"$(< file)"}}'
                     when "head", "tail" then "use zsh array slicing: ${lines[1,20]}"
                     when "sed", "awk" then "use ruby or zsh parameter expansion"
                     else "use allowed alternative"
                     end
        raise ValidationError.new("#{tool} not allowed per master.yml constraints", suggestion: suggestion)
      end
    end
  end

  def validate_file!(path)
    forbidden = @config.data.dig("filesystem", "rules", "forbidden_paths") || []
    forbidden.each do |pattern|
      raise ValidationError.new("forbidden path: #{path}") if File.fnmatch(pattern, path)
    end

    allowed = @config.data.dig("filesystem", "allowed_paths") || Defaults.allowed_paths
    normalized = File.expand_path(path)
    unless allowed.any? { |ap| normalized.start_with?(File.expand_path(ap)) }
      raise ValidationError.new("path outside allowed directories: #{path}")
    end
  end
end

class Assistant
  attr_reader :messages, :state, :stats

  def initialize(config:, tools:, circuit_breaker:)
    @config = config
    @tools = tools
    @circuit_breaker = circuit_breaker
    @messages = []
    @state = :ready
    @stats = { input_tokens: 0, output_tokens: 0, api_calls: 0, tool_calls: 0 }
    @add_message_callback = nil
    @tool_execution_callback = nil
  end

  attr_writer :add_message_callback, :tool_execution_callback

  def add_message(role:, content:)
    @messages << { role: role, content: content }
    @add_message_callback&.call(@messages.last)
  end

  def add_message_and_run!(content:, auto_tool_execution: false)
    add_message(role: "user", content: content)
    run(auto_tool_execution: auto_tool_execution)
  end

  def run(auto_tool_execution: false)
    RetryWithBackoff.call(max_attempts: 3) do
      @circuit_breaker.call do
        make_api_request(auto_tool_execution)
      end
    end
  rescue CircuitBreaker::OpenError => e
    Log.error(e.message)
    @state = :error
  end

  def last_response
    @messages.last[:content] if @messages.last&.dig(:role) == "assistant"
  end

  def complete!
    @state = :complete
  end

  private

  def make_api_request(auto_tool_execution)
    @stats[:api_calls] += 1
    response = api_client.messages(
      model: @config.data["model"],
      max_tokens: @config.data["max_tokens"],
      temperature: @config.data["temperature"],
      messages: @messages,
      tools: @tools.flat_map { |t| t.class.to_anthropic_tools }
    )

    @stats[:input_tokens] += response["usage"]["input_tokens"]
    @stats[:output_tokens] += response["usage"]["output_tokens"]

    content = response["content"]
    add_message(role: "assistant", content: content)

    if content.any? { |c| c["type"] == "tool_use" }
      @state = :requires_action
      execute_tools(content) if auto_tool_execution
    else
      @state = :complete
    end
  end

  def execute_tools(content)
    tool_results = content.select { |c| c["type"] == "tool_use" }.map do |tool_use|
      @stats[:tool_calls] += 1
      tool_name = tool_use["name"]
      tool_input = tool_use["input"]
      tool_id = tool_use["id"]

      @tool_execution_callback&.call(tool_id, tool_name, nil, tool_input)

      tool = @tools.find { |t| t.class.tool_functions.key?(tool_name.to_sym) }
      result = tool.send(tool_name, **tool_input.transform_keys(&:to_sym))

      {
        type: "tool_result",
        tool_use_id: tool_id,
        content: JSON.generate(result)
      }
    end

    add_message(role: "user", content: tool_results)
    make_api_request(true)
  end

  def api_client
    @api_client ||= Anthropic::Client.new(api_key: @config.api_key)
  end
end

class CLI
  ALIASES = { "/t" => "/tools", "/s" => "/stats", "/c" => "/config", "/h" => "/help", "/r" => "/reload" }.freeze

  def initialize
    @config = Config.new
    @validator = RuleValidator.new(@config)
    @circuit_breaker = CircuitBreaker.new
    @metrics = Metrics.new
    @tools = [ShellTool.new(@config, @validator), FileTool.new(@config, @validator)]
    @assistant = Assistant.new(config: @config, tools: @tools, circuit_breaker: @circuit_breaker)
    @ui = TTY_AVAILABLE ? TTYInterface.new : BaseInterface.new
    setup_callbacks
    restore_session if ENV["RESUME"]
  end

  def run(args)
    case args.first
    when "--setup" then run_setup
    when "--check" then check_config
    when "--test" then run_tests
    when "--help", "-h" then show_help
    when nil then interactive
    else oneshot(args.join(" "))
    end
  rescue Interrupt
    Log.info("interrupted")
    exit 0
  rescue => e
    Log.error("fatal: #{e.message}")
    Log.debug(e.backtrace.first(5).join("
"))
    exit 1
  ensure
    Log.info("session metrics", **@metrics.report) if @metrics
  end

  private

  def interactive
    @ui.banner(@config)
    loop do
      input = @ui.prompt_input
      break if input.nil? || input =~ /A(exit|quit|bye)z/i
      next if input.strip.empty?
      handle_input(input)
    end
    save_session
    @ui.farewell
  end

  def handle_input(input)
    input.start_with?("/") ? handle_command(input) : send_to_assistant(input)
  rescue => e
    Log.error(e.message)
  end

  def send_to_assistant(content)
    compress_context! if approaching_limit?
    @metrics.increment("messages.sent")
    @metrics.time("assistant.response") do
      @ui.thinking { @assistant.add_message(role: "user", content: content); @assistant.run(auto_tool_execution: false) }
    end
    @metrics.increment("messages.received")
    @metrics.gauge(:input_tokens, @assistant.stats[:input_tokens])
    @metrics.gauge(:output_tokens, @assistant.stats[:output_tokens])
    Log.info("api_call", cost_usd: @metrics.cost_usd, cost_nok: @metrics.cost_nok)

    if @assistant.state == :requires_action
      approved = @assistant.messages.last[:content].select { |c| c["type"] == "tool_use" }.all? { |call| @ui.confirm_tool_execution(call["name"], call["input"]) }
      approved ? @ui.thinking("executing tools") { @assistant.run(auto_tool_execution: true) } : @assistant.complete!
    end
    @ui.assistant_response(@assistant.last_response) if @assistant.last_response
  end

  def handle_command(cmd)
    cmd = ALIASES[cmd] || cmd
    case cmd
    when "/tools" then list_tools
    when "/stats" then show_stats
    when "/config" then show_config
    when "/clear" then clear_conversation
    when "/save" then save_session(manual: true)
    when "/reload" then reload_master_yml
    when "/help" then show_help
    else Log.warn("unknown command: #{cmd}")
    end
  end

  def reload_master_yml
    @config = Config.new
    @validator = RuleValidator.new(@config)
    @tools = [ShellTool.new(@config, @validator), FileTool.new(@config, @validator)]
    version = @config.data.dig("meta", "version") || "unknown"
    Log.info("master.yml reloaded", version: version)
    @ui.section("configuration reloaded") { @ui.stat("version", version) }
  end

  def restore_session
    sessions = Dir["#{@config.data["session_store"]}/*.json"].sort
    return if sessions.empty?

    latest = JSON.parse(File.read(sessions.last), symbolize_names: true)
    @assistant.messages.replace(latest[:messages])
    Log.info("session restored", messages: @assistant.messages.size, file: File.basename(sessions.last))
    @ui.section("session restored") { @ui.stat("messages", @assistant.messages.size) }
  rescue => e
    Log.warn("session restore failed: #{e.message}")
  end

  def compress_context!
    return unless @assistant.messages.size > 15

    kept = @assistant.messages[0..1] + @assistant.messages[-10..-1]
    middle = @assistant.messages[2..-11]
    summary = "Previous conversation summarized: #{middle.size} messages"
    @assistant.messages.replace([kept[0], {role: "assistant", content: summary}] + kept[1..-1])
    Log.info("context compressed", from: kept.size + middle.size, to: @assistant.messages.size)
  end

  def approaching_limit?
    total = @assistant.stats[:input_tokens] + @assistant.stats[:output_tokens]
    total > 150_000
  end

  def list_tools
    @ui.section("available tools") do
      @tools.each { |tool| tool.class.tool_functions.each { |name, schema| @ui.list_item("#{name}: #{schema.description}") } }
    end
  end

  def show_stats
    stats = @assistant.stats
    @ui.section("session statistics") { stats.each { |k, v| @ui.stat(k.to_s, v) } }
  end

  def show_config
    @ui.section("configuration") do
      @ui.stat("model", @config.data["model"])
      @ui.stat("shell", @config.data.dig("shell", "interpreter"))
      @ui.stat("max_tokens", @config.data["max_tokens"])
      @ui.stat("temperature", @config.data["temperature"])
      @ui.stat("session_store", @config.data["session_store"])
    end
  end

  def clear_conversation
    @assistant.messages.clear
    @assistant.instance_variable_set(:@state, :ready)
    Log.info("conversation cleared")
  end

  def save_session(manual: false)
    return if @assistant.messages.empty?
    session_id = Time.now.strftime("%Y%m%d_%H%M%S")
    dir = @config.data["session_store"]
    FileUtils.mkdir_p(dir)
    file = File.join(dir, "#{session_id}.json")
    File.write(file, JSON.pretty_generate({ timestamp: Time.now.iso8601, model: @config.data["model"], messages: @assistant.messages, stats: @assistant.stats }))
    Log.info("session saved: #{session_id}") if manual
  rescue => e
    Log.warn("save failed: #{e.message}")
  end

  def oneshot(prompt)
    @assistant.add_message_and_run!(content: prompt, auto_tool_execution: false)
    if @assistant.state == :requires_action
      approved = @assistant.messages.last[:content].select { |c| c["type"] == "tool_use" }.all? { |call| @ui.confirm_tool_execution(call["name"], call["input"]) }
      @assistant.run(auto_tool_execution: true) if approved
    end
    @ui.puts @assistant.last_response if @assistant.last_response
  end

  def setup_callbacks
    @assistant.add_message_callback = ->(msg) { Log.debug("message added: #{msg[:role]}") }
    @assistant.tool_execution_callback = ->(id, name, method, args) { Log.info("executing: #{name}") }
  end

  def run_setup
    @ui.section("CONVERGENCE CLI setup") do
      api_key = @ui.masked_input("enter Anthropic API key:")
      config_path = File.expand_path("~/pub/master.yml")
      File.write(config_path, YAML.dump({ "api_key" => api_key }))
      Log.info("configuration saved to #{config_path}")
    end
  end

  def check_config
    @ui.section("configuration check") do
      key = @config.api_key
      @ui.stat("api_key", "#{key[0..10]}...")
      @ui.stat("model", @config.data["model"])
      @ui.stat("shell", @config.data.dig("shell", "interpreter"))
      @ui.stat("rules", @config.rules.keys.join(", "))
    end
  rescue => e
    Log.error(e.message)
    exit 1
  end

  def run_tests
    @ui.section("running self-tests") do
      tests = [
        -> { raise "no API key" unless @config.api_key; raise "no model" unless @config.data["model"] },
        -> { @validator.validate_command!("ls") },
        -> { raise "no tools" if @tools.empty? }
      ]
      passed = tests.count { |test| (test.call; Log.info("test passed"); true) rescue (Log.error("test failed: #{$!.message}"); false) }
      @ui.puts "
#{passed}/#{tests.size} tests passed"
      exit(passed == tests.size ? 0 : 1)
    end
  end

  HELP_TEXT = <<~HELP

    usage:
      cli.rb                  interactive mode
      cli.rb "prompt"         one-shot mode
      cli.rb --setup          interactive setup
      cli.rb --check          check configuration
      cli.rb --test           run self-tests
      RESUME=1 cli.rb         resume last session

    interactive commands:
      /tools (/t)     list available tools
      /stats (/s)     show session statistics (includes cost)
      /config (/c)    show configuration
      /reload (/r)    reload master.yml
      /clear          clear conversation
      /save           save session
      /help (/h)      show this help
      exit            exit CLI

    configuration:
      create master.yml in ~/pub/ (recommended)
      set ANTHROPIC_API_KEY environment variable

  HELP

  def show_help
    @ui.section("CONVERGENCE CLI v2.4.0 - help") { @ui.puts HELP_TEXT }
  end
end

class BaseInterface
  def banner(config)
    Log.info("CONVERGENCE v2.4.0 initialized")
    Log.info("model=#{config.data["model"]}")
    Log.info("shell=#{config.data.dig("shell", "interpreter")}")
    Log.info("security=#{PLEDGE_AVAILABLE ? "pledge+unveil" : "disabled"}")
  end

  def farewell = Log.info("session ended")
  def prompt_input = (print "
> "; $stdin.gets&.chomp)
  def masked_input(msg) = (print "#{msg} "; $stdin.gets&.chomp)

  def confirm_tool_execution(name, input)
    details = input.map { |k, v| "#{k}=#{v}" }.join(" ")
    print "execute #{name} #{details}? [Y/n] "
    response = $stdin.gets&.chomp&.downcase
    response.empty? || response == "y"
  end

  def thinking(msg = "processing")
    print "#{msg}..."
    result = yield
    puts " done"
    result
  end

  def assistant_response(text) = puts "
#{text}"
  def section(title) = (puts "
#{title}:"; yield)
  def list_item(text) = puts "  #{text}"
  def stat(label, value) = puts "  #{label}: #{value}"
  def puts(text) = Kernel.puts(text)
end

class TTYInterface < BaseInterface
  def initialize
    @prompt = TTY::Prompt.new(prefix: "", active_color: :cyan, help_color: :bright_black, error_color: :red)
    @pastel = Pastel.new
    @spinner = nil
  end

  def banner(config)
    puts
    puts @pastel.cyan.bold("CONVERGENCE CLI v2.4.0")
    puts
    puts "  model:      #{config.data["model"]}"
    puts "  shell:      #{config.data.dig("shell", "interpreter")}"
    puts "  security:   #{PLEDGE_AVAILABLE ? @pastel.green("pledge+unveil") : @pastel.yellow("disabled")}"
    puts
    puts @pastel.dim("  type /help for commands
")
  end

  def farewell = puts "
session ended"
  def prompt_input = @prompt.ask(">", required: false) { |q| q.modify :strip }
  def masked_input(msg) = @prompt.mask(msg)

  def confirm_tool_execution(name, input)
    details = input.map { |k, v| "#{k}: #{v}" }.join(", ")
    @prompt.yes?("execute #{@pastel.cyan(name)} (#{details})?")
  end

  def thinking(msg = "processing", &block)
    @spinner = TTY::Spinner.new("[:spinner] #{msg}...", format: :dots)
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
  def stat(label, value) = puts "  #{@pastel.dim(label + ":")} #{value}"
end

CLI.new.run(ARGV) if __FILE__ == $PROGRAM_NAME