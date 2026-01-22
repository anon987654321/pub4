#!/usr/bin/env ruby
# frozen_string_literal: true

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

module Convergence
  VERSION = "17.0.0".freeze
  
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

def apply_openbsd_security(level = :user)
  return unless RUBY_PLATFORM.include?("openbsd")
  
  config = Convergence::ACCESS_LEVELS[level]
  paths = config[:paths].call
  
  if paths == :all
    unveil_paths = [[ENV.fetch("HOME", "/"), "rwc"], ["/tmp", "rwc"], ["/usr", "rx"], ["/etc", "r"], ["/var", "rwc"]]
  else
    unveil_paths = paths.map { |p| [p, "rwc"] } + [["/usr", "rx"], ["/etc", "r"]]
  end
  
  unveil_paths.each do |path, perms|
    next unless Dir.exist?(path)
    Open3.capture3("unveil", path, perms)
  rescue => e
    nil
  end
  
  Open3.capture3("pledge", "stdio rpath wpath cpath inet dns proc exec fattr")
rescue => e
  nil
end

class MasterConfig
  attr_reader :version, :preferred_tools
  
  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze
  
  def initialize
    @config = load_config
    @version = @config.dig("meta", "version") || Convergence::VERSION
    @preferred_tools = @config.dig("meta", "preferred_tools") || %w[ruby zsh doas]
  end
  
  def preferred?(command)
    @preferred_tools.any? { |t| command.include?(t) }
  end
  
  private
  
  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    return default_config unless path
    
    YAML.safe_load_file(path, aliases: true)
  rescue => e
    default_config
  end
  
  def default_config
    { "meta" => { "version" => Convergence::VERSION, "preferred_tools" => %w[ruby zsh doas] } }
  end
end

class Config
  CONFIG_DIR = File.expand_path("~/.convergence").freeze
  CONFIG_PATH = File.join(CONFIG_DIR, "config.yml").freeze
  
  attr_accessor :provider, :api_key, :model, :access_level
  
  def self.load
    new.tap(&:load!)
  end
  
  def initialize
    @provider = :openrouter
    @api_key = nil
    @model = "deepseek/deepseek-r1"
    @access_level = :user
  end
  
  def load!
    return self unless File.exist?(CONFIG_PATH)
    
    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: true)
    return self unless data.is_a?(Hash)
    
    @provider = data["provider"]&.to_sym if data["provider"]
    @api_key = data["api_key"]
    @model = data["model"] || "deepseek/deepseek-r1"
    @access_level = data["access_level"]&.to_sym || :user
    self
  rescue => e
    self
  end
  
  def save
    FileUtils.mkdir_p(CONFIG_DIR)
    data = {
      "provider" => @provider.to_s,
      "api_key" => @api_key,
      "model" => @model,
      "access_level" => @access_level.to_s
    }
    File.write(CONFIG_PATH, YAML.dump(data))
    File.chmod(0600, CONFIG_PATH)
  rescue => e
    warn "Warning: Could not save config: #{e.message}"
  end
  
  def configured?
    @api_key && !@api_key.empty?
  end
end

class APIClient
  TOOL_SCHEMAS = [
    { type: "function", function: { name: "read_file", description: "Read file contents", parameters: { type: "object", properties: { path: { type: "string", description: "File path" } }, required: ["path"] } } },
    { type: "function", function: { name: "write_file", description: "Write file", parameters: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] } } },
    { type: "function", function: { name: "list_directory", description: "List directory", parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] } } },
    { type: "function", function: { name: "run_command", description: "Run shell command", parameters: { type: "object", properties: { command: { type: "string" }, timeout: { type: "integer" } }, required: ["command"] } } }
  ].freeze
  
  MODELS = {
    "deepseek-r1" => "deepseek/deepseek-r1",
    "deepseek-v3" => "deepseek/deepseek-chat",
    "claude-3.5" => "anthropic/claude-3.5-sonnet",
    "gpt-4o" => "openai/gpt-4o",
    "gpt-4o-mini" => "openai/gpt-4o-mini"
  }.freeze
  
  attr_reader :model
  
  def initialize(api_key:, model: nil)
    @api_key = api_key
    @model = model || "deepseek/deepseek-r1"
    @messages = []
    @base_url = "https://openrouter.ai/api/v1"
  end
  
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
    "Error: #{e.message}"
  end
  
  def chat_with_tools(message, executor:)
    @messages << { role: "user", content: message }
    
    5.times do
      response = call_api_with_tools
      
      if response[:tool_calls]
        response[:tool_calls].each do |tc|
          result = executor.execute(tc[:name], tc[:arguments])
          puts "[#{tc[:name]}] #{result[:error] || 'OK'}"
          @messages << { role: "tool", tool_call_id: tc[:id], name: tc[:name], content: JSON.generate(result) }
        end
      else
        return response[:content]
      end
    end
    
    "Tool iteration limit reached"
  rescue => e
    "Error: #{e.message}"
  end
  
  def clear_history = @messages = []
  def get_history = @messages
  def set_history(msgs) = @messages = msgs || []
  
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
  
  def send_streaming(uri, headers, body)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)
      accumulated = ""
      
      http.request(request) do |response|
        raise "API error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
        
        response.read_body do |chunk|
          chunk.each_line do |line|
            next if line.strip.empty? || !line.start_with?("data: ")
            data = line[6..-1].strip
            next if data == "[DONE]"
            
            begin
              delta = JSON.parse(data).dig("choices", 0, "delta", "content")
              if delta
                accumulated << delta
                yield delta
              end
            rescue JSON::ParserError
              next
            end
          end
        end
      end
      
      @messages << { role: "assistant", content: accumulated }
      accumulated
    end
  end
  
  def send_non_streaming(uri, headers, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    request = Net::HTTP::Post.new(uri)
    headers.each { |k, v| request[k] = v }
    request.body = JSON.generate(body)
    response = http.request(request)
    
    raise "API error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    
    content = JSON.parse(response.body).dig("choices", 0, "message", "content") || ""
    @messages << { role: "assistant", content: content }
    content
  end
end

class ShellTool
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

class FileTool
  def initialize(base_path:, access_level:)
    @base_path = File.expand_path(base_path)
    @level = access_level
  end
  
  def read(path:)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    return { error: "not a file" } unless File.file?(safe)
    
    { content: File.read(safe)[0..100000], size: File.size(safe) }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  def write(path:, content:)
    safe = enforce_sandbox!(path)
    FileUtils.mkdir_p(File.dirname(safe))
    File.write(safe, content)
    { success: true, bytes: content.bytesize }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  def list(path:)
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
  
  private
  
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

class ToolExecutor
  def initialize(file_tool:, shell_tool:)
    @file_tool = file_tool
    @shell_tool = shell_tool
  end
  
  def execute(name, arguments)
    args = arguments.transform_keys(&:to_sym)
    
    case name
    when "read_file" then @file_tool.read(**args)
    when "write_file" then @file_tool.write(**args)
    when "list_directory" then @file_tool.list(**args)
    when "run_command" then @shell_tool.execute(**args)
    else { error: "unknown tool: #{name}" }
    end
  rescue => e
    { error: e.message }
  end
end

class SessionManager
  SESSION_DIR = File.expand_path("~/.convergence/sessions").freeze
  
  def initialize
    FileUtils.mkdir_p(SESSION_DIR)
  rescue => e
    nil
  end
  
  def save(name, state)
    path = File.join(SESSION_DIR, "#{sanitize_name(name)}.yml")
    File.write(path, YAML.dump(state))
    true
  rescue => e
    false
  end
  
  def load(name)
    path = File.join(SESSION_DIR, "#{sanitize_name(name)}.yml")
    return nil unless File.exist?(path)
    
    YAML.safe_load_file(path, permitted_classes: [Symbol, Time, Hash, Array], aliases: true)
  rescue => e
    nil
  end
  
  def list
    Dir.glob(File.join(SESSION_DIR, "*.yml")).map { |f| File.basename(f, ".yml") }.sort
  rescue => e
    []
  end
  
  private
  
  def sanitize_name(name)
    name.gsub(/[^a-z0-9_-]/i, "_")
  end
end

class CLI
  COMMANDS = {
    "/help" => "Show this help",
    "/agent" => "Toggle agent mode (tools)",
    "/level [mode]" => "Switch access level",
    "/model [name]" => "View/switch model",
    "/key" => "Update API key",
    "/save [name]" => "Save session",
    "/load [name]" => "Load session",
    "/sessions" => "List sessions",
    "/clear" => "Clear history",
    "/quit" => "Exit"
  }.freeze
  
  def initialize
    @config = Config.load
    @master = MasterConfig.new
    @client = nil
    @session_mgr = SessionManager.new
    @running = false
    @agent_mode = false
  end
  
  def run
    apply_openbsd_security(@config.access_level)
    show_banner
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
    puts "\nGoodbye"
  end
  
  private
  
  def show_banner
    puts "Convergence #{Convergence::VERSION}"
    puts "Level: #{@config.access_level} | Master: #{@master.version}"
    puts "Type /help for commands\n\n"
  end
  
  def setup_client
    unless @config.configured?
      @config.api_key = ENV["OPENROUTER_API_KEY"] || prompt_secret("API key: ")
      @config.save
    end
    
    @client = APIClient.new(api_key: @config.api_key, model: @config.model)
  rescue => e
    puts "Warning: #{e.message}"
    exit 1
  end
  
  def setup_tools
    file_tool = FileTool.new(base_path: Dir.pwd, access_level: @config.access_level)
    shell_tool = ShellTool.new
    @tool_executor = ToolExecutor.new(file_tool: file_tool, shell_tool: shell_tool)
  end
  
  def read_input
    prompt = @agent_mode ? "[A]> " : "> "
    Readline.readline(prompt, true)&.strip
  rescue Interrupt
    nil
  end
  
  def handle_command(input)
    parts = input.split(" ", 2)
    cmd, arg = parts[0], parts[1]
    
    case cmd
    when "/help" then show_help
    when "/agent" then toggle_agent
    when "/level" then arg ? switch_level(arg) : show_level
    when "/model" then arg ? switch_model(arg) : show_model
    when "/key" then update_key
    when "/save" then save_session(arg)
    when "/load" then load_session(arg)
    when "/sessions" then list_sessions
    when "/clear" then @client.clear_history; puts "History cleared"
    when "/quit", "/exit" then @running = false
    else puts "Unknown command. Type /help"
    end
  rescue => e
    puts "Error: #{e.message}"
  end
  
  def handle_message(input)
    print "\n"
    
    if @agent_mode
      response = @client.chat_with_tools(input, executor: @tool_executor)
      puts response
    else
      @client.send(input) { |chunk| print chunk; $stdout.flush }
    end
    
    print "\n\n"
  rescue => e
    puts "\nError: #{e.message}\n\n"
  end
  
  def show_help
    puts "\nCommands:"
    COMMANDS.each { |cmd, desc| puts "  #{cmd.ljust(20)} #{desc}" }
    puts ""
  end
  
  def toggle_agent
    @agent_mode = !@agent_mode
    puts "Agent mode: #{@agent_mode ? 'ON' : 'OFF'}"
  end
  
  def show_level
    puts "Current: #{@config.access_level}"
    Convergence::ACCESS_LEVELS.each { |k, v| puts "  #{k}: #{v[:description]}" }
  end
  
  def switch_level(level)
    sym = level.to_sym
    return puts "Unknown: #{level}" unless Convergence::ACCESS_LEVELS.key?(sym)
    
    if sym == :admin
      print "Admin grants full access. Continue? [y/N]: "
      return unless $stdin.gets&.strip&.downcase == "y"
    end
    
    @config.access_level = sym
    @config.save
    puts "Switched to #{sym}"
    setup_tools
  end
  
  def show_model
    puts "Model: #{@config.model}"
  end
  
  def switch_model(name)
    if @client.switch_model(name)
      @config.model = @client.model
      @config.save
      puts "Switched to #{@config.model}"
    else
      puts "Unknown model: #{name}"
    end
  end
  
  def update_key
    @config.api_key = prompt_secret("New API key: ")
    @config.save
    setup_client
    puts "Key updated"
  end
  
  def save_session(name)
    name ||= Time.now.strftime("%Y%m%d_%H%M%S")
    state = { history: @client.get_history, created: Time.now.to_i }
    
    if @session_mgr.save(name, state)
      puts "Saved: #{name}"
    else
      puts "Failed to save session"
    end
  end
  
  def load_session(name)
    return puts "Usage: /load NAME" unless name
    
    state = @session_mgr.load(name)
    return puts "Not found: #{name}" unless state
    
    @client.set_history(state["history"])
    puts "Loaded: #{name}"
  end
  
  def list_sessions
    sessions = @session_mgr.list
    if sessions.empty?
      puts "No sessions"
    else
      puts "Sessions:"
      sessions.each { |s| puts "  #{s}" }
    end
  end
  
  def prompt_secret(prompt)
    print prompt
    if $stdin.tty?
      $stdin.noecho(&:gets).chomp.tap { puts }
    else
      $stdin.gets.chomp
    end
  rescue => e
    ""
  end
end

CLI.new.run if __FILE__ == $PROGRAM_NAME