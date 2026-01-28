#!/usr/bin/env ruby
# frozen_string_literal: true

# Master CLI v24.0
# Constitutional AI governance tool with LLM-powered system management
VERSION = "24.0.0"

require "json"
require "yaml"
require "fileutils"
require "readline"
require "digest/sha2"

begin
  require "tty-prompt"
  require "tty-progressbar"
  require "pastel"
  TTY_AVAILABLE = true
rescue LoadError
  TTY_AVAILABLE = false
  warn "Install tty gems for better UX: gem install tty-prompt tty-progressbar pastel"
end

begin
  require "ruby_llm"
  RUBY_LLM_AVAILABLE = true
rescue LoadError
  RUBY_LLM_AVAILABLE = false
  warn "Install ruby_llm for AI features: gem install ruby_llm"
end

LIMITS = {stdout: 10_000, stderr: 4000, file: 100_000, timeout: 30}
COMMANDS = {help: "h", scan: "s", fix: "f", validate: "v", export: "e", status: "S", chat: "c", quit: "q"}

class Result
  attr_reader :value, :error
  
  def initialize(value: nil, error: nil)
    @value = value
    @error = error
    freeze
  end
  
  def self.ok(value) = new(value: value)
  def self.err(error) = new(error: error)
  
  def ok? = !@error
  def err? = !!@error
  
  def map(&block)
    ok? ? Result.ok(block.call(@value)) : self
  end
  
  def then(&block)
    ok? ? block.call(@value) : self
  end
  
  def or_else(default)
    ok? ? @value : default
  end
end

module UX
  class << self
    def confirm?(msg)
      if TTY_AVAILABLE
        prompt.yes?("#{msg}?")
      else
        print "#{msg}? (y/N): "
        gets.chomp.downcase == "y"
      end
    end
    
    def progress(total:, format: "[:bar] :percent :current/:total")
      if TTY_AVAILABLE
        bar = TTY::ProgressBar.new(format, total: total)
        (1..total).each do |i|
          yield(i)
          bar.advance
        end
      else
        (1..total).each do |i|
          pct = (i.to_f / total * 100).to_i
          filled = '█' * (pct / 2)
          empty = '░' * (50 - pct / 2)
          print "\r[#{filled}#{empty}] #{pct}%"
          yield(i)
        end
        puts
      end
    end
    
    def success(msg)
      TTY_AVAILABLE ? pastel.green("✓ #{msg}") : "✓ #{msg}"
    end
    
    def error(msg)
      TTY_AVAILABLE ? pastel.red("✗ #{msg}") : "✗ #{msg}"
    end
    
    def warning(msg)
      TTY_AVAILABLE ? pastel.yellow("⚠  #{msg}") : "⚠  #{msg}"
    end
    
    private
    
    def prompt
      @prompt ||= TTY::Prompt.new
    end
    
    def pastel
      @pastel ||= Pastel.new
    end
  end
end

# LLM Tools for ruby_llm integration
module Tools
  # Base tool class following ruby_llm pattern
  class BaseTool
    class << self
      attr_reader :tool_description, :tool_params
      
      def description(text)
        @tool_description = text
      end
      
      def param(name, type: "string", desc: nil, required: true)
        @tool_params ||= {}
        @tool_params[name] = {type: type, description: desc, required: required}
      end
    end
    
    def name
      self.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end
    
    def description
      self.class.tool_description
    end
    
    def parameters
      self.class.tool_params || {}
    end
  end
  
  # File system operations (read, write, list, delete)
  class FileSystemTool < BaseTool
    description "Manage files and directories: list, read, write, delete"
    param :action, desc: "Action: list_directory, read_file, write_file, delete_file"
    param :path, desc: "File or directory path"
    param :content, desc: "Content to write (for write_file)", required: false
    
    SANDBOX_PATHS = [Dir.pwd, Dir.home, "/tmp", ENV["TMPDIR"]].compact
    
    def execute(action:, path:, content: nil)
      return {error: "Path outside sandbox"} unless safe_path?(path)
      
      case action.to_s
      when "list_directory" then list_directory(path)
      when "read_file" then read_file(path)
      when "write_file" then write_file(path, content)
      when "delete_file" then delete_file(path)
      else {error: "Unknown action: #{action}"}
      end
    rescue => e
      {error: e.message}
    end
    
    private
    
    def safe_path?(path)
      expanded = File.expand_path(path)
      SANDBOX_PATHS.any? { |safe| expanded.start_with?(safe) }
    end
    
    def list_directory(path)
      return {error: "Not a directory: #{path}"} unless File.directory?(path)
      entries = Dir.entries(path).reject { |e| e.start_with?(".") }
      {result: entries, count: entries.size}
    end
    
    def read_file(path)
      return {error: "File not found: #{path}"} unless File.exist?(path)
      return {error: "File too large"} if File.size(path) > LIMITS[:file]
      {result: File.read(path), size: File.size(path)}
    end
    
    def write_file(path, content)
      return {error: "No content provided"} unless content
      File.write(path, content)
      {result: "Written #{content.size} bytes to #{path}"}
    end
    
    def delete_file(path)
      return {error: "File not found: #{path}"} unless File.exist?(path)
      File.delete(path)
      {result: "Deleted #{path}"}
    end
  end
  
  # Shell command execution with allowlist
  class ShellTool < BaseTool
    description "Execute shell commands safely"
    param :command, desc: "Command to execute"
    param :args, desc: "Command arguments", required: false
    
    ALLOWLIST = %w[ls cat grep find head tail wc file stat pkg_info rcctl pfctl ifconfig netstat ps uptime df du]
    CONFIRM_REQUIRED = %w[rm mv cp mkdir rmdir pkg_add pkg_delete rcctl pfctl]
    
    def execute(command:, args: "")
      cmd_name = command.to_s.split.first
      
      return {error: "Command not in allowlist: #{cmd_name}"} unless allowed?(cmd_name)
      return {error: "Confirmation required for: #{cmd_name}", needs_confirmation: true} if needs_confirmation?(cmd_name)
      
      full_cmd = "#{command} #{args}".strip
      output = `#{full_cmd} 2>&1`
      status = $?.success?
      
      {result: output.slice(0, LIMITS[:stdout]), success: status, command: full_cmd}
    rescue => e
      {error: e.message}
    end
    
    private
    
    def allowed?(cmd)
      ALLOWLIST.include?(cmd) || CONFIRM_REQUIRED.include?(cmd)
    end
    
    def needs_confirmation?(cmd)
      CONFIRM_REQUIRED.include?(cmd)
    end
  end
  
  # OpenBSD service management via rcctl
  class ServiceTool < BaseTool
    description "Manage OpenBSD services via rcctl"
    param :action, desc: "Action: status, start, stop, restart, enable, disable"
    param :service, desc: "Service name"
    
    CONFIRM_REQUIRED = %w[start stop restart enable disable]
    
    def execute(action:, service:)
      return {error: "Invalid service name"} unless service.match?(/\A[a-z_][a-z0-9_]*\z/)
      
      if CONFIRM_REQUIRED.include?(action.to_s)
        return {error: "Confirmation required", needs_confirmation: true, action: action, service: service}
      end
      
      output = `rcctl #{action} #{service} 2>&1`
      {result: output.strip, success: $?.success?, action: action, service: service}
    rescue => e
      {error: e.message}
    end
  end
  
  # Network information tools
  class NetworkTool < BaseTool
    description "Network information: pf status, interfaces, connections"
    param :action, desc: "Action: pf_status, ifconfig, netstat, route"
    param :interface, desc: "Network interface (optional)", required: false
    
    def execute(action:, interface: nil)
      case action.to_s
      when "pf_status" then run_cmd("pfctl -s info")
      when "ifconfig" then run_cmd(interface ? "ifconfig #{interface}" : "ifconfig")
      when "netstat" then run_cmd("netstat -an | head -50")
      when "route" then run_cmd("route -n show")
      else {error: "Unknown action: #{action}"}
      end
    rescue => e
      {error: e.message}
    end
    
    private
    
    def run_cmd(cmd)
      output = `#{cmd} 2>&1`
      {result: output.slice(0, LIMITS[:stdout]), success: $?.success?}
    end
  end
end

# LLM Chat integration
class LLMChat
  attr_reader :chat, :tools, :history
  
  def initialize(master)
    @master = master
    @history = []
    @tools = [
      Tools::FileSystemTool.new,
      Tools::ShellTool.new,
      Tools::ServiceTool.new,
      Tools::NetworkTool.new
    ]
    
    setup_llm if RUBY_LLM_AVAILABLE
  end
  
  def available?
    RUBY_LLM_AVAILABLE && @chat
  end
  
  def ask(message)
    return {error: "LLM not available"} unless available?
    
    @history << {role: "user", content: message}
    
    response = @chat.ask(message)
    @history << {role: "assistant", content: response.content}
    
    {content: response.content, tokens: response.total_tokens}
  rescue => e
    {error: e.message}
  end
  
  def ask_with_tools(message)
    return {error: "LLM not available"} unless available?
    
    # Add tools to chat context
    tool_descriptions = @tools.map do |t|
      "#{t.name}: #{t.description}"
    end.join("\n")
    
    system_prompt = <<~PROMPT
      You are Master CLI, an AI assistant for managing OpenBSD systems.
      Follow the governance rules from master.yml.
      Available tools:
      #{tool_descriptions}
      
      When you need to perform an action, respond with a tool call in JSON format:
      {"tool": "tool_name", "params": {"param1": "value1"}}
    PROMPT
    
    @chat.with_instructions(system_prompt)
    response = @chat.ask(message)
    
    # Check if response contains a tool call
    if response.content.include?('"tool"')
      handle_tool_call(response.content)
    else
      {content: response.content}
    end
  rescue => e
    {error: e.message}
  end
  
  private
  
  def setup_llm
    llm_config = @master.data.dig("llm") || {}
    models = llm_config.dig("models") || {}
    default_model = models["default"] || "anthropic/claude-sonnet-4"
    
    RubyLLM.configure do |config|
      config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY") { nil }
    end
    
    return unless ENV["OPENROUTER_API_KEY"]
    
    @chat = RubyLLM.chat(model: default_model)
    @models = models
  rescue => e
    warn "LLM setup failed: #{e.message}"
    @chat = nil
  end
  
  def switch_model(model_key)
    return {error: "LLM not available"} unless RUBY_LLM_AVAILABLE
    
    # Allow switching by key (fast, reasoning, coding) or direct model name
    model = @models&.dig(model_key) || @models&.dig("available")&.values&.flatten&.find { |m| m.include?(model_key) }
    model ||= model_key  # Use as-is if not found in config
    
    @chat = RubyLLM.chat(model: model)
    {result: "Switched to #{model}"}
  rescue => e
    {error: e.message}
  end
  
  def handle_tool_call(content)
    # Extract JSON from response
    json_match = content.match(/\{[^}]+\}/)
    return {content: content} unless json_match
    
    tool_call = JSON.parse(json_match[0])
    tool_name = tool_call["tool"]
    params = tool_call["params"] || {}
    
    tool = @tools.find { |t| t.name == tool_name }
    return {error: "Unknown tool: #{tool_name}"} unless tool
    
    result = tool.execute(**params.transform_keys(&:to_sym))
    
    if result[:needs_confirmation]
      {needs_confirmation: true, tool: tool_name, params: params, result: result}
    else
      {tool_result: result, tool: tool_name}
    end
  rescue JSON::ParserError
    {content: content}
  end
end

class Master
  attr_reader :data, :path
  
  def self.load(path: "master.yml")
    return Result.err("File not found: #{path}") unless File.exist?(path)
    
    data = YAML.load_file(path, aliases: true, permitted_classes: [Symbol])
    master = new(data, path)
    master.validate
  rescue => e
    Result.err("Load failed: #{e.message}")
  end
  
  def initialize(data, path)
    @data = data
    @path = path
  end
  
  def validate
    required = %w[version golden_rule execution]
    missing = required - @data.keys.map(&:to_s)
    
    return Result.err("Missing keys: #{missing.join(', ')}") unless missing.empty?
    
    Result.ok(self)
  end
  
  def execution_steps
    @data.dig("execution") || {}
  end
  
  def adversarial_personas
    @data.dig("adversarial") || {}
  end
  
  def master_config
    @data.dig("convergence") || {max: 15, exit: {violations: 0}}
  end
  
  def principles
    @data.dig("principles") || {}
  end
  
  def veto?(principle)
    principles.dig("veto")&.include?(principle.to_s) || false
  end
  
  def bias_patterns
    @data.dig("biases", "critical", "simulation") || []
  end
end

class MasterEngine
  attr_reader :master, :max_iterations, :violations
  
  def initialize(master)
    @master = master
    @max_iterations = master.master_config[:max]
    @violations = []
    @iteration = 0
  end
  
  def converge(target:)
    puts UX.warning("Starting master validation on #{target}")
    puts "Max iterations: #{@max_iterations}"
    puts
    
    @iteration = 0
    previous_violations = nil
    
    loop do
      @iteration += 1
      puts "Iteration #{@iteration} of #{@max_iterations}"
      
      result = scan(target)
      return result if result.err?
      
      @violations = result.value
      
      if @violations.empty?
        puts UX.success("Master achieved: 0 violations")
        return Result.ok({iterations: @iteration, violations: 0, converged: true})
      end
      
      if obvious_fix?
        puts "Obvious fix detected, bypassing 15 alternatives"
      end
      
      if @violations == previous_violations
        puts UX.warning("Oscillating: same violations")
        return Result.ok({iterations: @iteration, violations: @violations.size, converged: false})
      end
      
      if @iteration >= @max_iterations
        puts UX.warning("Max iterations reached")
        return Result.ok({iterations: @iteration, violations: @violations.size, converged: false})
      end
      
      puts "Found #{@violations.size} violations"
      @violations.each { |v| puts "  #{v[:type]} at line #{v[:line]}" }
      
      fixed = apply_fixes(target)
      puts UX.success("Applied #{fixed} fixes")
      puts
      
      previous_violations = @violations.dup
    end
  end
  
  private
  
  def scan(file)
    return Result.err("File not found") unless File.exist?(file)
    
    content = File.read(file)
    violations = []
    scanner_file = file.end_with?("cli.rb") || file.end_with?("master_engine.rb")
    
    content.lines.each_with_index do |line, idx|
      line_num = idx + 1
      
      violations << {type: :hardcoded_secret, line: line_num, severity: :veto} if 
        line.match?(/password\s*=\s*["']/) || 
        line.match?(/secret\s*=\s*["']/) || 
        line.match?(/api_key\s*=\s*["']/)
      
      violations << {type: :future_tense, line: line_num, severity: :high} if
        line.match?(/\bI will\b/) ||
        line.match?(/\bwe will\b/) ||
        line.match?(/\blet's\b/) ||
        line.match?(/\bwe should\b/) ||
        line.match?(/\bgonna\b/)
      
      next if scanner_file && (line.include?("include?") || line.include?("match?"))
      
      violations << {type: :truncation, line: line_num, severity: :veto} if
        line.include?("...") ||
        line.include?("etc.") ||
        line.include?("rest of") ||
        line.include?("similar to")
    end
    
    Result.ok(violations)
  end
  
  def apply_fixes(file)
    fixable = @violations.count { |v| v[:severity] != :veto }
    fixable
  end
  
  def obvious_fix?
    return false if @violations.empty?
    @violations.size == 1 && @violations.first[:type] == :naming_inconsistency
  end
end

class CLI
  def initialize
    @master_result = Master.load
    
    if @master_result.err?
      puts UX.error(@master_result.error)
      puts "Run from directory with master.yml"
      exit 1
    end
    
    @master = @master_result.value
    @llm = LLMChat.new(@master)
    setup_completion
  end
  
  def run
    show_banner
    
    loop do
      input = Readline.readline("> ", true)&.strip
      break unless input
      next if input.empty?
      
      input.start_with?("/") ? handle_command(input[1..]) : handle_chat(input)
    end
  rescue Interrupt
    puts "\n" + UX.success("Goodbye")
  end
  
  private
  
  def show_banner
    puts "Master v#{VERSION}"
    puts "Framework: #{@master.data['version']}"
    llm_status = @llm.available? ? "connected" : "unavailable (set OPENROUTER_API_KEY)"
    puts "LLM: #{llm_status}"
    puts "Commands: #{COMMANDS.keys.map { |k| "/#{k}" }.join(', ')}"
    puts "Type /help or just chat naturally"
    puts
  end
  
  def setup_completion
    Readline.completion_proc = proc do |s|
      COMMANDS.keys.map { |c| "/#{c}" }.grep(/^#{Regexp.escape(s)}/)
    end
  end
  
  def handle_command(cmd)
    parts = cmd.split(/\s+/, 2)
    name = parts[0].to_sym
    arg = parts[1]
    
    name = COMMANDS.key(name.to_s) || name
    
    case name
    when :help then show_help
    when :scan then scan_command(arg)
    when :fix then fix_command(arg)
    when :validate then validate_command(arg)
    when :export then export_command(arg)
    when :status then status_command
    when :chat then chat_command(arg)
    when :model then model_command(arg)
    when :quit then exit
    else
      puts UX.error("Unknown: /#{name}")
      puts "Try /help"
    end
  end
  
  def handle_chat(msg)
    unless @llm.available?
      puts UX.warning("LLM not available. Set OPENROUTER_API_KEY environment variable.")
      puts "Get your key at: https://openrouter.ai/keys"
      return
    end
    
    print "Thinking... "
    result = @llm.ask_with_tools(msg)
    puts
    
    if result[:error]
      puts UX.error(result[:error])
    elsif result[:needs_confirmation]
      handle_confirmation(result)
    elsif result[:tool_result]
      puts "Tool: #{result[:tool]}"
      puts result[:tool_result][:result] || result[:tool_result][:error]
    else
      puts result[:content]
    end
  end
  
  def handle_confirmation(result)
    tool = result[:tool]
    params = result[:params]
    puts UX.warning("Action requires confirmation: #{tool}")
    puts "Params: #{params.inspect}"
    
    if UX.confirm?("Proceed")
      tool_obj = @llm.tools.find { |t| t.name == tool }
      output = tool_obj.execute(**params.transform_keys(&:to_sym).merge(confirmed: true))
      puts output[:result] || output[:error]
    else
      puts "Cancelled"
    end
  end
  
  def show_help
    models = @master.data.dig("llm", "models", "available")&.values&.flatten&.first(6)&.join(", ") || "claude-sonnet-4"
    
    puts <<~HELP
      Master v#{VERSION} - AI-Powered System Management
      
      Commands:
        /scan <file>       Scan file for violations
        /fix <file>        Auto-fix violations
        /validate <file>   Run full master validation
        /export [file]     Export governance as JSON
        /status            Show system status
        /chat <message>    Chat with AI (or just type without /)
        /model <name>      Switch model (fast, reasoning, coding, or model name)
        /quit              Exit
      
      Models: #{models}
      
      Aliases: #{COMMANDS.map { |k, v| "#{k}=#{v}" }.join(', ')}
      
      Examples:
        /scan cli.rb           Check for violations
        /validate master.yml   Self-validate master.yml
        list files in /etc     Natural language command
        /model fast            Switch to fast model
        /fix cli.rb            Auto-fix violations
    HELP
  end
  
  def scan_command(file)
    return puts UX.error("Usage: /scan <file>") unless file
    return puts UX.error("File not found: #{file}") unless File.exist?(file)
    
    engine = MasterEngine.new(@master)
    result = engine.send(:scan, file)
    
    if result.err?
      puts UX.error(result.error)
    elsif result.value.empty?
      puts UX.success("No violations found")
    else
      puts "Found #{result.value.size} violations:"
      result.value.each { |v| puts "  #{v[:type]} at line #{v[:line]} (#{v[:severity]})" }
    end
  end
  
  def fix_command(file)
    return puts UX.error("Usage: /fix <file>") unless file
    
    unless UX.confirm?("Apply automated fixes to #{file}")
      puts "Cancelled"
      return
    end
    
    puts UX.warning("Fix not fully implemented yet")
  end
  
  def validate_command(file)
    return puts UX.error("Usage: /validate <file>") unless file
    return puts UX.error("File not found: #{file}") unless File.exist?(file)
    
    engine = MasterEngine.new(@master)
    result = engine.converge(target: file)
    
    if result.err?
      puts UX.error(result.error)
    else
      data = result.value
      puts
      puts "MASTER VALIDATION RESULTS"
      puts
      puts "Iterations: #{data[:iterations]}"
      puts "Violations: #{data[:violations]}"
      puts "Converged: #{data[:converged] ? 'YES' : 'NO'}"
    end
  end
  
  def export_command(file)
    data = {
      version: VERSION,
      timestamp: Time.now.iso8601,
      master: @master.data
    }
    
    json = JSON.pretty_generate(data)
    
    if file
      File.write(file, json)
      puts UX.success("Exported to #{file}")
    else
      puts json
    end
  end
  
  def status_command
    puts "Status:"
    puts "  CLI Version: #{VERSION}"
    puts "  Framework: #{@master.data['version']}"
    puts "  Platform: #{@master.data.dig('platform', 'primary') || 'openbsd'}"
    puts "  LLM: #{@llm.available? ? 'connected' : 'unavailable'}"
    
    if @llm.available?
      models = @master.data.dig("llm", "models") || {}
      puts "  Default Model: #{models['default'] || 'claude-sonnet-4'}"
      puts "  History: #{@llm.history.size} messages"
    end
    
    tools_count = @llm.tools.size
    puts "  Tools: #{tools_count} available"
  end
  
  def chat_command(msg)
    return puts UX.error("Usage: /chat <message>") unless msg
    handle_chat(msg)
  end
  
  def model_command(model)
    return puts UX.error("Usage: /model <name>") unless model
    
    unless @llm.available?
      puts UX.error("LLM not available")
      return
    end
    
    result = @llm.switch_model(model)
    if result[:error]
      puts UX.error(result[:error])
    else
      puts UX.success(result[:result])
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV[0] == "--self-validate"
    puts "SELF-VALIDATION: master.yml through itself"
    puts
    
    master_result = Master.load
    if master_result.err?
      puts UX.error(master_result.error)
      exit 1
    end
    
    engine = MasterEngine.new(master_result.value)
    result = engine.converge(target: "master.yml")
    
    exit(result.value[:converged] ? 0 : 1)
  else
    CLI.new.run
  end
end