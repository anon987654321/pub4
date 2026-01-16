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

  def banner(mode)

    puts "convergence v∞.15.2"

    puts "mode: #{mode}"

    puts "master.yml: v#{MASTER_CONFIG.version}" if MASTER_CONFIG.version

    puts "security: #{PLEDGE_AVAILABLE ? "pledge+unveil" : "standard"}" if RUBY_PLATFORM =~ /openbsd/

    puts "type /help for commands\n"

  end

  def prompt = TTY ? @prompt.ask(">", required: false)&.strip : (print "> "; $stdin.gets&.chomp)

  def thinking(msg = "thinking") = TTY ? (s = TTY::Spinner.new("#{msg}...", format: :dots); s.auto_spin; yield.tap { s.success("") }) : (print "#{msg}... "; yield.tap { puts "done" })

  def response(text) = puts("\n#{text}\n")

  def error(msg) = puts(c(:red, "error: #{msg}"))

  def status(msg) = puts(c(:dim, msg))

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

class JudgeSelector
  def initialize
    @mode = "auto"
  end

  def set_mode(mode)
    @mode = mode
  end

  def judge(user_query, candidates, echo_manager = nil)
    # Filter out failed candidates
    valid_candidates = candidates.select { |c| c[:response] && !c[:response].empty? }
    
    return fallback_select(valid_candidates) if valid_candidates.empty?
    return valid_candidates.first[:response] if valid_candidates.size == 1

    judge_prompt = build_judge_prompt(user_query, valid_candidates)

    case @mode
    when "auto"
      # Try local → API → webchat fallback
      result = try_local_judge(judge_prompt) || 
               try_api_judge(judge_prompt) ||
               try_webchat_judge(judge_prompt, echo_manager)
      result || fallback_select(valid_candidates)
    when "local"
      try_local_judge(judge_prompt) || fallback_select(valid_candidates)
    when "api"
      try_api_judge(judge_prompt) || fallback_select(valid_candidates)
    else
      # Specific provider mode
      try_provider_judge(judge_prompt, @mode, echo_manager) || fallback_select(valid_candidates)
    end
  end

  private

  def build_judge_prompt(query, candidates)
    prompt = "You are a judge evaluating multiple AI responses to select the best answer.\n\n"
    prompt += "User question: #{query}\n\n"
    prompt += "Candidate answers:\n\n"
    candidates.each_with_index do |c, i|
      prompt += "Candidate #{i + 1} (#{c[:provider]}, latency: #{c[:latency]&.round(2)}s):\n"
      prompt += "#{c[:response]}\n\n"
    end
    prompt += "Respond with JSON containing: {\"winner\": <number>, \"final_answer\": \"<synthesized or selected answer>\"}\n"
    prompt += "Select the most accurate, complete, and helpful answer. You may synthesize elements from multiple candidates."
    prompt
  end

  def try_local_judge(prompt)
    return nil unless ollama_available?
    
    uri = URI("http://localhost:11434/api/generate")
    payload = { model: "llama3.2:3b", prompt: prompt, stream: false }
    response = Timeout.timeout(30) do
      Net::HTTP.post(uri, JSON.generate(payload), "Content-Type" => "application/json")
    end
    
    if response.code == "200"
      text = JSON.parse(response.body)["response"]
      parse_judge_response(text)
    else
      nil
    end
  rescue
    nil
  end

  def try_api_judge(prompt)
    return nil unless ENV["ANTHROPIC_API_KEY"]&.start_with?("sk-ant-")
    
    client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
    response = client.messages(
      model: "claude-3-5-haiku-20241022",
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }]
    )
    
    text = response["content"].map { |c| c["text"] }.compact.join("\n")
    parse_judge_response(text)
  rescue
    nil
  end

  def try_webchat_judge(prompt, echo_manager)
    return nil unless echo_manager
    
    healthy = echo_manager.healthy_providers
    return nil if healthy.empty?
    
    provider = healthy.first
    try_provider_judge(prompt, provider, echo_manager)
  end

  def try_provider_judge(prompt, provider_name, echo_manager)
    return nil unless echo_manager && WebChat::PROVIDERS[provider_name]
    
    session = echo_manager.send(:get_or_create_session, provider_name)
    response = Timeout.timeout(30) { session.send(prompt) }
    parse_judge_response(response)
  rescue
    nil
  end

  def parse_judge_response(text)
    # Try to extract JSON
    json_match = text.match(/\{[^}]*"final_answer"[^}]*\}/m)
    if json_match
      data = JSON.parse(json_match[0])
      return data["final_answer"] if data["final_answer"]
    end
    nil
  rescue
    nil
  end

  def fallback_select(candidates)
    # Heuristic: prefer non-empty, longest, best latency
    best = candidates.max_by do |c|
      length_score = c[:response]&.length || 0
      latency_score = c[:latency] ? (1.0 / (c[:latency] + 0.1)) : 0
      length_score * 0.7 + latency_score * 0.3
    end
    best ? best[:response] : "No valid responses received."
  end

  def ollama_available?
    system("curl -s http://localhost:11434/api/tags > /dev/null 2>&1")
  end
end

class EchoProviderManager
  attr_reader :providers, :health

  def initialize(provider_names = ["glm", "deepseek", "grok"])
    @providers = {}
    @health = {}
    @timeout = 45
    provider_names.each { |name| add_provider(name) if WebChat::PROVIDERS[name] }
  end

  def add_provider(name)
    return if @providers[name]
    @health[name] = {
      enabled: true,
      last_ok_at: nil,
      last_error: nil,
      consecutive_failures: 0,
      avg_latency: 0,
      total_queries: 0
    }
  end

  def remove_provider(name)
    @providers[name]&.quit rescue nil
    @providers.delete(name)
    @health.delete(name)
  end

  def set_timeout(seconds)
    @timeout = [seconds.to_i, 10].max
  end

  def query_all(text)
    results = []
    healthy = healthy_providers

    if healthy.empty?
      # Try to re-enable all providers if all are disabled
      @health.each { |name, h| h[:enabled] = true if h[:consecutive_failures] < 10 }
      healthy = healthy_providers
    end

    threads = healthy.map do |name|
      Thread.new do
        begin
          start_time = Time.now
          session = get_or_create_session(name)
          response = Timeout.timeout(@timeout) { session.send(text) }
          latency = Time.now - start_time
          
          update_health_success(name, latency)
          { provider: name, response: response, latency: latency, error: nil }
        rescue => e
          update_health_failure(name, e.message)
          { provider: name, response: nil, latency: nil, error: e.message }
        end
      end
    end

    threads.each { |t| results << t.value }
    results
  end

  def healthy_providers
    @health.select { |name, h| h[:enabled] && h[:consecutive_failures] < 3 }.keys
  end

  def status
    @health.map do |name, h|
      status_str = h[:enabled] ? (h[:consecutive_failures] > 0 ? "degraded" : "healthy") : "disabled"
      latency_str = h[:avg_latency] > 0 ? "#{h[:avg_latency].round(2)}s" : "n/a"
      "#{name}: #{status_str}, latency: #{latency_str}, queries: #{h[:total_queries]}, failures: #{h[:consecutive_failures]}"
    end.join("\n")
  end

  def close_all
    @providers.each { |_, session| session.quit rescue nil }
    @providers.clear
  end

  private

  def get_or_create_session(name)
    unless @providers[name]
      @providers[name] = WebChat.new(name)
    end
    @providers[name]
  end

  def update_health_success(name, latency)
    h = @health[name]
    h[:last_ok_at] = Time.now
    h[:consecutive_failures] = 0
    h[:total_queries] += 1
    h[:avg_latency] = (h[:avg_latency] * (h[:total_queries] - 1) + latency) / h[:total_queries]
  end

  def update_health_failure(name, error_msg)
    h = @health[name]
    h[:last_error] = error_msg
    h[:consecutive_failures] += 1
    h[:total_queries] += 1
    h[:enabled] = false if h[:consecutive_failures] >= 3
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

    /provider X    switch webchat provider (claude primary, grok, deepseek, z.ai, etc.)

    /tools         list available tools (API mode only)

    /yes           approve pending tool calls

    /no            reject pending tool calls

    /echo on|off           enable/disable echo chamber mode

    /echo providers LIST   set echo providers (default: glm deepseek grok)

    /echo timeout SECS     set per-provider timeout (default: 45)

    /echo show             show provider health/status

    /echo debug on|off     show all candidate responses

    /judge MODE            set judge mode: auto|local|api|<provider> (default: auto)

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

    @mode = detect_mode

    @provider = "claude"

    @client = nil

    @tools = [ShellTool.new, FileTool.new, LangChainTool.new, OpenBSDTool.new]

    @rag = RAG.new

    @rag_enabled = false

    @theme = "default"

    @profiles = {}

    @echo_enabled = false

    @echo_manager = nil

    @echo_debug = false

    @judge = JudgeSelector.new

  end

  def run

    boot_sequence

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

    @echo_manager&.close_all

  end

  private

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

  def mode_label = case @mode; when :api then "api (#{ENV["CLAUDE_MODEL"] || "claude-sonnet-4-20250514"})"; when :webchat then "webchat/#{@provider}"; else "unavailable"; end

  def connect

    case @mode

    when :api then @client = APIClient.new(@tools); UI.status("connected to API")

    when :webchat then UI.thinking("connecting to #{@provider}") { @client = WebChat.new(@provider) }; UI.status("connected")

    else UI.error("no backend"); exit 1

    end

  end

  def command(input)

    parts = input.split(/\s+/, 2)

    cmd, arg = parts[0], parts[1]

    case cmd

    when "/help" then UI.puts(HELP)

    when "/mode" then UI.status(mode_label)

    when "/clear" then system("clear") || system("cls")

    when "/tools" then @mode == :api ? @tools.each { |t| t.class.schema.each { |s| UI.puts("#{s[:name]}: #{s[:description]}") } } : UI.status("tools only in API mode")

    when "/yes" then approve_tools(true)

    when "/no" then approve_tools(false)

    when "/provider" then switch_provider(arg)

    when "/ingest" then rag_ingest(arg)

    when "/search" then rag_search(arg)

    when "/rag" then toggle_rag

    when "/rag-stats" then UI.puts(@rag.stats.map { |k, v| "#{k}: #{v}" }.join(", "))

    when "/chain" then run_chain(arg)

    when "/webchat" then launch_webchat

    when "/screenshot" then UI.status("screenshot: #{@client.screenshot}") if @client.is_a?(WebChat)

    when "/page-source" then UI.puts(@client.page_source[0..5000]) if @client.is_a?(WebChat)

    when "/openbsd" then openbsd_cmd(arg)

    when "/theme" then @theme = arg || "default"; UI.status("theme set to #{@theme}")

    when "/profile" then profile_cmd(arg)

    when "/echo" then echo_cmd(arg)

    when "/judge" then judge_cmd(arg)

    else UI.error("unknown command")

    end

  end

  def message(text)

    text = @rag.augment(text) if @rag_enabled && @rag.stats[:chunks] > 0

    if @echo_enabled && @mode == :webchat
      echo_message(text)
    else
      response = UI.thinking { @client.send(text) }

      UI.response(response)

      show_pending_tools if @mode == :api && @client.pending_tools?
    end

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

  def echo_cmd(arg)
    return UI.error("echo mode only works in webchat mode") unless @mode == :webchat

    parts = arg.to_s.split(/\s+/)
    subcmd = parts[0]

    case subcmd
    when "on"
      @echo_enabled = true
      @echo_manager ||= EchoProviderManager.new(["glm", "deepseek", "grok"])
      UI.status("echo chamber enabled with providers: #{@echo_manager.healthy_providers.join(", ")}")
    when "off"
      @echo_enabled = false
      @echo_manager&.close_all
      @echo_manager = nil
      UI.status("echo chamber disabled")
    when "providers"
      if parts.size > 1
        provider_list = parts[1..-1]
        invalid = provider_list.reject { |p| WebChat::PROVIDERS[p] }
        if invalid.any?
          UI.error("unknown providers: #{invalid.join(", ")}")
        else
          @echo_manager&.close_all
          @echo_manager = EchoProviderManager.new(provider_list)
          UI.status("echo providers set to: #{provider_list.join(", ")}")
        end
      else
        UI.puts("available providers: #{WebChat::PROVIDERS.keys.join(", ")}")
        UI.puts("current: #{@echo_manager&.healthy_providers&.join(", ") || "none"}")
      end
    when "timeout"
      if parts[1]
        timeout = parts[1].to_i
        if timeout >= 10
          @echo_manager ||= EchoProviderManager.new
          @echo_manager.set_timeout(timeout)
          UI.status("echo timeout set to #{timeout}s")
        else
          UI.error("timeout must be at least 10 seconds")
        end
      else
        UI.error("usage: /echo timeout <seconds>")
      end
    when "show"
      if @echo_manager
        UI.puts(@echo_manager.status)
      else
        UI.status("echo chamber not initialized")
      end
    when "debug"
      if parts[1] == "on"
        @echo_debug = true
        UI.status("echo debug enabled")
      elsif parts[1] == "off"
        @echo_debug = false
        UI.status("echo debug disabled")
      else
        UI.error("usage: /echo debug on|off")
      end
    else
      UI.error("usage: /echo on|off|providers|timeout|show|debug")
    end
  end

  def judge_cmd(arg)
    return UI.error("judge mode only works with echo chamber") unless @echo_enabled

    mode = arg.to_s.strip
    if mode.empty?
      UI.error("usage: /judge auto|local|api|<provider>")
    elsif mode == "auto" || mode == "local" || mode == "api"
      @judge.set_mode(mode)
      UI.status("judge mode set to: #{mode}")
    elsif WebChat::PROVIDERS[mode]
      @judge.set_mode(mode)
      UI.status("judge mode set to provider: #{mode}")
    else
      UI.error("unknown judge mode: #{mode}")
    end
  end

  def echo_message(text)
    UI.status("querying echo providers...")
    
    candidates = UI.thinking("collecting responses") do
      @echo_manager.query_all(text)
    end

    if @echo_debug
      UI.puts("\n" + UI.c(:dim, "=== Candidate Responses ==="))
      candidates.each do |c|
        if c[:error]
          UI.puts(UI.c(:red, "#{c[:provider]}: ERROR - #{c[:error]}"))
        else
          UI.puts(UI.c(:cyan, "#{c[:provider]} (#{c[:latency]&.round(2)}s):"))
          UI.puts(c[:response][0..500] + (c[:response].length > 500 ? "..." : ""))
          UI.puts("")
        end
      end
      UI.puts(UI.c(:dim, "=== Judging ==="))
    end

    final_answer = UI.thinking("judging responses") do
      @judge.judge(text, candidates, @echo_manager)
    end

    UI.response(final_answer)
  end

end

CLI.new.run if __FILE__ == $0
