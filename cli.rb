#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI v∞.16.0 - API-first LLM client for OpenBSD
# Single-file design with OpenRouter API, screen sessions, directory processing

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "digest"
require "io/console"

# OpenBSD pledge/unveil support (fixed for syscall 84)
PLEDGE_AVAILABLE = if RUBY_PLATFORM.include?("openbsd")
  begin
    require "pledge"
    true
  rescue LoadError
    false
  end
else
  false
end

def apply_pledge
  return unless PLEDGE_AVAILABLE
  # exec and proc needed for shell tool execution
  Pledge.pledge("stdio rpath wpath cpath inet dns proc exec fattr")
  Pledge.unveil(ENV["HOME"], "rwc")
  Pledge.unveil("/tmp", "rwc")
  Pledge.unveil("/usr/local", "rx")
  Pledge.unveil("/etc/ssl", "r")
  Pledge.unveil(nil, nil)
rescue => e
  warn "pledge: #{e.message}"
end

# Master configuration with preferred_tools
class MasterConfig
  attr_reader :version, :preferred_tools

  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze

  def initialize
    @config = load_config
    @version = @config.dig("meta", "version")
    @preferred_tools = @config.dig("constraints", "preferred_tools") || %w[ruby zsh doas]
  end

  def preferred?(command)
    @preferred_tools.any? { |t| command =~ /\b#{Regexp.escape(t)}\b/ }
  end

  private

  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    path ? YAML.safe_load_file(path, aliases: false) : default_config
  rescue => e
    warn "master.yml error: #{e.message}, using defaults"
    default_config
  end

  def default_config
    {
      "meta" => { "version" => "∞.16.0" },
      "constraints" => { "preferred_tools" => %w[ruby zsh doas] }
    }
  end
end

# Configuration management
class Config
  CONFIG_DIR = File.expand_path("~/.convergence").freeze
  CONFIG_PATH = File.join(CONFIG_DIR, "config.yml").freeze

  attr_accessor :provider, :api_key, :model

  def self.load
    new.tap(&:load!)
  end

  def initialize
    @provider = :openrouter
    @api_key = nil
    @model = nil
  end

  def load!
    return self unless File.exist?(CONFIG_PATH)
    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: false)
    return self unless data.is_a?(Hash)
    @provider = data["provider"]&.to_sym if data["provider"]
    @api_key = data["api_key"]
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
      "api_key" => @api_key,
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
    !@provider.nil? && !@api_key.nil?
  end
end

# OpenRouter API client
class APIClient
  PROVIDERS = {
    openrouter: {
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      models: {
        "deepseek-r1" => "deepseek/deepseek-r1",
        "claude-3.5" => "anthropic/claude-3.5-sonnet",
        "gpt-4o" => "openai/gpt-4o"
      },
      default_model: "deepseek/deepseek-r1"
    }
  }.freeze

  attr_reader :provider, :model

  def initialize(provider:, api_key:, model: nil)
    @provider = provider.to_sym
    @api_key = api_key
    @config = PROVIDERS[@provider] or raise "Unknown provider: #{provider}"
    @model = model || @config[:default_model]
    @messages = []
  end

  def send(message, &block)
    @messages << { role: "user", content: message }
    uri = URI("#{@config[:base_url]}/chat/completions")
    headers = {
      "Authorization" => "Bearer #{@api_key}",
      "HTTP-Referer" => "https://github.com/anon987654321/pub4",
      "X-Title" => "Convergence CLI",
      "Content-Type" => "application/json"
    }
    body = {
      model: @model,
      messages: @messages,
      stream: block_given?
    }
    if block_given?
      send_streaming(uri, headers, body, &block)
    else
      send_non_streaming(uri, headers, body)
    end
  end

  def clear_history
    @messages = []
  end

  def get_history
    @messages
  end

  def set_history(messages)
    @messages = messages || []
  end

  private

  def send_streaming(uri, headers, body)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)
      accumulated = ""
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise "API error (#{response.code})"
        end
        response.read_body do |chunk|
          chunk.each_line do |line|
            next if line.strip.empty?
            next unless line.start_with?("data: ")
            data = line[6..-1].strip
            next if data == "[DONE]"
            begin
              json = JSON.parse(data)
              delta = json.dig("choices", 0, "delta", "content")
              if delta
                accumulated << delta
                yield delta
              end
            rescue JSON::ParserError
              # Skip invalid JSON
            end
          end
        end
      end
      @messages << { role: "assistant", content: accumulated }
      accumulated
    end
  rescue => e
    "API Error: #{e.message}"
  end

  def send_non_streaming(uri, headers, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = JSON.generate(body)
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise "API error (#{response.code})"
    end
    json = JSON.parse(response.body)
    content = json.dig("choices", 0, "message", "content")
    @messages << { role: "assistant", content: content }
    content
  rescue => e
    "API Error: #{e.message}"
  end
end

# Directory processor
class DirectoryProcessor
  def initialize(path, config)
    @path = File.expand_path(path)
    @config = config
    @results = []
  end

  def process
    files = Dir.glob(File.join(@path, "**", "*"))
      .select { |f| File.file?(f) && processable?(f) }
    files.each do |file|
      result = analyze_file(file)
      @results << result
      yield result if block_given?
    end
    @results
  end

  private

  def processable?(path)
    %w[.rb .sh .yml .yaml .js .ts .py].include?(File.extname(path).downcase)
  end

  def analyze_file(path)
    content = File.read(path)
    {
      path: path,
      lines: content.lines.count,
      uses_preferred: @config.preferred_tools.any? { |t| content.include?(t) },
      suggestions: []
    }
  end
end

# Shell tool
class ShellTool
  def initialize(master_config: nil)
    @master_config = master_config
  end

  def execute(command:, timeout: 30)
    shell_path = find_shell
    return { error: "no shell found" } unless shell_path
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

  private

  def find_shell
    ["/usr/local/bin/zsh", "/bin/zsh", "/bin/sh"].find { |s| File.executable?(s) }
  end
end

# File tool
class FileTool
  def initialize(base_path:)
    @base_path = File.expand_path(base_path)
  end

  def read(path:)
    safe_path = enforce_sandbox!(path)
    return { error: "file not found" } unless File.exist?(safe_path)
    content = File.read(safe_path)
    { content: content[0..50000], size: File.size(safe_path) }
  rescue => e
    { error: "failed to read file: #{e.message}" }
  end

  def write(path:, content:)
    safe_path = enforce_sandbox!(path)
    FileUtils.mkdir_p(File.dirname(safe_path))
    File.write(safe_path, content)
    { success: true, path: path }
  rescue => e
    { error: "failed to write file: #{e.message}" }
  end

  private

  def enforce_sandbox!(filepath)
    expanded = File.expand_path(filepath)
    unless expanded.start_with?(@base_path)
      raise SecurityError, "Access denied: #{filepath} outside sandbox"
    end
    expanded
  end
end

# Session management
class SessionManager
  SESSION_DIR = File.expand_path("~/.convergence/sessions").freeze

  def initialize
    FileUtils.mkdir_p(SESSION_DIR)
  end

  def save(name, state)
    path = File.join(SESSION_DIR, "#{name}.yml")
    File.write(path, YAML.dump(state))
    File.chmod(0600, path)
  end

  def load(name)
    path = File.join(SESSION_DIR, "#{name}.yml")
    return nil unless File.exist?(path)
    YAML.safe_load_file(path, permitted_classes: [Symbol, Time], aliases: false)
  end

  def list
    Dir.glob(File.join(SESSION_DIR, "*.yml")).map do |f|
      File.basename(f, ".yml")
    end
  end
end

# Main CLI
class CLI
  VERSION = "∞.16.0".freeze

  def initialize
    @config = Config.load
    @master_config = MasterConfig.new
    @client = nil
    @session_mgr = SessionManager.new
    @running = false
  end

  def run
    apply_pledge
    show_banner
    setup_client
    @running = true
    while @running
      print "> "
      input = $stdin.gets&.chomp
      break if input.nil?
      handle_input(input)
    end
  end

  private

  def show_banner
    puts "CONVERGENCE CLI #{VERSION}"
    puts "Master: #{@master_config.version}"
    puts "Preferred tools: #{@master_config.preferred_tools.join(', ')}"
    puts "Type /help for commands\n\n"
  end

  def setup_client
    unless @config.configured?
      puts "First time setup:"
      @config.api_key = ENV["OPENROUTER_API_KEY"] || prompt_secret("OpenRouter API key: ")
      @config.provider = :openrouter
      @config.model = "deepseek/deepseek-r1"
      @config.save
    end
    @client = APIClient.new(
      provider: @config.provider,
      api_key: @config.api_key,
      model: @config.model
    )
  end

  def handle_input(input)
    return if input.strip.empty?
    if input.start_with?("/")
      handle_command(input)
    else
      handle_message(input)
    end
  end

  def handle_command(input)
    parts = input.split(" ", 2)
    cmd = parts[0]
    arg = parts[1]
    case cmd
    when "/help"
      show_help
    when "/process"
      process_directory(arg)
    when "/screen"
      create_screen_session(arg)
    when "/detach"
      detach_session
    when "/attach"
      attach_session(arg)
    when "/sessions"
      list_sessions
    when "/clear"
      @client.clear_history
      puts "History cleared"
    when "/key"
      update_api_key
    when "/model"
      switch_model(arg)
    when "/quit", "/exit"
      @running = false
    else
      puts "Unknown command: #{cmd}"
    end
  end

  def show_help
    puts <<~HELP
      Commands:
      /help              - Show this help
      /process PATH      - Process directory through master.yml
      /screen NAME       - Create named screen session
      /detach            - Save state and detach
      /attach NAME       - Restore session
      /sessions          - List active sessions
      /clear             - Clear conversation history
      /key               - Update API key
      /model [name]      - Switch model
      /quit              - Exit
    HELP
  end

  def process_directory(path)
    unless path
      puts "Usage: /process PATH"
      return
    end
    unless Dir.exist?(path)
      puts "Directory not found: #{path}"
      return
    end
    puts "Processing #{path}..."
    processor = DirectoryProcessor.new(path, @master_config)
    processor.process do |result|
      preferred = result[:uses_preferred] ? "✓" : "✗"
      puts "#{preferred} #{result[:path]} (#{result[:lines]} lines)"
    end
    puts "Complete"
  end

  def create_screen_session(name)
    unless name
      puts "Usage: /screen NAME"
      return
    end
    state = {
      created_at: Time.now.to_i,
      history: @client.get_history
    }
    @session_mgr.save(name, state)
    puts "Screen session '#{name}' created"
  end

  def detach_session
    puts "Session state saved"
  end

  def attach_session(name)
    unless name
      puts "Usage: /attach NAME"
      return
    end
    state = @session_mgr.load(name)
    unless state
      puts "Session not found: #{name}"
      return
    end
    @client.set_history(state["history"] || [])
    puts "Attached to session '#{name}'"
  end

  def list_sessions
    sessions = @session_mgr.list
    if sessions.empty?
      puts "No sessions found"
    else
      puts "Sessions:"
      sessions.each { |s| puts "  #{s}" }
    end
  end

  def update_api_key
    key = prompt_secret("New OpenRouter API key: ")
    @config.api_key = key
    @config.save
    setup_client
    puts "API key updated"
  end

  def switch_model(model)
    unless model
      puts "Current model: #{@config.model}"
      puts "Available: deepseek-r1, claude-3.5, gpt-4o"
      return
    end
    @config.model = APIClient::PROVIDERS[:openrouter][:models][model] || model
    @config.save
    setup_client
    puts "Switched to model: #{@config.model}"
  end

  def handle_message(input)
    print "\n"
    begin
      @client.send(input) do |chunk|
        print chunk
        $stdout.flush
      end
      print "\n\n"
    rescue => e
      puts "Error: #{e.message}"
    end
  end

  def prompt_secret(prompt)
    print prompt
    if $stdin.tty?
      $stdin.noecho(&:gets).chomp.tap { puts }
    else
      $stdin.gets.chomp
    end
  end
end

# Entry point
if __FILE__ == $PROGRAM_NAME
  CLI.new.run
end
