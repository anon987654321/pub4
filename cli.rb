#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI v∞.15.2 — Multi-LLM, LangChain, OpenBSD, Zsh/Starship Inspired

# Self-installs gems (--user-install), FREE webchat (Ferrum), API (Anthropic), RAG, chains, OpenBSD tools.

# Zsh/Starship: Plugin ecosystem, customizable themes, shell expansions.

require "json"
require "yaml"

require "net/http"

require "uri"

require "fileutils"

require "open3"

require "timeout"

require "digest"

require "io/console"

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

class MasterConfig
  attr_reader :version, :banned_tools

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

    "| bash"

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
    # Use match to capture the actual matched tool from the regex groups
    match = command.match(@banned_regex)
    match ? match[1] : nil
  end

  def dangerous?(command) = DANGEROUS_PATTERNS.any? { |p| command.include?(p) }

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

  def default_config = { "meta" => { "version" => "∞.15.2" }, "constraints" => { "banned_tools" => %w[python bash sed awk wc head tail find sudo] } }

end

MASTER_CONFIG = MasterConfig.new
def find_browser = %w[/usr/bin/chromium /usr/bin/google-chrome /usr/local/bin/chrome].find { |p| File.executable?(p) }
def check_browser
  return true if find_browser

  warn "no browser - install chromium or set ANTHROPIC_API_KEY"

  false

end

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

module Log
  def self.info(msg, **ctx) = $stderr.puts JSON.generate({ t: Time.now.strftime("%H:%M:%S"), l: :info, m: msg }.merge(ctx)) if ENV["LOG_JSON"]

  def self.warn(msg, **ctx) = $stderr.puts JSON.generate({ t: Time.now.strftime("%H:%M:%S"), l: :warn, m: msg }.merge(ctx)) if ENV["LOG_JSON"]

end

module UI
  extend self

  def init = (@pastel = TTY ? Pastel.new : nil; @prompt = TTY ? TTY::Prompt.new : nil)

  def puts(text = "") = Kernel.puts(text)

  def c(style, text) = @pastel ? @pastel.send(style, text) : text

  def banner(mode = nil)
    puts "\n#{c(:bold, "╔═══════════════════════════════════════╗")}"
    puts "#{c(:bold, "║")}   #{c(:cyan, "CONVERGENCE CLI")} #{c(:bright_yellow, "v∞.15.2")}        #{c(:bold, "║")}"
    puts "#{c(:bold, "╚═══════════════════════════════════════╝")}\n"

    puts "mode: #{mode}" if mode

    puts "master.yml: v#{MASTER_CONFIG.version}" if MASTER_CONFIG.version

    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}" if RUBY_PLATFORM =~ /openbsd/

    puts "type /help for commands\n"

  end

  def prompt = TTY ? @prompt.ask(">", required: false)&.strip : (print "> "; $stdin.gets&.chomp)

  def thinking(msg = "thinking") = TTY ? (s = TTY::Spinner.new("#{msg}...", format: :dots); s.auto_spin; yield.tap { s.success("") }) : (print "#{msg}... "; yield.tap { puts "done" })

  def response(text) = puts("\n#{text}\n")

  def error(msg) = puts(c(:red, "error: #{msg}"))

  def status(msg) = puts(c(:dim, msg))

  def ask_yes_no(question, default: true)
    prompt_text = default ? "#{question} [Y/n]" : "#{question} [y/N]"
    
    if TTY && @prompt
      @prompt.yes?(prompt_text)
    else
      print "#{prompt_text}: "
      answer = $stdin.gets&.chomp&.downcase
      return default if answer.empty?
      answer.start_with?("y")
    end
  end

  def ask_choice(question, choices)
    if TTY && @prompt
      @prompt.select(question, choices)
    else
      puts question
      choices.each_with_index { |choice, i| puts "  #{i + 1}. #{choice}" }
      print "Enter number (1-#{choices.size}): "
      idx = $stdin.gets&.chomp&.to_i
      return nil if idx < 1 || idx > choices.size
      choices[idx - 1]
    end
  end

  def ask_secret(prompt_text)
    if TTY && @prompt
      @prompt.mask(prompt_text)
    else
      print "#{prompt_text}: "
      $stdin.noecho(&:gets).chomp.tap { puts }
    end
  end
end

class WebChat
  PROVIDERS = {

    "claude" => { url: "https://claude.ai", input: 'div[contenteditable="true"]', response: '.font-claude-message' },

    "grok" => { url: "https://grok.x.ai", input: 'textarea[placeholder*="Ask"]', response: '[data-testid="message-content"]' },

    "deepseek" => { url: "https://chat.deepseek.com", input: 'textarea#chat-input', response: '.markdown-body' },

    "z.ai" => { url: "https://z.ai", input: 'textarea', response: '.response-text' },

    "lmsys" => { url: "https://chat.lmsys.org", input: 'textarea[data-testid="textbox"]', response: '.message.bot' },

    "chatgpt" => { url: "https://chatgpt.com", input: 'textarea#prompt-textarea', response: '.markdown' },

    "gemini" => { url: "https://gemini.google.com", input: 'textarea', response: '.model-response' },

    "glm" => { url: "https://chatglm.cn", input: 'textarea.chat-input', response: '.message-content' },

    "huggingchat" => { url: "https://huggingface.co/chat", input: 'textarea', response: '.prose' },

    "perplexity" => { url: "https://perplexity.ai", input: 'textarea', response: '.prose' },

    "copilot" => { url: "https://copilot.microsoft.com", input: 'textarea', response: '.response-message' },

    "poe" => { url: "https://poe.com", input: 'textarea', response: '.Message_botMessageBubble' }

  }

  def initialize(provider = "claude")

    @provider = provider

    @cfg = PROVIDERS[provider] || PROVIDERS["claude"]

    @browser = Ferrum::Browser.new(headless: true, timeout: 90, browser_path: find_browser, browser_options: { "no-sandbox": nil })

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

          return current.sub(/^(Model [AB]?:?s*|Response:?s*)/i, "").strip if (stable += 1) >= 3

        else

          stable, last = 0, current

        end

      end

      sleep 1

    end

  end

end

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

module ToolDSL
  def self.extended(base) = base.instance_variable_set(:@schema, [])

  def tool(name, desc, props = {}, required = []) = @schema << { name: name.to_s, description: desc, input_schema: { type: "object", properties: props, required: required.map(&:to_s) } }

  def schema = @schema

end

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

class FileTool
  extend ToolDSL

  tool :read_file, "Read file", { path: { type: "string" } }, [:path]

  tool :write_file, "Write file", { path: { type: "string" }, content: { type: "string" } }, [:path, :content]

  tool :list_dir, "List directory", { path: { type: "string" } }, [:path]

  ALLOWED = [ENV["HOME"], Dir.pwd, "/tmp"].compact

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

  def allowed?(path) = ALLOWED.any? { |a| File.expand_path(path).start_with?(File.expand_path(a)) }

end

class LangChainTool
  extend ToolDSL

  tool :run_chain, "Run LangChain chain", { chain_json: { type: "string" } }, [:chain_json]

  tool :rag_search, "RAG search", { query: { type: "string" } }, [:query]

  def initialize = @llm = Langchain::LLM::Anthropic.new(api_key: ENV["ANTHROPIC_API_KEY"]) if ENV["ANTHROPIC_API_KEY"]

  def run_chain(chain_json:) = LANGCHAIN ? { result: Langchain::Chain.new(@llm).call(JSON.parse(chain_json)["inputs"]) } : { error: "langchainrb unavailable" } rescue { error: $!.message }

  def rag_search(query:) = { results: Langchain::Vectorsearch::Chroma.new.similarity_search(query, k: 3).map { |r| r[:text] } } rescue { error: "vectorstore unavailable" }

end

class OpenBSDTool
  extend ToolDSL

  tool :fetch_news, "Fetch OpenBSD news", {}, []

  tool :search_packages, "Search OpenBSD packages", { query: { type: "string" } }, [:query]

  def fetch_news

    uri = URI("https://www.openbsd.amsterdam/news/")

    response = Net::HTTP.get(uri)

    news = response.scan(/<h2>(.*?)<\/h2>/).flatten.first(5)

    { news: news }

  rescue => e

    { error: e.message }

  end

  def search_packages(query:)

    uri = URI("https://www.openbsd.amsterdam/packages/?q=#{URI.encode_www_form_component(query)}")

    response = Net::HTTP.get(uri)

    packages = response.scan(/<a href=".*?">(.*?)<\/a>/).flatten.first(10)

    { packages: packages }

  rescue => e

    { error: e.message }

  end

end

class RAG
  def initialize = (@chunks = []; @embeddings = {}; @provider = detect_provider)

  def ingest(path)

    return ingest_dir(path) if File.directory?(path)

    text = File.read(path) rescue nil

    return 0 unless text

    chunks = chunk_text(text, source: path)

    chunks.each { |c| vec = embed(c[:text]); @chunks << c; @embeddings[c[:id]] = vec if vec }

    chunks.size

  end

  def search(query, k: 5) = qvec = embed(query); qvec ? @chunks.map { |c| vec = @embeddings[c[:id]]; vec ? { chunk: c, score: cosine(qvec, vec) } : nil }.compact.sort_by { |s| -s[:score] }.first(k) : []

  def augment(query, k: 3) = results = search(query, k); results.empty? ? query : "Context:\n#{results.map { |r| r[:chunk][:text] }.join("\n")}\nQuestion: #{query}"

  def stats = { chunks: @chunks.size, provider: @provider }

  private

  def detect_provider = ENV["OPENAI_API_KEY"] ? :openai : system("curl -s http://localhost:11434/api/tags > /dev/null 2>&1") ? :local : :none

  def embed(text) = case @provider; when :openai then embed_openai(text); when :local then embed_ollama(text); else nil; end

  def embed_openai(text) = Net::HTTP.post(URI("https://api.openai.com/v1/embeddings"), JSON.generate(model: "text-embedding-3-small", input: text), { "Authorization" => "Bearer #{ENV["OPENAI_API_KEY"]}", "Content-Type" => "application/json" }).then { |r| r.code == "200" ? JSON.parse(r.body).dig("data", 0, "embedding") : nil } rescue nil

  def embed_ollama(text) = Net::HTTP.post(URI("http://localhost:11434/api/embeddings"), JSON.generate(model: "nomic-embed-text", prompt: text), "Content-Type" => "application/json").then { |r| r.code == "200" ? JSON.parse(r.body)["embedding"] : nil } rescue nil

  def chunk_text(text, source: nil, size: 500) = text.split(/\n{2,}/).each_with_index.map { |p, i| { id: "#{i}_#{Digest::MD5.hexdigest(p)[0..7]}", text: p.strip, source: source, idx: i } if p.strip.size > 0 }.compact

  def cosine(a, b) = a.zip(b).sum { |x, y| x * y } / (Math.sqrt(a.sum { |x| x*x }) * Math.sqrt(b.sum { |y| y*y })) rescue 0

  def ingest_dir(path) = Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) && %w[.txt .md .rb .yml .json .html].include?(File.extname(f).downcase) }.sum { |f| ingest(f) }

end

class CLI
  HELP = <<~H

    /help          show commands

    /mode          show current mode

    /provider [X]  switch provider (webchat or API provider)

    /model [X]     switch model (API mode only)

    /key           update API key

    /reset         clear saved preferences and restart setup

    /tools         list available tools (API mode only)

    /yes           approve pending tool calls

    /no            reject pending tool calls

    /ingest PATH   add files to knowledge base

    /search QUERY  search knowledge base

    /rag           toggle RAG augmentation

    /rag-stats     show RAG statistics

    /chain JSON    run LangChain chain

    /webchat       launch webchat UI

    /screenshot    take browser screenshot

    /page-source   get browser page source

    /openbsd news    fetch OpenBSD news

    /openbsd packages QUERY    search packages

    /theme NAME    switch UI theme (starship-dark, etc.)

    /profile save/load NAME    manage profiles

    /clear         clear conversation

    exit           quit

  H

  def initialize

    UI.init
    
    # Load configuration module
    require_relative "cli_config"

    @config = Convergence::Config.load

    @mode = @config.mode

    @provider = @config.provider

    @api_key = @config.api_key_for(@provider) if @provider

    @model = @config.model

    @client = nil

    @tools = [ShellTool.new, FileTool.new, LangChainTool.new, OpenBSDTool.new]

    @rag = RAG.new

    @rag_enabled = false

    @theme = "default"

    @profiles = {}

  end

  def run

    # Run interactive setup if not configured
    unless @config.configured?
      interactive_setup
    end

    boot_sequence

    UI.banner(mode_label)

    setup_client

    loop do

      input = UI.prompt

      break if input.nil? || input =~ /^(exit|quit|bye)$/i

      next if input.strip.empty?

      input.start_with?("/") ? command(input) : message(input)

    end

    UI.status("session ended")

  ensure

    @client.quit if @client&.respond_to?(:quit)

  end

  private

  def interactive_setup
    UI.banner

    UI.puts "\nWelcome! Let's set up your CLI.\n\n"

    # Ask about FREE mode
    free_mode = UI.ask_yes_no("Enable FREE mode? (browser automation with free LLM providers)", default: true)

    if free_mode
      @mode = :webchat
      @provider = select_webchat_provider
    else
      @mode = :api
      @provider = select_api_provider
      @api_key = prompt_api_key(@provider)
    end

    # Save preferences
    @config.mode = @mode
    @config.provider = @provider
    @config.set_api_key(@provider, @api_key) if @api_key
    @config.save

    UI.status("\nConfiguration saved to ~/.convergence/config.yml")
    UI.puts ""
  end

  def select_webchat_provider
    # Load webchat module
    require_relative "cli_webchat"
    
    providers = Convergence::WebChatClient::PROVIDERS.keys.map(&:to_s)
    
    UI.puts "\nAvailable FREE providers (browser automation):"
    providers.each { |p| UI.puts "  • #{p}" }
    UI.puts ""
    
    choice = UI.ask_choice("Select provider:", providers)
    
    (choice || providers.first).to_sym
  end

  def select_api_provider
    # Load API module
    require_relative "cli_api"
    
    providers = Convergence::APIClient::PROVIDERS.keys.map(&:to_s)
    
    UI.puts "\nAvailable API providers:"
    providers.each { |p| UI.puts "  • #{p}" }
    UI.puts ""
    
    choice = UI.ask_choice("Select provider:", providers)
    
    (choice || "openrouter").to_sym
  end

  def prompt_api_key(provider)
    UI.puts "\nYou'll need an API key for #{provider}."
    
    case provider.to_sym
    when :openrouter
      UI.puts "Get your key at: https://openrouter.ai/keys"
    when :openai
      UI.puts "Get your key at: https://platform.openai.com/api-keys"
    when :anthropic
      UI.puts "Get your key at: https://console.anthropic.com/settings/keys"
    when :gemini
      UI.puts "Get your key at: https://makersuite.google.com/app/apikey"
    when :deepseek
      UI.puts "Get your key at: https://platform.deepseek.com/api_keys"
    end
    
    UI.puts ""
    UI.ask_secret("Enter API key")
  end

  def setup_client
    case @mode
    when :webchat
      require_relative "cli_webchat"
      @client = Convergence::WebChatClient.new(initial_provider: @provider)
    when :api
      require_relative "cli_api"
      @client = Convergence::APIClient.new(
        provider: @provider,
        api_key: @api_key,
        model: @model
      )
    else
      # Fallback to auto-detection for backward compatibility
      @mode = detect_mode
      @provider = @mode == :api ? :anthropic : :duckduckgo
      setup_client
    end
  end

  def boot_sequence

    puts "Welcome to **cli.rb** v∞.15.2 (RAG: #{@rag.stats[:chunks]} chunks, #{@rag.stats[:provider]}) - tokens: NONE"

    puts "<openbsd-inspired dmesg style boot process>"

    puts "cpu0: OpenBSD-like pledge+unveil enabled" if PLEDGE_AVAILABLE

    puts "master.yml v#{MASTER_CONFIG.version} loaded"

    puts "backend: #{mode_label}"

    puts "RAG provider: #{@rag.stats[:provider]}"

    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}"

    puts "..."

    puts "<begin chat>"

  end

  def detect_mode = ANTHROPIC && ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-") ? :api : FERRUM ? :webchat : :none

  def mode_label
    case @mode
    when :api
      model_name = @model || @client&.model || "unknown"
      "api/#{@provider}/#{model_name}"
    when :webchat
      "webchat/#{@provider}"
    else
      "unavailable"
    end
  end

  def command(input)

    parts = input.split(/\s+/, 2)

    cmd, arg = parts[0], parts[1]

    case cmd

    when "/help" then UI.puts(HELP)

    when "/mode" then show_mode

    when "/clear" then system("clear") || system("cls")

    when "/provider" then switch_provider(arg)

    when "/model" then switch_model(arg)

    when "/key" then update_api_key

    when "/reset" then reset_config

    when "/tools" then @mode == :api ? @tools.each { |t| t.class.schema.each { |s| UI.puts("#{s[:name]}: #{s[:description]}") } } : UI.status("tools only in API mode")

    when "/yes" then approve_tools(true)

    when "/no" then approve_tools(false)

    when "/ingest" then rag_ingest(arg)

    when "/search" then rag_search(arg)

    when "/rag" then toggle_rag

    when "/rag-stats" then UI.puts(@rag.stats.map { |k, v| "#{k}: #{v}" }.join(", "))

    when "/chain" then run_chain(arg)

    when "/webchat" then launch_webchat

    when "/screenshot" then UI.status("screenshot: #{@client.screenshot}") if @client&.respond_to?(:screenshot)

    when "/page-source" then UI.puts(@client.page_source[0..5000]) if @client&.respond_to?(:page_source)

    when "/openbsd" then openbsd_cmd(arg)

    when "/theme" then @theme = arg || "default"; UI.status("theme set to #{@theme}")

    when "/profile" then profile_cmd(arg)

    else UI.error("unknown command")

    end

  end

  def show_mode
    UI.puts "\n#{UI.c(:bold, "Current Configuration:")}"
    UI.puts "  Mode: #{UI.c(:cyan, @mode.to_s)}"
    UI.puts "  Provider: #{UI.c(:cyan, @provider.to_s)}"
    
    if @mode == :api
      UI.puts "  Model: #{UI.c(:cyan, @model || @client&.model || "default")}"
      
      if @client&.respond_to?(:usage_stats)
        stats = @client.usage_stats
        UI.puts "  Usage: #{stats[:total_tokens]} tokens (#{stats[:prompt_tokens]} prompt, #{stats[:completion_tokens]} completion)"
      end
    end
    
    UI.puts ""
  end

  def update_api_key
    unless @mode == :api
      UI.error("API keys only applicable in API mode")
      return
    end

    new_key = prompt_api_key(@provider)
    
    if new_key && !new_key.empty?
      @api_key = new_key
      @config.set_api_key(@provider, new_key)
      @config.save
      
      # Reconnect with new key
      setup_client
      
      UI.status("API key updated and saved")
    else
      UI.error("API key cannot be empty")
    end
  end

  def reset_config
    UI.puts "\n#{UI.c(:yellow, "Warning:")} This will clear all saved preferences."
    
    if UI.ask_yes_no("Are you sure?", default: false)
      @config.reset
      UI.status("Configuration reset. Restart the CLI to set up again.")
      exit 0
    else
      UI.status("Reset cancelled")
    end
  end

  def message(text)

    text = @rag.augment(text) if @rag_enabled && @rag.stats[:chunks] > 0

    response = UI.thinking do
      case @mode
      when :api
        # API client supports streaming
        if @client.respond_to?(:send)
          accumulated = ""
          @client.send(text) do |chunk|
            print chunk
            accumulated << chunk
          end
          puts "" unless accumulated.empty?
          accumulated
        else
          @client.send(text)
        end
      when :webchat
        # WebChat client
        if @client.respond_to?(:send_message)
          @client.send_message(text)
        else
          @client.send(text)
        end
      else
        "Error: No client available"
      end
    end

    UI.response(response) unless response.nil? || response.empty?

    show_pending_tools if @mode == :api && @client&.respond_to?(:pending_tools?) && @client.pending_tools?

  rescue => e

    UI.error(e.message)

    Log.error(e.message, backtrace: e.backtrace.first(3)) if defined?(Log)

  end

  def show_pending_tools = @client.pending_tools.each { |tc| UI.puts("tool: #{tc["name"]}"); UI.puts("input: #{tc["input"].to_json}") }; UI.status("approve with /yes or /no")

  def approve_tools(approved)

    return UI.status("no pending tools") unless @mode == :api && @client&.respond_to?(:pending_tools?) && @client.pending_tools?

    if approved

      response = UI.thinking("executing") { @client.process_tool_results(execute_pending) }

      UI.response(response)

    else

      UI.status("tools rejected")

    end

  end

  def execute_pending = @client.pending_tools.map { |tc| tool = @tools.find { |t| t.class.schema.any? { |s| s[:name] == tc["name"] } }; result = tool ? tool.send(tc["name"], **tc["input"].transform_keys(&:to_sym)) : { error: "unknown" }; { type: "tool_result", tool_use_id: tc["id"], content: JSON.generate(result) } }

  def switch_provider(name)

    if name.nil? || name.empty?
      case @mode
      when :webchat
        require_relative "cli_webchat"
        providers = Convergence::WebChatClient::PROVIDERS.keys
        UI.puts("Available webchat providers:")
        providers.each { |p| UI.puts("  • #{p}") }
      when :api
        require_relative "cli_api"
        providers = Convergence::APIClient::PROVIDERS.keys
        UI.puts("Available API providers:")
        providers.each { |p| UI.puts("  • #{p}") }
      else
        UI.error("No mode configured")
      end
      return
    end

    case @mode
    when :webchat
      require_relative "cli_webchat"
      
      unless Convergence::WebChatClient::PROVIDERS.key?(name.to_sym)
        UI.error("unknown provider: #{name}")
        return
      end

      @client&.quit if @client&.respond_to?(:quit)

      @provider = name.to_sym

      UI.thinking("connecting to #{name}") do
        @client = Convergence::WebChatClient.new(initial_provider: @provider)
      end

      @config.provider = @provider
      @config.save

      UI.status("switched to #{name}")

    when :api
      require_relative "cli_api"
      
      unless Convergence::APIClient::PROVIDERS.key?(name.to_sym)
        UI.error("unknown provider: #{name}")
        return
      end

      @provider = name.to_sym
      @api_key = @config.api_key_for(@provider)

      unless @api_key
        @api_key = prompt_api_key(@provider)
        @config.set_api_key(@provider, @api_key)
      end

      @client = Convergence::APIClient.new(
        provider: @provider,
        api_key: @api_key,
        model: @model
      )

      @config.provider = @provider
      @config.save

      UI.status("switched to #{@provider}")

    else
      UI.error("provider switching not available in current mode")
    end

  rescue => e
    UI.error("Failed to switch provider: #{e.message}")
  end

  def switch_model(name)
    unless @mode == :api
      UI.error("model switching only available in API mode")
      return
    end

    unless @client&.respond_to?(:models)
      UI.error("current client doesn't support model switching")
      return
    end

    if name.nil? || name.empty?
      UI.puts("Available models for #{@provider}:")
      @client.models.each { |short, full| UI.puts("  • #{short} (#{full})") }
      return
    end

    if @client.switch_model(name)
      @model = @client.model
      @config.model = @model
      @config.save
      UI.status("switched to model: #{@model}")
    else
      UI.error("unknown model: #{name}")
      UI.puts("Available models:")
      @client.models.each { |short, full| UI.puts("  • #{short} (#{full})") }
    end
  end

  def rag_ingest(path) = arg ? (count = UI.thinking("ingesting") { @rag.ingest(File.expand_path(path)) }; UI.status("added #{count} chunks")) : UI.error("usage: /ingest PATH")

  def rag_search(query) = query ? (results = @rag.search(query); results.empty? ? UI.status("no results") : results.each_with_index { |r, i| UI.puts("#{i + 1}. [#{r[:score].round(3)}] #{r[:chunk][:source]}"); UI.puts("   #{r[:chunk][:text][0..150]}...") }) : UI.error("usage: /search QUERY")

  def toggle_rag = (@rag_enabled = !@rag_enabled; UI.status("RAG #{@rag_enabled ? "enabled" : "disabled"}"); UI.status("knowledge base empty, use /ingest first") if @rag_enabled && @rag.stats[:chunks] == 0)

  def run_chain(json) = json ? (tool = @tools.find { |t| t.is_a?(LangChainTool) }; UI.puts("chain result: #{tool.run_chain(chain_json: json)}")) : UI.error("usage: /chain JSON")

  def launch_webchat

    require "webrick"

    server = WEBrick::HTTPServer.new(Port: 8000)

    server.mount_proc("/chat") { |req, res| res.content_type = "text/html"; res.body = "<html><body><form action='/send' method='post'><input name='message'><button>Send</button></form><div id='response'></div></body></html>" }

    server.mount_proc("/send") { |req, res| msg = req.query["message"]; response = @client.send(msg) rescue "error"; res.content_type = "text/html"; res.body = "<html><body>Response: #{response}</body></html>" }

    UI.status("webchat at http://localhost:8000/chat")

    server.start

  end

  def openbsd_cmd(arg)

    parts = arg.split(/\s+/, 2)

    subcmd, param = parts[0], parts[1]

    tool = @tools.find { |t| t.is_a?(OpenBSDTool) }

    case subcmd

    when "news" then UI.puts(tool.fetch_news)

    when "packages" then UI.puts(tool.search_packages(query: param)) if param

    else UI.error("usage: /openbsd news or /openbsd packages QUERY")

    end

  end

  def profile_cmd(arg)

    parts = arg.split(/\s+/)

    action, name = parts[0], parts[1]

    case action

    when "save" then @profiles[name] = { rag: @rag.stats, theme: @theme }; UI.status("profile #{name} saved")

    when "load" then if @profiles[name]; @theme = @profiles[name][:theme]; UI.status("profile #{name} loaded"); else UI.error("profile not found"); end

    else UI.error("usage: /profile save/load NAME")

    end

  end

end

CLI.new.run if __FILE__ == $0
