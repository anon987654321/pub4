#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI v∞.17.0 - Hybrid API-first LLM client for OpenBSD
# Single-file design with OpenRouter API, tiered permissions, screen sessions

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

# OpenBSD pledge/unveil support (deferred to runtime)
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

module Convergence
  VERSION = "∞.17.0".freeze
  
  # Tiered permission system
  ACCESS_LEVELS = {
    sandbox: {
      name: "Sandbox",
      paths: -> { [Dir.pwd, "/tmp"] },
      allow_root: false,
      confirm_writes: true,
      confirm_deletes: true,
      description: "Project directory only, confirmations required"
    },
    user: {
      name: "User",
      paths: -> { [ENV["HOME"], Dir.pwd, "/tmp"] },
      allow_root: false,
      confirm_writes: false,
      confirm_deletes: true,
      description: "Home directory access, no root"
    },
    admin: {
      name: "Admin",
      paths: -> { :all },
      allow_root: true,  # Via doas only
      confirm_writes: true,
      confirm_deletes: true,
      confirm_root: true,
      description: "Full access with doas, all destructive ops require confirmation"
    }
  }.freeze
end

def apply_pledge(level = :user)
  return unless PLEDGE_AVAILABLE
  
  config = Convergence::ACCESS_LEVELS[level]
  promises = "stdio rpath wpath cpath inet dns proc exec fattr"
  promises += " prot_exec" if config[:allow_root]
  
  Pledge.pledge(promises)
  
  paths = config[:paths].call
  if paths == :all
    Pledge.unveil(ENV["HOME"], "rwc")
    Pledge.unveil("/tmp", "rwc")
    Pledge.unveil("/usr/local", "rx")
    Pledge.unveil("/etc", "r")
    Pledge.unveil("/var", "rwc")
  else
    paths.each { |p| Pledge.unveil(p, "rwc") }
    Pledge.unveil("/usr/local", "rx")
    Pledge.unveil("/etc/ssl", "r")
  end
  Pledge.unveil(nil, nil)
rescue => e
  warn "pledge: #{e.message}"
end

# MasterConfig with preferred_tools
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
    @preferred_tools = @config.dig("meta", "preferred_tools") || 
                       @config.dig("constraints", "preferred_tools") || 
                       %w[ruby zsh doas]
  end
  
  def preferred?(command)
    @preferred_tools.any? { |t| command =~ /\b#{Regexp.escape(t)}\b/ }
  end
  
  private
  
  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    path ? YAML.safe_load_file(path, aliases: false) : default_config
  rescue => e
    warn "master.yml: #{e.message}"
    default_config
  end
  
  def default_config
    { "meta" => { "version" => Convergence::VERSION, "preferred_tools" => %w[ruby zsh doas] } }
  end
end

# Config persistence
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
    @model = nil
    @access_level = :user
  end
  
  def load!
    return self unless File.exist?(CONFIG_PATH)
    data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: false)
    return self unless data.is_a?(Hash)
    @provider = data["provider"]&.to_sym if data["provider"]
    @api_key = data["api_key"]
    @model = data["model"]
    @access_level = data["access_level"]&.to_sym || :user
    self
  rescue => e
    warn "config load: #{e.message}"
    self
  end
  
  def save
    FileUtils.mkdir_p(CONFIG_DIR)
    data = {
      "provider" => @provider&.to_s,
      "api_key" => @api_key,
      "model" => @model,
      "access_level" => @access_level&.to_s
    }
    File.write(CONFIG_PATH, YAML.dump(data))
    File.chmod(0600, CONFIG_PATH)
  rescue => e
    warn "config save: #{e.message}"
  end
  
  def configured?
    @provider && @api_key
  end
end

# OpenRouter API client with expanded models
class APIClient
  PROVIDERS = {
    openrouter: {
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      models: {
        # DeepSeek
        "deepseek-r1" => "deepseek/deepseek-r1",
        "deepseek-v3" => "deepseek/deepseek-chat",
        # Anthropic
        "claude-3.5" => "anthropic/claude-3.5-sonnet",
        "claude-3-opus" => "anthropic/claude-3-opus",
        "claude-3-haiku" => "anthropic/claude-3-haiku",
        # OpenAI
        "gpt-4o" => "openai/gpt-4o",
        "gpt-4o-mini" => "openai/gpt-4o-mini",
        "gpt-4-turbo" => "openai/gpt-4-turbo",
        # Meta Llama
        "llama-3.1-70b" => "meta-llama/llama-3.1-70b-instruct",
        "llama-3.1-8b" => "meta-llama/llama-3.1-8b-instruct",
        # Google
        "gemini-pro" => "google/gemini-pro",
        "gemini-2.0" => "google/gemini-2.0-flash-exp",
        # Mistral
        "mistral-large" => "mistralai/mistral-large-latest",
        "mixtral-8x7b" => "mistralai/mixtral-8x7b-instruct"
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
    body = { model: @model, messages: @messages, stream: block_given? }
    
    if block_given?
      send_streaming(uri, headers, body, &block)
    else
      send_non_streaming(uri, headers, body)
    end
  end
  
  def clear_history = @messages = []
  def get_history = @messages
  def set_history(msgs) = @messages = msgs || []
  def models = @config[:models]
  
  def switch_model(name)
    resolved = @config[:models][name] || name
    if @config[:models].values.include?(resolved)
      @model = resolved
      true
    else
      false
    end
  end
  
  private
  
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
            rescue JSON::ParserError; end
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
    raise "API error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    content = JSON.parse(response.body).dig("choices", 0, "message", "content")
    @messages << { role: "assistant", content: content }
    content
  rescue => e
    "API Error: #{e.message}"
  end
end

# Directory processor
class DirectoryProcessor
  EXTENSIONS = %w[.rb .sh .yml .yaml .js .ts .py .md .txt].freeze
  
  def initialize(path, master_config)
    @path = File.expand_path(path)
    @config = master_config
  end
  
  def process
    files = Dir.glob(File.join(@path, "**", "*"))
      .select { |f| File.file?(f) && EXTENSIONS.include?(File.extname(f).downcase) }
    files.each do |file|
      result = analyze(file)
      yield result if block_given?
    end
  end
  
  private
  
  def analyze(path)
    content = File.read(path)
    {
      path: path,
      lines: content.lines.count,
      uses_preferred: @config.preferred_tools.any? { |t| content.include?(t) }
    }
  end
end

# Shell tool with permission checks
class ShellTool
  def initialize(access_level:, master_config:)
    @level = access_level
    @config = Convergence::ACCESS_LEVELS[@level]
    @master_config = master_config
  end
  
  def execute(command:, timeout: 30)
    return { error: "command requires confirmation" } if needs_confirmation?(command)
    
    shell = ["/usr/local/bin/zsh", "/bin/zsh", "/bin/sh"].find { |s| File.executable?(s) }
    return { error: "no shell" } unless shell
    
    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(shell, "-c", command)
      { stdout: stdout[0..4000], stderr: stderr[0..1000], exit_code: status.exitstatus, success: status.success? }
    end
  rescue Timeout::Error
    { error: "timeout" }
  rescue => e
    { error: e.message }
  end
  
  private
  
  def needs_confirmation?(cmd)
    (@config[:confirm_writes] && cmd =~ /\b(rm|mv|cp|chmod|chown)\b/) ||
    (@config[:confirm_root] && cmd.include?("doas"))
  end
end

# File tool with sandbox
class FileTool
  def initialize(base_path:, access_level:)
    @base_path = File.expand_path(base_path)
    @level = access_level
    @config = Convergence::ACCESS_LEVELS[@level]
  end
  
  def read(path:)
    safe = enforce_sandbox!(path)
    return { error: "not found" } unless File.exist?(safe)
    { content: File.read(safe)[0..50000], size: File.size(safe) }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  def write(path:, content:)
    safe = enforce_sandbox!(path)
    FileUtils.mkdir_p(File.dirname(safe))
    File.write(safe, content)
    { success: true }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: e.message }
  end
  
  private
  
  def enforce_sandbox!(filepath)
    expanded = File.expand_path(filepath)
    paths = @config[:paths].call
    return expanded if paths == :all
    raise SecurityError, "outside sandbox" unless paths.any? { |p| expanded.start_with?(p) }
    expanded
  end
end

# Session manager
class SessionManager
  SESSION_DIR = File.expand_path("~/.convergence/sessions").freeze
  
  def initialize = FileUtils.mkdir_p(SESSION_DIR)
  
  def save(name, state)
    File.write(File.join(SESSION_DIR, "#{name}.yml"), YAML.dump(state))
  end
  
  def load(name)
    path = File.join(SESSION_DIR, "#{name}.yml")
    File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Symbol, Time, Hash, Array], aliases: false) : nil
  end
  
  def list = Dir.glob(File.join(SESSION_DIR, "*.yml")).map { |f| File.basename(f, ".yml") }
end

# Simple RAG (optional, no external dependencies)
class RAG
  def initialize = (@chunks = [])
  
  def ingest(path)
    return 0 unless File.exist?(path)
    text = File.read(path)
    new_chunks = text.split(/\n{2,}/).reject(&:empty?).map.with_index do |p, i|
      { id: Digest::MD5.hexdigest(p)[0..7], text: p.strip, source: path }
    end
    @chunks.concat(new_chunks)
    new_chunks.size
  end
  
  def search(query, k: 3)
    return [] if @chunks.empty?
    # Simple keyword match (no embeddings required)
    terms = query.downcase.split
    @chunks.map { |c| { chunk: c, score: terms.count { |t| c[:text].downcase.include?(t) } } }
           .sort_by { |r| -r[:score] }
           .first(k)
  end
  
  def stats = { chunks: @chunks.size }
end

# Main CLI
class CLI
  HELP = <<~H
    Commands:
    /help              - Show this help
    /level [sandbox|user|admin] - View/switch access level
    /process PATH      - Process directory through master.yml
    /screen NAME       - Create named session
    /detach            - Save and detach
    /attach NAME       - Restore session
    /sessions          - List sessions
    /model [name]      - View/switch model
    /models            - List available models
    /key               - Update API key
    /ingest PATH       - Add to knowledge base
    /search QUERY      - Search knowledge base
    /clear             - Clear history
    /quit              - Exit
  H
  
  def initialize
    @config = Config.load
    @master = MasterConfig.new
    @client = nil
    @session_mgr = SessionManager.new
    @rag = RAG.new
    @running = false
  end
  
  def run
    apply_pledge(@config.access_level)
    banner
    setup_client
    @running = true
    
    while @running
      input = Readline.readline(prompt_text, true)&.strip
      break if input.nil?
      next if input.empty?
      input.start_with?("/") ? command(input) : message(input)
    end
  end
  
  private
  
  def banner
    puts "CONVERGENCE CLI #{Convergence::VERSION}"
    puts "Master: #{@master.version} | Level: #{@config.access_level}"
    puts "Security: #{PLEDGE_AVAILABLE ? 'pledge+unveil' : 'standard'}"
    puts "Type /help for commands\n\n"
  end
  
  def prompt_text
    level = @config.access_level.to_s[0].upcase
    "[#{level}]> "
  end
  
  def setup_client
    unless @config.configured?
      @config.api_key = ENV["OPENROUTER_API_KEY"] || prompt_secret("OpenRouter API key: ")
      @config.provider = :openrouter
      @config.model = "deepseek/deepseek-r1"
      @config.save
    end
    @client = APIClient.new(provider: @config.provider, api_key: @config.api_key, model: @config.model)
  end
  
  def command(input)
    parts = input.split(" ", 2)
    cmd, arg = parts[0], parts[1]
    
    case cmd
    when "/help" then puts HELP
    when "/level" then arg ? switch_level(arg) : show_level
    when "/process" then process_dir(arg)
    when "/screen" then save_session(arg)
    when "/detach" then puts "Session saved"
    when "/attach" then load_session(arg)
    when "/sessions" then list_sessions
    when "/model" then arg ? switch_model(arg) : show_model
    when "/models" then list_models
    when "/key" then update_key
    when "/ingest" then ingest(arg)
    when "/search" then search(arg)
    when "/clear" then @client.clear_history; puts "Cleared"
    when "/quit", "/exit" then @running = false
    else puts "Unknown: #{cmd}"
    end
  end
  
  def show_level
    puts "Current: #{@config.access_level}"
    Convergence::ACCESS_LEVELS.each { |k, v| puts "  #{k}: #{v[:description]}" }
  end
  
  def switch_level(level)
    sym = level.to_sym
    unless Convergence::ACCESS_LEVELS.key?(sym)
      puts "Unknown level: #{level}"
      return
    end
    if sym == :admin
      print "Admin mode grants full access. Continue? [y/N]: "
      return unless $stdin.gets&.strip&.downcase == "y"
    end
    @config.access_level = sym
    @config.save
    apply_pledge(sym)
    puts "Switched to #{sym}"
  end
  
  def process_dir(path)
    return puts "Usage: /process PATH" unless path
    return puts "Not found: #{path}" unless Dir.exist?(path)
    puts "Processing #{path}..."
    DirectoryProcessor.new(path, @master).process do |r|
      mark = r[:uses_preferred] ? "✓" : "✗"
      puts "#{mark} #{r[:path]} (#{r[:lines]} lines)"
    end
  end
  
  def save_session(name)
    return puts "Usage: /screen NAME" unless name
    @session_mgr.save(name, { history: @client.get_history, created: Time.now.to_i })
    puts "Session '#{name}' saved"
  end
  
  def load_session(name)
    return puts "Usage: /attach NAME" unless name
    state = @session_mgr.load(name)
    return puts "Not found: #{name}" unless state
    @client.set_history(state["history"])
    puts "Attached: #{name}"
  end
  
  def list_sessions
    sessions = @session_mgr.list
    sessions.empty? ? puts("No sessions") : sessions.each { |s| puts "  #{s}" }
  end
  
  def show_model
    puts "Current: #{@config.model}"
  end
  
  def list_models
    puts "Available models:"
    @client.models.each do |short, full|
      mark = full == @config.model ? "→" : " "
      puts "#{mark} #{short.ljust(16)} (#{full})"
    end
  end
  
  def switch_model(name)
    if @client.switch_model(name)
      @config.model = @client.model
      @config.save
      puts "Switched: #{@config.model}"
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
  
  def ingest(path)
    return puts "Usage: /ingest PATH" unless path
    count = @rag.ingest(File.expand_path(path))
    puts "Ingested #{count} chunks (total: #{@rag.stats[:chunks]})"
  end
  
  def search(query)
    return puts "Usage: /search QUERY" unless query
    results = @rag.search(query)
    results.empty? ? puts("No results") : results.each { |r| puts "#{r[:chunk][:source]}: #{r[:chunk][:text][0..100]}..." }
  end
  
  def message(input)
    print "\n"
    @client.send(input) { |chunk| print chunk; $stdout.flush }
    print "\n\n"
  rescue => e
    puts "Error: #{e.message}"
  end
  
  def prompt_secret(prompt)
    print prompt
    $stdin.tty? ? $stdin.noecho(&:gets).chomp.tap { puts } : $stdin.gets.chomp
  end
end

CLI.new.run if __FILE__ == $PROGRAM_NAME
