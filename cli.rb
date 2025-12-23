#!/usr/bin/env ruby
# frozen_string_literal: true
# CONVERGENCE CLI v3.0
# Self-bootstrapping AI assistant
#
# First run: auto-installs gems, checks for browser
# Just: chmod +x cli.rb && ./cli.rb
require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "digest"
# OpenBSD security hardening
PLEDGE_AVAILABLE = if RUBY_PLATFORM =~ /openbsd/
  begin
    require "pledge"
    Pledge.pledge("stdio rpath wpath cpath inet dns proc exec prot_exec", nil) rescue nil
    Pledge.unveil(ENV["HOME"], "rwc") rescue nil
    Pledge.unveil("/tmp", "rwc") rescue nil
    Pledge.unveil("/usr/local", "rx") rescue nil
    Pledge.unveil("/etc/ssl", "r") rescue nil
    Pledge.unveil(nil, nil) rescue nil
    true
  rescue LoadError
    false
  end
else
  false
end
# First run detection
FIRST_RUN = !File.exist?(File.expand_path("~/.convergence_installed"))
warn "convergence v3.0 - first run setup
" if FIRST_RUN
# Self-bootstrap missing gems
def ensure_gem(name, require_as = nil)
  require(require_as || name)
  true
rescue LoadError
  return false if ENV["NO_AUTO_INSTALL"]
  warn "  installing #{name}..." if FIRST_RUN
  result = system("gem install #{name} --no-document --quiet 2>/dev/null")
  return false unless result
  Gem.clear_paths
  begin
    require(require_as || name)
    true
  rescue LoadError
    false
  end
end
# Master.yml configuration loader
class MasterConfig
  attr_reader :config, :version, :banned_tools
  SEARCH_PATHS = [
    File.expand_path("~/pub/master.yml"),
    File.join(Dir.pwd, "master.yml"),
    File.join(File.dirname(__FILE__), "master.yml")
  ].freeze
  # Dangerous patterns hard-coded for safety
  DANGEROUS_PATTERNS = [
    "rm -rf /",
    "rm -rf /*",
    "rm -rf ~",
    "rm -rf $HOME",
    "> /etc/passwd",
    "> /etc/shadow",
    "> /etc/sudoers",
    "| sh",
    "| bash"
  ].freeze
  def initialize
    @config = load_config
    @version = @config.dig("meta", "version")
    @banned_tools = @config.dig("constraints", "banned_tools") || []
    # Pre-compile banned tools regex for performance
    @banned_regex = if @banned_tools.any?
      Regexp.new('\b(' + @banned_tools.map { |t| Regexp.escape(t) }.join('|') + ')\b')
    else
      /(?!)/  # Regex that never matches
    end
    validate_version
  end
  def load_config
    path = SEARCH_PATHS.find { |p| File.exist?(p) }
    if path
      YAML.safe_load_file(path, aliases: false)
    else
      warn "master.yml not found in search paths, using defaults"
      default_config
    end
  rescue => e
    warn "error loading master.yml: #{e.message}, using defaults"
    default_config
  end
  def validate_version
    return unless @version
    # Parse version with fallback for non-standard formats
    parts = @version.to_s.split(".").map do |p|
      p.match?(/Ad+z/) ? p.to_i : 0
    end
    major = parts[0] || 0
    if major < 76
      warn "master.yml version #{@version} < 76.x, may have compatibility issues"
    elsif major >= 77
      warn "master.yml version #{@version} >= 77.x, compatibility uncertain"
    end
  rescue => e
    warn "unable to validate master.yml version: #{e.message}"
  end
  def banned?(command)
    command =~ @banned_regex
  end
  def banned_tool(command)
    @banned_tools.find { |t| command =~ /#{Regexp.escape(t)}/ }
  end
  def dangerous?(command)
    DANGEROUS_PATTERNS.any? { |pattern| command.include?(pattern) }
  end
  def suggest_alternative(tool)
    # Get zsh replacements from config if available
    zsh_replaces = @config.dig("stack", "zsh", "replaces") || {}
    case tool
    when "sed"
      zsh_replaces["sed"] || "use zsh: ${var//old/new}"
    when "awk"
      zsh_replaces["awk"] || "use zsh: ${${(s: :)line}[2]}"
    when "bash"
      "use zsh with pure zsh patterns"
    when "wc"
      zsh_replaces["wc"] || "use zsh: ${#lines}"
    when "head"
      zsh_replaces["head"] || "use zsh: ${lines[1,10]}"
    when "tail"
      zsh_replaces["tail"] || "use zsh: ${lines[-5,-1]}"
    when "python"
      "use ruby instead"
    when "sudo"
      "use doas on OpenBSD"
    else
      "use zsh parameter expansion or ruby"
    end
  end
  private
  def default_config
    {
      "meta" => { "version" => "76.0" },
      "constraints" => {
        "banned_tools" => %w[python bash sed awk wc head tail find sudo],
        "allowed_tools" => %w[ruby zsh git grep cat sort]
      }
    }
  end
end
# Load master.yml at startup
MASTER_CONFIG = MasterConfig.new
warn "master.yml v#{MASTER_CONFIG.version || 'unknown'} loaded
" if FIRST_RUN
# Check for browser
def find_browser
  paths = %w[
    /usr/bin/chromium
    /usr/bin/chromium-browser
    /usr/bin/google-chrome
    /usr/bin/google-chrome-stable
    /usr/local/bin/chrome
    /usr/local/bin/chromium
    /usr/local/chrome/chrome
  ]
  # Platform-specific paths
  case RUBY_PLATFORM
  when /darwin/
    paths += [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium"
    ]
  when /openbsd/
    paths += ["/usr/local/bin/chrome", "/usr/local/bin/iridium"]
  end
  paths.find { |p| File.executable?(p) }
end
def check_browser
  return true if find_browser
  warn "
no browser found for webchat mode"
  warn "install chromium:"
  case RUBY_PLATFORM
  when /darwin/ then warn "  brew install chromium"
  when /linux/
    if File.exist?("/etc/debian_version")
      warn "  sudo apt install chromium-browser"
    elsif File.exist?("/etc/redhat-release")
      warn "  sudo dnf install chromium"
    elsif File.exist?("/etc/arch-release")
      warn "  sudo pacman -S chromium"
    else
      warn "  install chromium via your package manager"
    end
  when /openbsd/ then warn "  doas pkg_add chromium"
  when /freebsd/ then warn "  sudo pkg install chromium"
  end
  warn "
or set ANTHROPIC_API_KEY to use API mode instead
"
  false
end
# Bootstrap gems
TTY = ensure_gem("tty-prompt") && ensure_gem("tty-spinner") && ensure_gem("pastel")
FERRUM = ensure_gem("ferrum")
ANTHROPIC = ensure_gem("anthropic")
# Mark first run complete
if FIRST_RUN
  FileUtils.touch(File.expand_path("~/.convergence_installed"))
  warn "setup complete
"
end
# Validate we have a working backend
unless ANTHROPIC && ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-")
  unless FERRUM && check_browser
    warn "error: no backend available"
    warn "either:"
    warn "  1. install chromium for free webchat mode"
    warn "  2. set ANTHROPIC_API_KEY for API mode"
    exit 1
  end
end
# Logging
module Log
  def self.out(level, msg, **ctx)
    return if level == :debug && !ENV["DEBUG"]
    entry = { t: Time.now.strftime("%H:%M:%S"), l: level, m: msg }.merge(ctx)
    $stderr.puts JSON.generate(entry) if ENV["LOG_JSON"]
  end
  def self.info(msg, **ctx) = out(:info, msg, **ctx)
  def self.warn(msg, **ctx) = out(:warn, msg, **ctx)
  def self.error(msg, **ctx) = out(:error, msg, **ctx)
  def self.debug(msg, **ctx) = out(:debug, msg, **ctx)
end
# UI - minimal, no decorations, follows NN heuristics
module UI
  extend self
  def init
    @pastel = TTY ? Pastel.new : nil
    @prompt = TTY ? TTY::Prompt.new : nil
  end
  def puts(text = "") = Kernel.puts(text)
  def c(style, text) = @pastel ? @pastel.send(style, text) : text
  def banner(mode)
    puts "convergence v3.0"
    puts "mode: #{mode}"
    puts "master.yml: v#{MASTER_CONFIG.version}" if MASTER_CONFIG.version
    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}" if RUBY_PLATFORM =~ /openbsd/
    puts "type /help for commands
"
  end
  def prompt
    TTY ? @prompt.ask(">", required: false)&.strip : (print "> "; $stdin.gets&.chomp)
  end
  def thinking(msg = "thinking")
    if TTY
      s = TTY::Spinner.new("#{msg}...", format: :dots)
      s.auto_spin
      yield.tap { s.success("") }
    else
      print "#{msg}... "
      yield.tap { puts "done" }
    end
  rescue => e
    s&.error("") if TTY
    raise
  end
  def response(text) = puts("
#{text}
")
  def error(msg) = puts(c(:red, "error: #{msg}"))
  def status(msg) = puts(c(:dim, msg))
  def confirm(msg) = TTY ? @prompt.yes?(msg) : (print "#{msg} [y/N] "; $stdin.gets&.strip&.downcase == "y")
end
# Webchat - browser automation for free AI access
class WebChat
  PROVIDERS = {
    "lmsys" => { url: "https://chat.lmsys.org", input: 'textarea[placeholder*="Type"], textarea[data-testid="textbox"]', response: '.message.bot, .chatbot .bot' },
    "chatgpt" => { url: "https://chatgpt.com", input: 'textarea#prompt-textarea', response: '.markdown, [data-message-author-role="assistant"]' },
    "claude" => { url: "https://claude.ai", input: 'div[contenteditable="true"]', response: '.font-claude-message' },
    "deepseek" => { url: "https://chat.deepseek.com", input: 'textarea#chat-input', response: '.markdown-body, .ds-markdown' },
    "gemini" => { url: "https://gemini.google.com", input: 'rich-textarea, textarea', response: '.model-response' },
    "grok" => { url: "https://grok.x.ai", input: 'textarea[placeholder*="Ask"]', response: '[data-testid="message-content"]' },
    "glm" => { url: "https://chatglm.cn", input: 'textarea.chat-input', response: '.message-content' },
    "huggingchat" => { url: "https://huggingface.co/chat", input: 'textarea[placeholder*="Ask"]', response: '.prose' },
    "perplexity" => { url: "https://perplexity.ai", input: 'textarea', response: '.prose' },
    "copilot" => { url: "https://copilot.microsoft.com", input: 'textarea', response: '.response-message' },
    "poe" => { url: "https://poe.com", input: 'textarea', response: '.Message_botMessageBubble' }
  }
  attr_reader :provider
  def initialize(provider = "lmsys")
    @provider = provider
    @cfg = PROVIDERS[provider] || PROVIDERS["lmsys"]
    browser_path = find_browser
    @browser = Ferrum::Browser.new(
      headless: true,
      timeout: 90,
      process_timeout: 90,
      browser_path: browser_path,
      browser_options: { "no-sandbox": nil, "disable-gpu": nil, "disable-dev-shm-usage": nil }
    )
    @page = @browser.create_page
    @page.go_to(@cfg[:url])
    wait_ready
  end
  def send(text)
    el = find(@cfg[:input]) or raise "input not found"
    el.focus
    el.type(text)
    sleep 0.2
    el.type(:Enter)
    wait_response
  end
  def quit = @browser&.quit
  private
  def find(selectors)
    selectors.split(", ").each { |s| (el = @page.at_css(s) rescue nil) and return el }
    nil
  end
  def wait_ready(timeout = 30)
    deadline = Time.now + timeout
    until find(@cfg[:input]) or Time.now > deadline
      sleep 0.5
    end
  end
  def wait_response(timeout = 90)
    deadline, last, stable = Time.now + timeout, "", 0
    loop do
      raise "timeout waiting for response" if Time.now > deadline
      elements = @page.css(@cfg[:response]) rescue []
      if elements.any?
        current = elements.last.text.strip
        if current == last && !current.empty?
          return current.sub(/^(Model [AB]?:?s*|Response:?s*)/i, "").strip if (stable += 1) >= 3
        else
          stable, last = 0, current
        end
      end
      sleep 1
    end
  end
end
# API Client - Anthropic Claude
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
      return "[tool calls pending - approve with /yes or /no]" unless auto_tools
      execute_tools
    else
      @pending_tool_calls = []
      content.map { |c| c["text"] }.compact.join("
")
    end
  end
  def execute_tools
    results = @pending_tool_calls.map do |tc|
      tool = @tools.find { |t| t.class.schema.any? { |s| s[:name] == tc["name"] } }
      result = tool ? tool.send(tc["name"], **tc["input"].transform_keys(&:to_sym)) : { error: "unknown tool" }
      { type: "tool_result", tool_use_id: tc["id"], content: JSON.generate(result) }
    end
    @pending_tool_calls = []
    process_tool_results(results)
  end
end
# Tools
module ToolDSL
  def self.extended(base)
    base.instance_variable_set(:@schema, [])
  end
  def tool(name, desc, props = {}, required = [])
    @schema << { name: name.to_s, description: desc,
      input_schema: { type: "object", properties: props, required: required.map(&:to_s) } }
  end
  def schema = @schema
end
class ShellTool
  extend ToolDSL
  tool :shell, "Execute shell command", { command: { type: "string", description: "command" } }, [:command]
  def shell(command:)
    # Check banned tools
    if MASTER_CONFIG.banned?(command)
      banned_tool = MASTER_CONFIG.banned_tool(command)
      alternative = MASTER_CONFIG.suggest_alternative(banned_tool)
      return { error: "blocked: #{banned_tool} (master.yml banned)", alternative: alternative }
    end
    # Check dangerous patterns
    if MASTER_CONFIG.dangerous?(command)
      return { error: "blocked: dangerous pattern detected (master.yml)" }
    end
    # Execute with zsh preference
    shell_path = ["/usr/local/bin/zsh", "/bin/zsh", "/bin/ksh", ENV["SHELL"]].find { |s| s && File.executable?(s) } || "/bin/sh"
    stdout, stderr, status = Open3.capture3(shell_path, "-c", command)
    { stdout: stdout[0..4000], stderr: stderr[0..1000], exit: status.exitstatus }
  rescue => e
    { error: e.message }
  end
end
class FileTool
  extend ToolDSL
  tool :read_file, "Read file", { path: { type: "string" } }, [:path]
  tool :write_file, "Write file", { path: { type: "string" }, content: { type: "string" } }, [:path, :content]
  tool :list_dir, "List directory", { path: { type: "string" } }, [:path]
  ALLOWED = [ENV["HOME"], Dir.pwd, "/tmp"].compact
  def read_file(path:)
    return { error: "outside allowed paths" } unless allowed?(path)
    return { error: "not found" } unless File.exist?(path)
    { content: File.read(path)[0..50000], size: File.size(path) }
  rescue => e
    { error: e.message }
  end
  def write_file(path:, content:)
    return { error: "outside allowed paths" } unless allowed?(path)
    File.write(path, content)
    { ok: true, size: content.bytesize }
  rescue => e
    { error: e.message }
  end
  def list_dir(path:)
    return { error: "outside allowed paths" } unless allowed?(path)
    entries = Dir.entries(path).reject { |e| e.start_with?(".") }.map do |e|
      full = File.join(path, e)
      { name: e, type: File.directory?(full) ? "dir" : "file", size: File.size?(full) }
    end
    { entries: entries.sort_by { |e| [e[:type] == "dir" ? 0 : 1, e[:name]] } }
  rescue => e
    { error: e.message }
  end
  private
  def allowed?(path)
    expanded = File.expand_path(path)
    ALLOWED.any? { |a| expanded.start_with?(File.expand_path(a)) }
  end
end
# RAG - Retrieval Augmented Generation
class RAG
  def initialize
    @chunks = []
    @embeddings = {}
    @provider = detect_provider
  end
  def ingest(path)
    return ingest_dir(path) if File.directory?(path)
    return 0 unless File.file?(path)
    text = File.read(path) rescue nil
    return 0 unless text
    chunks = chunk_text(text, source: path)
    chunks.each do |chunk|
      vec = embed(chunk[:text])
      next unless vec
      @chunks << chunk
      @embeddings[chunk[:id]] = vec
    end
    chunks.size
  end
  def search(query, k: 5)
    return [] if @chunks.empty?
    qvec = embed(query)
    return [] unless qvec
    scored = @chunks.map do |c|
      vec = @embeddings[c[:id]]
      next unless vec
      { chunk: c, score: cosine(qvec, vec) }
    end.compact
    scored.sort_by { |s| -s[:score] }.first(k)
  end
  def augment(query, k: 3)
    results = search(query, k: k)
    return query if results.empty?
    context = results.map { |r| r[:chunk][:text] }.join("
")
    "Context:
#{context}
Question: #{query}"
  end
  def stats = { chunks: @chunks.size, provider: @provider }
  def clear = (@chunks = []; @embeddings = {})
  def enabled? = @provider != :none
  private
  def detect_provider
    return :openai if ENV["OPENAI_API_KEY"]
    return :local if system("curl -s http://localhost:11434/api/tags > /dev/null 2>&1")
    :none
  end
  def embed(text)
    case @provider
    when :openai then embed_openai(text)
    when :local then embed_ollama(text)
    else nil
    end
  end
  def embed_openai(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV["OPENAI_API_KEY"]}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(model: "text-embedding-3-small", input: text)
    res = http.request(req)
    return nil unless res.code == "200"
    JSON.parse(res.body).dig("data", 0, "embedding")
  rescue
    nil
  end
  def embed_ollama(text)
    uri = URI("http://localhost:11434/api/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(model: "nomic-embed-text", prompt: text)
    res = http.request(req)
    return nil unless res.code == "200"
    JSON.parse(res.body)["embedding"]
  rescue
    nil
  end
  def chunk_text(text, source: nil, size: 500)
    paragraphs = text.split(/
{2,}/)
    chunks, current, idx = [], "", 0
    paragraphs.each do |p|
      p = p.strip
      next if p.empty?
      if current.length + p.length < size
        current += (current.empty? ? "" : "
") + p
      else
        chunks << make_chunk(current, source, idx) unless current.empty?
        idx += 1
        current = p
      end
    end
    chunks << make_chunk(current, source, idx) unless current.empty?
    chunks
  end
  def make_chunk(text, source, idx)
    { id: "#{idx}_#{Digest::MD5.hexdigest(text)[0..7]}", text: text, source: source, idx: idx }
  end
  def cosine(a, b)
    return 0 unless a&.size == b&.size
    dot = a.zip(b).sum { |x, y| x * y }
    mag_a = Math.sqrt(a.sum { |x| x * x })
    mag_b = Math.sqrt(b.sum { |x| x * x })
    mag_a.zero? || mag_b.zero? ? 0 : dot / (mag_a * mag_b)
  end
  def ingest_dir(path)
    count = 0
    Dir.glob(File.join(path, "**", "*")).each do |f|
      next unless File.file?(f)
      next unless %w[.txt .md .rb .yml .json .html].include?(File.extname(f).downcase)
      count += ingest(f)
    end
    count
  end
end
# Main CLI
class CLI
  HELP = <<~H
    /help          show commands
    /mode          show current mode
    /provider X    switch webchat provider (lmsys, chatgpt, deepseek, claude, gemini, grok, glm, huggingchat, perplexity, copilot, poe)
    /tools         list available tools (API mode only)
    /yes           approve pending tool calls
    /no            reject pending tool calls
    /ingest PATH   add files to knowledge base
    /search QUERY  search knowledge base
    /rag           toggle RAG augmentation
    /rag-stats     show RAG statistics
    /clear         clear conversation
    exit           quit
  H
  def initialize
    UI.init
    @mode = detect_mode
    @provider = "lmsys"
    @client = nil
    @tools = [ShellTool.new, FileTool.new]
    @rag = RAG.new
    @rag_enabled = false
  end
  def run
    UI.banner(mode_label)
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
  def detect_mode
    return :api if ANTHROPIC && ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-")
    return :webchat if FERRUM
    :none
  end
  def mode_label
    case @mode
    when :api then "api (#{ENV["CLAUDE_MODEL"] || "claude-sonnet-4-20250514"})"
    when :webchat then "webchat/#{@provider}"
    else "unavailable"
    end
  end
  def connect
    case @mode
    when :api
      @client = APIClient.new(@tools)
      UI.status("connected to API")
    when :webchat
      UI.thinking("connecting to #{@provider}") { @client = WebChat.new(@provider) }
      UI.status("connected, responses may be slow")
    else
      UI.error("no backend - install ferrum gem or set ANTHROPIC_API_KEY")
      exit 1
    end
  end
  def command(input)
    parts = input.split(/s+/, 2)
    cmd, arg = parts[0], parts[1]
    case cmd
    when "/help" then UI.puts(HELP)
    when "/mode" then UI.status(mode_label)
    when "/clear" then system("clear") || system("cls")
    when "/tools"
      if @mode == :api
        @tools.each { |t| t.class.schema.each { |s| UI.puts("#{s[:name]}: #{s[:description]}") } }
      else
        UI.status("tools only available in API mode")
      end
    when "/yes" then approve_tools(true)
    when "/no" then approve_tools(false)
    when "/provider" then switch_provider(arg)
    when "/ingest" then rag_ingest(arg)
    when "/search" then rag_search(arg)
    when "/rag" then toggle_rag
    when "/rag-stats" then UI.puts(@rag.stats.map { |k, v| "#{k}: #{v}" }.join(", "))
    else UI.error("unknown command, try /help")
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
  def show_pending_tools
    @client.pending_tools.each do |tc|
      UI.puts("tool: #{tc["name"]}")
      UI.puts("input: #{tc["input"].to_json}")
    end
    UI.status("approve with /yes or reject with /no")
  end
  def approve_tools(approved)
    return UI.status("no pending tools") unless @mode == :api && @client.pending_tools?
    if approved
      response = UI.thinking("executing") { @client.process_tool_results(execute_pending) }
      UI.response(response)
    else
      UI.status("tools rejected")
    end
  end
  def execute_pending
    @client.pending_tools.map do |tc|
      tool = @tools.find { |t| t.class.schema.any? { |s| s[:name] == tc["name"] } }
      result = tool ? tool.send(tc["name"], **tc["input"].transform_keys(&:to_sym)) : { error: "unknown" }
      { type: "tool_result", tool_use_id: tc["id"], content: JSON.generate(result) }
    end
  end
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
    return UI.error("usage: /ingest PATH") unless path
    return UI.error("embeddings not available - set OPENAI_API_KEY or run ollama") unless @rag.enabled?
    expanded = File.expand_path(path)
    count = UI.thinking("ingesting") { @rag.ingest(expanded) }
    UI.status("added #{count} chunks")
  end
  def rag_search(query)
    return UI.error("usage: /search QUERY") unless query
    results = @rag.search(query, k: 5)
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
    UI.status("RAG augmentation #{@rag_enabled ? "enabled" : "disabled"}")
    UI.status("knowledge base empty, use /ingest first") if @rag_enabled && @rag.stats[:chunks] == 0
  end
end
CLI.new.run if __FILE__ == $0
