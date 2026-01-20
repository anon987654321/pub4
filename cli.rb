#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI v∞.16.0 — Consolidated Multi-LLM CLI
# Single-file consolidation with tiered permissions, pledge/unveil, RAG, and NN/g usability

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "digest"
require "set"

# ============================================================================
# TIER PERMISSION SYSTEM
# ============================================================================

module Convergence
  # Access levels for file/system operations
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
      allow_root: true,  # Via doas, never sudo
      confirm_writes: true,   # ALWAYS confirm destructive ops
      confirm_deletes: true,  # ALWAYS confirm deletes
      confirm_root: true,     # ALWAYS confirm root commands
      description: "Full access with doas, all destructive ops require confirmation"
    }
  }.freeze
end

# ============================================================================
# PLEDGE/UNVEIL INTEGRATION - jeremyevans/ruby-pledge
# ============================================================================

PLEDGE_AVAILABLE = if RUBY_PLATFORM =~ /openbsd/
  begin
    require 'unveil'  # From jeremyevans/ruby-pledge, includes pledge
    true
  rescue LoadError
    # Auto-install if missing
    if !ENV["NO_AUTO_INSTALL"]
      warn "installing pledge gem..."
      result = system("gem install pledge --user-install --no-document --quiet 2>/dev/null")
      if result
        Gem.clear_paths
        begin
          require 'unveil'
          true
        rescue LoadError
          false
        end
      else
        false
      end
    else
      false
    end
  end
else
  false
end

# Apply pledge/unveil based on access level
def apply_security_sandbox(level)
  return unless PLEDGE_AVAILABLE
  
  config = Convergence::ACCESS_LEVELS[level]
  paths = config[:paths].is_a?(Proc) ? config[:paths].call : config[:paths]
  
  # Build unveil hash (path => permissions)
  unveil_paths = if paths == :all
    # Admin mode: unveil common paths with appropriate permissions
    {
      ENV["HOME"] => "rwxc",
      "/tmp" => "rwxc",
      "/usr/local" => "rx",
      "/etc" => "r",
      "/var" => "rwc"
    }
  else
    # Sandbox/User mode: restrict to specified paths
    paths.each_with_object({}) do |path, hash|
      hash[path] = "rwxc"
    end.merge({
      "/usr/local" => "rx",  # For gems and tools
      "/etc/ssl" => "r"      # For HTTPS
    })
  end
  
  # Apply unveil - call individually for each path as per jeremyevans/ruby-pledge API
  unveil_paths.each { |path, perms| Pledge.unveil(path, perms) }
  Pledge.unveil(nil, nil)  # Lock unveil
  
  # Apply pledge (restricts syscalls)
  promises = "stdio rpath wpath cpath inet dns proc exec tty"
  promises += " prot_exec" if config[:allow_root]  # Needed for doas
  Pledge.pledge(promises)
  
  Log.info("security: pledge+unveil applied", level: level) if defined?(Log)
rescue => e
  Log.warn("security: pledge/unveil failed", error: e.message) if defined?(Log)
  warn "pledge/unveil warning: #{e.message}"
end

# ============================================================================
# GEM AUTO-INSTALLATION
# ============================================================================

FIRST_RUN = !File.exist?(File.expand_path("~/.convergence_installed"))

def ensure_gem(name, require_as = nil)
  require(require_as || name)
  true
rescue LoadError
  return false if ENV["NO_AUTO_INSTALL"]
  
  warn "installing #{name}..." if FIRST_RUN
  result = system("gem install #{name} --user-install --no-document --quiet 2>/dev/null")
  return false unless result
  
  Gem.clear_paths
  begin
    require(require_as || name)
    true
  rescue LoadError
    false
  end
end

# ============================================================================
# MASTER CONFIG
# ============================================================================

class MasterConfig
  attr_reader :version, :banned_tools

  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze

  DANGEROUS_PATTERNS = [
    /rm\s+-rf\s+\/\s*$/,          # rm -rf / at end of command
    /rm\s+-rf\s+\/\*\s*$/,        # rm -rf /* at end of command
    /rm\s+-rf\s+~\s*$/,           # rm -rf ~ at end of command
    /rm\s+-rf\s+\$HOME\s*$/,      # rm -rf $HOME at end of command
    />\s*\/etc\/passwd\s*$/,      # > /etc/passwd at end
    />\s*\/etc\/shadow\s*$/,      # > /etc/shadow at end
    />\s*\/etc\/sudoers\s*$/,     # > /etc/sudoers at end
    /\|\s*sh\s*$/,                # | sh at end of command
    /\|\s*bash\s*$/,              # | bash at end of command
    /curl.*\|\s*sh\s*$/,          # curl ... | sh pattern
    /wget.*\|\s*sh\s*$/           # wget ... | sh pattern
  ].freeze

  def initialize
    @config = load_config
    @version = @config["version"] || @config.dig("meta", "version")
    @banned_tools = @config.dig("constraints", "banned_tools") || []
    @banned_regex = Regexp.new("\\b(" + @banned_tools.map { |t| Regexp.escape(t) }.join('|') + ")\\b") if @banned_tools.any?
  end

  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    path ? YAML.safe_load_file(path, aliases: false) : default_config
  rescue => e
    warn "master.yml error: #{e.message}, using defaults"
    default_config
  end

  def banned?(command) = @banned_regex ? command =~ @banned_regex : false

  def banned_tool(command)
    return nil unless @banned_regex && command =~ @banned_regex
    match = command.match(@banned_regex)
    match ? match[1] : nil
  end

  def dangerous?(command) = DANGEROUS_PATTERNS.any? { |pattern| command =~ pattern }

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

  private

  def default_config = { "meta" => { "version" => "∞.16.0" }, "constraints" => { "banned_tools" => %w[python bash sed awk wc head tail find sudo] } }
end

MASTER_CONFIG = MasterConfig.new

# ============================================================================
# BROWSER DETECTION
# ============================================================================

def find_browser
  %w[/usr/bin/chromium /usr/bin/google-chrome /usr/local/bin/chrome /usr/bin/chromium-browser /snap/bin/chromium].find { |p| File.executable?(p) }
end

def check_browser
  return true if find_browser
  warn "no browser - install chromium or set ANTHROPIC_API_KEY"
  false
end

# ============================================================================
# GEM AVAILABILITY CHECKS
# ============================================================================

TTY = ensure_gem("tty-prompt") && ensure_gem("tty-spinner") && ensure_gem("pastel")
FERRUM = ensure_gem("ferrum")
ANTHROPIC = ensure_gem("anthropic")
LANGCHAIN = ensure_gem("langchainrb")

if FIRST_RUN
  FileUtils.touch(File.expand_path("~/.convergence_installed"))
  warn "setup complete\n"
end

unless ANTHROPIC && ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-")
  unless FERRUM && check_browser
    warn "no backend"
    exit 1
  end
end

# ============================================================================
# LOGGING
# ============================================================================

module Log
  def self.info(msg, **ctx) = $stderr.puts JSON.generate({ t: Time.now.strftime("%H:%M:%S"), l: :info, m: msg }.merge(ctx)) if ENV["LOG_JSON"]
  def self.warn(msg, **ctx) = $stderr.puts JSON.generate({ t: Time.now.strftime("%H:%M:%S"), l: :warn, m: msg }.merge(ctx)) if ENV["LOG_JSON"]
  def self.error(msg, **ctx) = $stderr.puts JSON.generate({ t: Time.now.strftime("%H:%M:%S"), l: :error, m: msg }.merge(ctx)) if ENV["LOG_JSON"]
end

# ============================================================================
# UI MODULE
# ============================================================================

module UI
  extend self

  def init = (@pastel = TTY ? Pastel.new : nil; @prompt = TTY ? TTY::Prompt.new : nil)

  def puts(text = "") = Kernel.puts(text)

  def c(style, text) = @pastel ? @pastel.send(style, text) : text

  def banner(mode, access_level)
    puts "convergence v∞.16.0"
    puts "mode: #{mode}"
    puts "access: #{Convergence::ACCESS_LEVELS[access_level][:name]} (#{access_level})"
    puts "master.yml: v#{MASTER_CONFIG.version}" if MASTER_CONFIG.version
    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}" if RUBY_PLATFORM =~ /openbsd/
    puts "type /help for commands\n"
  end

  def prompt = TTY ? @prompt.ask(">", required: false)&.strip : (print "> "; $stdin.gets&.chomp)

  def thinking(msg = "thinking") = TTY ? (s = TTY::Spinner.new("#{msg}...", format: :dots); s.auto_spin; yield.tap { s.success("") }) : (print "#{msg}... "; yield.tap { puts "done" })

  def response(text) = puts("\n#{text}\n")

  def error(msg) = puts(c(:red, "error: #{msg}"))

  def status(msg) = puts(c(:dim, msg))

  def confirm(msg) = TTY ? @prompt.yes?(msg) : (print "#{msg} (y/n) "; $stdin.gets&.chomp&.downcase == "y")
end

# ============================================================================
# WEBCHAT WITH STEALTH MODE
# ============================================================================

class WebChat
  STEALTH_OPTIONS = {
    "disable-blink-features" => "AutomationControlled",
    "disable-features" => "IsolateOrigins,site-per-process",
    "disable-infobars" => nil,
    "no-first-run" => nil
  }.freeze
  
  STEALTH_JS = <<~JS
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    window.chrome = { runtime: {} };
  JS

  PROVIDERS = {
    "claude" => { url: "https://claude.ai", input: 'div[contenteditable="true"]', response: '.font-claude-message' },
    "grok" => { url: "https://grok.x.ai", input: 'textarea[placeholder*="Ask"]', response: '[data-testid="message-content"]' },
    "deepseek" => { url: "https://chat.deepseek.com", input: 'textarea#chat-input', response: '.markdown-body' },
    "chatgpt" => { url: "https://chatgpt.com", input: 'textarea#prompt-textarea', response: '.markdown' },
    "gemini" => { url: "https://gemini.google.com", input: 'textarea', response: '.model-response' },
    "huggingchat" => { url: "https://huggingface.co/chat", input: 'textarea', response: '.prose' },
    "perplexity" => { url: "https://perplexity.ai", input: 'textarea', response: '.prose' }
  }

  def initialize(provider = "claude")
    @provider = provider
    @cfg = PROVIDERS[provider] || PROVIDERS["claude"]
    @browser = Ferrum::Browser.new(
      headless: true,
      timeout: 90,
      browser_path: find_browser,
      browser_options: STEALTH_OPTIONS.merge({ "no-sandbox": nil })
    )
    @browser.evaluate_on_new_document(STEALTH_JS)
    @page = @browser.create_page
    @page.go_to(@cfg[:url])
    wait_ready
  end

  def send(text)
    el = find(@cfg[:input]) or raise "input not found"
    el.focus; el.type(text); sleep 0.2; el.type(:Enter)
    wait_response
  end

  def screenshot = @page.screenshot(path: "/tmp/cli_screenshot.png") && "/tmp/cli_screenshot.png"

  def page_source = @page.body

  def quit = @browser&.quit

  private

  def find(selectors) = selectors.split(", ").each { |s| (el = @page.at_css(s) rescue nil) and return el }; nil

  def wait_ready = (deadline = Time.now + 30; until find(@cfg[:input]) or Time.now > deadline; sleep 0.5; end)

  def wait_response
    deadline, last, stable = Time.now + 90, "", 0

    loop do
      raise "timeout" if Time.now > deadline

      elements = @page.css(@cfg[:response]) rescue []

      if elements.any?
        current = elements.last.text.strip

        if current == last && !current.empty?
          # Strip provider prefixes (Model A/B:, Model :, Response:) from response text
          return current.sub(/^(Model [AB]?:?\s*|Response:?\s*)/i, "").strip if (stable += 1) >= 3
        else
          stable, last = 0, current
        end
      end

      sleep 1
    end
  end
end

# ============================================================================
# API CLIENT
# ============================================================================

class APIClient
  def initialize(tools = [])
    @client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
    @messages = []
    @tools = tools
    @model = ENV["CLAUDE_MODEL"] || "claude-sonnet-4-20250514"
    @pending_tool_calls = []
  end

  def send(text, auto_tools: false)
    @messages << { role: "user", content: text }
    call_api(auto_tools)
  end

  def process_tool_results(results)
    @messages << { role: "user", content: results }
    call_api(false)
  end

  def pending_tools? = @pending_tool_calls.any?

  def pending_tools = @pending_tool_calls

  # Undo the last exchange (removes last user message and assistant response)
  def undo_last_exchange
    return false if @messages.size < 2
    
    # Remove last two messages (user + assistant)
    @messages.pop(2)
    true
  end

  # Check if undo is available
  def can_undo? = @messages.size >= 2

  private

  def call_api(auto_tools)
    params = { model: @model, max_tokens: 8192, messages: @messages }
    params[:tools] = @tools.flat_map { |t| t.class.schema } if @tools.any?

    response = @client.messages(**params)
    content = response["content"]
    @messages << { role: "assistant", content: content }

    tool_blocks = content.select { |c| c["type"] == "tool_use" }

    if tool_blocks.any?
      @pending_tool_calls = tool_blocks
      return "[tool calls pending]" unless auto_tools
      execute_tools
    else
      @pending_tool_calls = []
      content.map { |c| c["text"] }.compact.join("\n")
    end
  end

  def execute_tools
    results = @pending_tool_calls.map do |tc|
      tool = @tools.find { |t| t.class.schema.any? { |s| s[:name] == tc["name"] } }
      result = tool ? tool.send(tc["name"], **tc["input"].transform_keys(&:to_sym)) : { error: "unknown" }
      { type: "tool_result", tool_use_id: tc["id"], content: JSON.generate(result) }
    end

    @pending_tool_calls = []
    process_tool_results(results)
  end
end

# ============================================================================
# TOOL DSL
# ============================================================================

module ToolDSL
  def self.extended(base) = base.instance_variable_set(:@schema, [])

  def tool(name, desc, props = {}, required = []) = @schema << { name: name.to_s, description: desc, input_schema: { type: "object", properties: props, required: required.map(&:to_s) } }

  def schema = @schema
end

# ============================================================================
# SHELL TOOL
# ============================================================================

class ShellTool
  extend ToolDSL

  tool :shell, "Execute shell command", { command: { type: "string", description: "command" } }, [:command]

  def shell(command:)
    if MASTER_CONFIG.banned?(command)
      banned_tool = MASTER_CONFIG.banned_tool(command)
      return { error: "blocked: #{banned_tool}", alternative: MASTER_CONFIG.suggest_alternative(banned_tool) }
    end

    return { error: "blocked: dangerous pattern" } if MASTER_CONFIG.dangerous?(command)

    shell_path = ["/usr/local/bin/zsh", "/bin/zsh"].find { |s| File.executable?(s) } || "/bin/sh"
    stdout, stderr, status = Open3.capture3(shell_path, "-c", command)
    { stdout: stdout[0..4000], stderr: stderr[0..1000], exit: status.exitstatus }
  rescue => e
    { error: e.message }
  end
end

# ============================================================================
# FILE TOOL
# ============================================================================

class FileTool
  extend ToolDSL

  tool :read_file, "Read file", { path: { type: "string" } }, [:path]
  tool :write_file, "Write file", { path: { type: "string" }, content: { type: "string" } }, [:path, :content]
  tool :list_dir, "List directory", { path: { type: "string" } }, [:path]

  def initialize(access_level = :sandbox)
    @access_level = access_level
    @allowed_paths = calculate_allowed_paths
  end

  def read_file(path:) = allowed?(path) && File.exist?(path) ? { content: File.read(path)[0..50000], size: File.size(path) } : { error: "access denied" }

  def write_file(path:, content:) = allowed?(path) ? (File.write(path, content); { ok: true }) : { error: "access denied" }

  def list_dir(path:)
    return { error: "access denied" } unless allowed?(path)

    entries = Dir.entries(path).reject { |e| e.start_with?(".") }.map { |e| full = File.join(path, e); { name: e, type: File.directory?(full) ? "dir" : "file" } }
    { entries: entries.sort_by { |e| [e[:type] == "dir" ? 0 : 1, e[:name]] } }
  rescue => e
    { error: e.message }
  end

  private

  def calculate_allowed_paths
    config = Convergence::ACCESS_LEVELS[@access_level]
    paths = config[:paths].is_a?(Proc) ? config[:paths].call : config[:paths]
    paths == :all ? :all : paths.compact
  end

  def allowed?(path)
    return true if @allowed_paths == :all
    @allowed_paths.any? { |a| File.expand_path(path).start_with?(File.expand_path(a)) }
  end
end

# ============================================================================
# LANGCHAIN TOOL
# ============================================================================

class LangChainTool
  extend ToolDSL

  tool :run_chain, "Run LangChain chain", { chain_json: { type: "string" } }, [:chain_json]
  tool :rag_search, "RAG search", { query: { type: "string" } }, [:query]

  def initialize = @llm = Langchain::LLM::Anthropic.new(api_key: ENV["ANTHROPIC_API_KEY"]) if ENV["ANTHROPIC_API_KEY"]

  def run_chain(chain_json:) = LANGCHAIN ? { result: Langchain::Chain.new(@llm).call(JSON.parse(chain_json)["inputs"]) } : { error: "langchainrb unavailable" } rescue { error: $!.message }

  def rag_search(query:) = { results: Langchain::Vectorsearch::Chroma.new.similarity_search(query, k: 3).map { |r| r[:text] } } rescue { error: "vectorstore unavailable" }
end

# ============================================================================
# RAG WITH RRF FUSION
# ============================================================================

class RAG
  attr_reader :stats

  def initialize
    @chunks = []
    @embeddings = {}
    @provider = detect_provider
    @stats = { chunks: 0, embeddings: 0, provider: @provider }
  end

  def ingest(path)
    return ingest_dir(path) if File.directory?(path)

    text = File.read(path) rescue nil
    return 0 unless text

    chunks = chunk_text(text, source: path)
    chunks.each { |c| vec = embed(c[:text]); @chunks << c; @embeddings[c[:id]] = vec if vec }
    
    update_stats
    chunks.size
  end

  def search(query, k: 5)
    qvec = embed(query)
    return keyword_search(query, k: k) unless qvec
    
    results = @chunks.map { |c| vec = @embeddings[c[:id]]; vec ? { chunk: c, score: cosine(qvec, vec) } : nil }.compact
    results.sort_by! { |s| -s[:score] }
    results.first(k)
  end

  # Add RRF (Reciprocal Rank Fusion) for multi-query search
  def search_with_rrf(query, k: 5)
    # Generate sub-queries for better coverage
    sub_queries = generate_sub_queries(query)
    
    # Search with each sub-query
    all_results = sub_queries.map { |sq| search(sq, k: k * 2) }
    
    # Apply RRF fusion
    rrf_scores = Hash.new(0.0)
    @chunk_cache ||= {}
    
    all_results.each do |results|
      results.each_with_index do |r, rank|
        rrf_scores[r[:chunk][:id]] += 1.0 / (60 + rank)  # RRF formula
        @chunk_cache[r[:chunk][:id]] = r[:chunk]
      end
    end
    
    # Sort by RRF score and return top k
    rrf_scores.sort_by { |_, score| -score }
              .first(k)
              .map { |id, score| { chunk: @chunk_cache[id], score: score } }
  end

  def augment(query, k: 3)
    results = search_with_rrf(query, k: k)
    return query if results.empty?
    
    context = results.map { |r| r[:chunk][:text] }.join("\n---\n")
    "Context:\n#{context}\n\nQuestion: #{query}"
  end

  private

  def detect_provider = ENV["OPENAI_API_KEY"] ? :openai : system("curl -s http://localhost:11434/api/tags > /dev/null 2>&1") ? :local : :none

  def embed(text) = case @provider; when :openai then embed_openai(text); when :local then embed_ollama(text); else nil; end

  def embed_openai(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV["OPENAI_API_KEY"]}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(model: "text-embedding-3-small", input: text[0..8000])
    
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    res.code == "200" ? JSON.parse(res.body).dig("data", 0, "embedding") : nil
  rescue => e
    nil
  end

  def embed_ollama(text)
    uri = URI("http://localhost:11434/api/embeddings")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(model: "nomic-embed-text", prompt: text[0..8000])
    
    res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
    res.code == "200" ? JSON.parse(res.body)["embedding"] : nil
  rescue => e
    nil
  end

  def keyword_search(query, k: 5)
    query_terms = query.downcase.split(/\W+/).reject { |t| t.length < 3 }
    return [] if query_terms.empty?

    results = @chunks.map do |chunk|
      text_lower = chunk[:text].downcase
      score = query_terms.sum { |term| count = text_lower.scan(/\b#{Regexp.escape(term)}\b/).size; count > 0 ? Math.log(1 + count) : 0 }
      { chunk: chunk, score: score }
    end

    results.select! { |r| r[:score] > 0 }
    results.sort_by! { |r| -r[:score] }
    results.first(k)
  end

  def chunk_text(text, source: nil, size: 500)
    text.split(/\n{2,}/).each_with_index.map do |p, i|
      next unless p.strip.size > 0
      { id: "#{i}_#{Digest::MD5.hexdigest(p)[0..7]}", text: p.strip, source: source, idx: i }
    end.compact
  end

  def cosine(a, b) = a.zip(b).sum { |x, y| x * y } / (Math.sqrt(a.sum { |x| x*x }) * Math.sqrt(b.sum { |y| y*y })) rescue 0

  def ingest_dir(path) = Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) && %w[.txt .md .rb .yml .json .html].include?(File.extname(f).downcase) }.sum { |f| ingest(f) }

  def generate_sub_queries(query)
    # Simple sub-query generation
    [
      query,
      query.split.first(3).join(" "),  # First 3 words
      query.gsub(/\?$/, "")             # Without question mark
    ].uniq
  end

  def update_stats
    @stats[:chunks] = @chunks.size
    @stats[:embeddings] = @embeddings.size
    @stats[:provider] = @provider
  end
end

# ============================================================================
# CLI WITH NN/G USABILITY IMPROVEMENTS
# ============================================================================

class CLI
  # H6: Recognition - Command aliases
  ALIASES = {
    "/h" => "/help", "/?" => "/help",
    "/p" => "/provider",
    "/s" => "/search",
    "/u" => "/undo",
    "/q" => "exit",
    "/l" => "/level",
    "/r" => "/rag",
    "/t" => "/tools"
  }.freeze

  # H10: Contextual help
  COMMAND_HELP = {
    "provider" => <<~HELP,
      /provider [name] - Switch webchat provider
      
      Available providers:
        claude     - Claude.ai (recommended)
        grok       - Grok on X
        deepseek   - DeepSeek Chat
        chatgpt    - ChatGPT
        gemini     - Google Gemini
        huggingchat - HuggingFace Chat
        perplexity - Perplexity.ai
        
      Example: /provider deepseek
    HELP
    "level" => <<~HELP,
      /level [sandbox|user|admin] - Set access level
      
      Levels:
        sandbox - Project dir + /tmp only, confirms all writes
        user    - Home dir access, no root
        admin   - Full access via doas, confirms destructive ops
        
      Current level shown in prompt: [mode|S/U/A]
    HELP
    "rag" => <<~HELP,
      /rag - Toggle RAG (Retrieval Augmented Generation)
      
      When enabled, queries are augmented with relevant
      context from your knowledge base.
      
      Related commands:
        /ingest PATH  - Add files to knowledge base
        /search QUERY - Search knowledge base
        /rag-stats    - Show RAG statistics
    HELP
    "undo" => <<~HELP,
      /undo - Undo last exchange
      
      Removes the last question and answer from the
      conversation history. Only works in API mode.
    HELP
  }.freeze

  HELP = <<~H

    /help [cmd]    show commands (or details for specific command)
    /mode          show current mode
    /level [name]  show/set access level (sandbox/user/admin)
    /provider X    switch webchat provider
    /tools         list available tools (API mode only)
    /yes           approve pending tool calls
    /no            reject pending tool calls
    /undo          undo last exchange
    /ingest PATH   add files to knowledge base
    /search QUERY  search knowledge base
    /rag           toggle RAG augmentation
    /rag-stats     show RAG statistics
    /clear         clear conversation
    exit           quit

    Aliases: /h /p /s /u /q /l /r /t

  H

  def initialize
    UI.init
    @mode = detect_mode
    @provider = "claude"
    @client = nil
    @access_level = :user  # Default to user level
    @tools = nil
    @rag = RAG.new
    @rag_enabled = false
    @history = []  # For undo
  end

  def run
    boot_sequence
    UI.banner(mode_label, @access_level)
    
    # Apply security sandbox based on access level
    apply_security_sandbox(@access_level)
    
    connect

    loop do
      input = UI.prompt

      break if input.nil? || input =~ /^(exit|quit|bye)$/i

      next if input.strip.empty?

      input.start_with?("/") ? command(input) : message(input)
    end

    UI.status("session ended")
  ensure
    @client.quit if @client.is_a?(WebChat)
  end

  private

  def boot_sequence
    puts "Welcome to **cli.rb** v∞.16.0"
    puts "RAG: #{@rag.stats[:chunks]} chunks, provider: #{@rag.stats[:provider]}"
    puts "Access: #{Convergence::ACCESS_LEVELS[@access_level][:description]}"
    puts "<openbsd-inspired boot sequence>"
    puts "cpu0: OpenBSD-like pledge+unveil enabled" if PLEDGE_AVAILABLE
    puts "master.yml v#{MASTER_CONFIG.version} loaded"
    puts "backend: #{mode_label}"
    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}"
    puts "..."
    puts "<begin chat>"
  end

  def detect_mode = ANTHROPIC && ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-") ? :api : FERRUM ? :webchat : :none

  def mode_label = case @mode; when :api then "api (#{ENV["CLAUDE_MODEL"] || "claude-sonnet-4-20250514"})"; when :webchat then "webchat/#{@provider}"; else "unavailable"; end

  # H1: Visibility - Enhanced prompt with status
  def prompt_with_status
    mode_indicator = case @mode
                     when :api then "api"
                     when :webchat then "web/#{@provider}"
                     else "?"
                     end
    
    level_char = @access_level.to_s[0].upcase  # S/U/A
    # Use ASCII fallback for better terminal compatibility
    rag_indicator = @rag_enabled ? "*RAG" : ""
    tokens = @total_tokens.to_i > 0 ? " #{@total_tokens}t" : ""
    
    "[#{mode_indicator}#{tokens}#{rag_indicator}|#{level_char}] > "
  end

  def connect
    # Initialize tools with current access level
    @tools = [ShellTool.new, FileTool.new(@access_level), LangChainTool.new]

    case @mode
    when :api then @client = APIClient.new(@tools); UI.status("connected to API")
    when :webchat then UI.thinking("connecting to #{@provider}") { @client = WebChat.new(@provider) }; UI.status("connected")
    else UI.error("no backend"); exit 1
    end
  end

  # Resolve command aliases
  def resolve_command(input)
    parts = input.split(/\s+/, 2)
    cmd = ALIASES[parts[0]] || parts[0]
    [cmd, parts[1]]
  end

  def command(input)
    cmd, arg = resolve_command(input)

    case cmd
    when "/help" then command_help(arg)
    when "/mode" then UI.status(mode_label)
    when "/level" then command_level(arg)
    when "/clear" then system("clear") || system("cls")
    when "/tools" then @mode == :api ? @tools.each { |t| t.class.schema.each { |s| UI.puts("#{s[:name]}: #{s[:description]}") } } : UI.status("tools only in API mode")
    when "/yes" then approve_tools(true)
    when "/no" then approve_tools(false)
    when "/undo" then command_undo
    when "/provider" then switch_provider(arg)
    when "/ingest" then rag_ingest(arg)
    when "/search" then rag_search(arg)
    when "/rag" then toggle_rag
    when "/rag-stats" then UI.puts(@rag.stats.map { |k, v| "#{k}: #{v}" }.join(", "))
    when "/screenshot" then UI.status("screenshot: #{@client.screenshot}") if @client.is_a?(WebChat)
    when "/page-source" then UI.puts(@client.page_source[0..5000]) if @client.is_a?(WebChat)
    else UI.error("unknown command: #{cmd}")
    end
  end

  # H10: Contextual help
  def command_help(arg = nil)
    if arg && COMMAND_HELP[arg]
      UI.puts(COMMAND_HELP[arg])
    else
      UI.puts(HELP)
      UI.puts("\nTip: /help <command> for details (e.g., /help provider)")
    end
  end

  # Access level management
  def command_level(arg = nil)
    unless arg
      UI.status("current access level: #{@access_level} (#{Convergence::ACCESS_LEVELS[@access_level][:description]})")
      UI.puts("\nAvailable levels:")
      Convergence::ACCESS_LEVELS.each do |level, config|
        UI.puts("  #{level}: #{config[:description]}")
      end
      return
    end

    new_level = arg.to_sym
    unless Convergence::ACCESS_LEVELS.key?(new_level)
      UI.error("unknown level: #{arg}")
      return
    end

    # Confirm if switching to admin
    if new_level == :admin && !UI.confirm("Switch to admin level? This grants full system access via doas.")
      UI.status("cancelled")
      return
    end

    @access_level = new_level
    
    # Reinitialize tools with new access level
    @tools = [ShellTool.new, FileTool.new(@access_level), LangChainTool.new]
    if @mode == :api && @client
      @client = APIClient.new(@tools)
    end
    
    UI.status("access level changed to: #{@access_level}")
  end

  # H3: Undo last exchange
  def command_undo
    if @mode != :api || !@client
      UI.error("undo only available in API mode")
      return
    end

    unless @client.can_undo?
      UI.error("nothing to undo")
      return
    end

    # Use the proper encapsulated method
    if @client.undo_last_exchange
      UI.status("undid last exchange")
    else
      UI.error("failed to undo")
    end
  end

  def message(text)
    text = @rag.augment(text) if @rag_enabled && @rag.stats[:chunks] > 0

    response = UI.thinking { @client.send(text) }
    UI.response(response)

    show_pending_tools if @mode == :api && @client.pending_tools?
  rescue => e
    UI.error(e.message)
    Log.error(e.message, backtrace: e.backtrace.first(3))
  end

  def show_pending_tools = @client.pending_tools.each { |tc| UI.puts("tool: #{tc["name"]}"); UI.puts("input: #{tc["input"].to_json}") }; UI.status("approve with /yes or /no")

  def approve_tools(approved)
    return UI.status("no pending tools") unless @mode == :api && @client.pending_tools?

    if approved
      response = UI.thinking("executing") { @client.process_tool_results(execute_pending) }
      UI.response(response)
    else
      UI.status("tools rejected")
    end
  end

  def execute_pending = @client.pending_tools.map { |tc| tool = @tools.find { |t| t.class.schema.any? { |s| s[:name] == tc["name"] } }; result = tool ? tool.send(tc["name"], **tc["input"].transform_keys(&:to_sym)) : { error: "unknown" }; { type: "tool_result", tool_use_id: tc["id"], content: JSON.generate(result) } }

  def switch_provider(name)
    unless name
      UI.puts("providers: #{WebChat::PROVIDERS.keys.join(", ")}")
      return
    end

    unless WebChat::PROVIDERS[name]
      UI.error("unknown provider: #{name}")
      return
    end

    return UI.status("provider switching only in webchat mode") unless @mode == :webchat

    @client&.quit
    @provider = name
    UI.thinking("connecting to #{name}") { @client = WebChat.new(name) }
    UI.status("switched to #{name}")
  end

  def rag_ingest(path)
    unless path
      UI.error("usage: /ingest PATH")
      return
    end
    
    count = UI.thinking("ingesting") { @rag.ingest(File.expand_path(path)) }
    UI.status("added #{count} chunks")
  end

  def rag_search(query)
    unless query
      UI.error("usage: /search QUERY")
      return
    end
    
    results = @rag.search_with_rrf(query)
    
    if results.empty?
      UI.status("no results")
    else
      results.each_with_index do |r, i|
        UI.puts("#{i + 1}. [#{r[:score].round(3)}] #{r[:chunk][:source]}")
        UI.puts("   #{r[:chunk][:text][0..150]}...")
      end
    end
  end

  def toggle_rag
    @rag_enabled = !@rag_enabled
    UI.status("RAG #{@rag_enabled ? "enabled" : "disabled"}")
    UI.status("knowledge base empty, use /ingest first") if @rag_enabled && @rag.stats[:chunks] == 0
  end
end

# ============================================================================
# MAIN
# ============================================================================

CLI.new.run if __FILE__ == $0
