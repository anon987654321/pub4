#!/usr/bin/env ruby
# frozen_string_literal: true

# Convergence CLI v17.1.0 – secure LLM-assisted dev tool
# Per master.yml v17.0.0 governance

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "open3"
require "timeout"
require "io/console"
require "readline"
require "pathname"
require "time"

VERSION = "17.1.0"
OPENBSD = RUBY_PLATFORM.include?("openbsd")
GOVERNANCE_VERSION = "17.0.0"
CONFIG_SCHEMA_VERSION = "2.0.0"

# Constants hoisted for easy reference and maintainability
MAX_STDOUT_SIZE = 10_000
MAX_STDERR_SIZE = 4000
MAX_FILE_SIZE = 100_000
DEFAULT_TIMEOUT = 30
DEFAULT_MODEL = "deepseek/deepseek-r1"
CONFIG_FILE_PERMISSIONS = 0o600

# Governance enforcement engine
class Governance
  attr_reader :master_yml, :metrics
  
  def initialize(master_yml_path: "master.yml")
    @master_yml = load_master_yml(master_yml_path)
    @metrics = {}
  end
  
  def calculate_weights(files: [])
    return { correctness: 0.0, maintainability: 0.0, security: 0.0, performance: 0.0, consistency: 0.0 } if files.empty?
    
    scores = files.map do |file|
      next unless File.exist?(file)
      content = File.read(file)
      
      {
        correctness: calculate_correctness_score(content),
        maintainability: calculate_maintainability_score(content),
        security: calculate_security_score(content),
        performance: calculate_performance_score(content),
        consistency: calculate_consistency_score(content)
      }
    end.compact
    
    return { correctness: 0.0, maintainability: 0.0, security: 0.0, performance: 0.0, consistency: 0.0 } if scores.empty?
    
    total = scores.size.to_f
    {
      correctness: (scores.sum { |s| s[:correctness] } / total).round(2),
      maintainability: (scores.sum { |s| s[:maintainability] } / total).round(2),
      security: (scores.sum { |s| s[:security] } / total).round(2),
      performance: (scores.sum { |s| s[:performance] } / total).round(2),
      consistency: (scores.sum { |s| s[:consistency] } / total).round(2)
    }
  end
  
  def export_json
    {
      version: VERSION,
      governance_version: GOVERNANCE_VERSION,
      timestamp: Time.now.iso8601,
      metrics: @metrics,
      rules: {
        principles: extract_principles,
        thresholds: extract_thresholds,
        axioms: extract_axioms
      }
    }
  end
  
  private
  
  def load_master_yml(path)
    return {} unless File.exist?(path)
    YAML.safe_load_file(path, permitted_classes: [Symbol])
  rescue => e
    warn "Failed to load master.yml: #{e.message}" if ENV["DEBUG"]
    {}
  end
  
  def extract_principles
    @master_yml.dig("rules", "principles") || []
  end
  
  def extract_thresholds
    @master_yml.dig("rules", "thresholds") || {}
  end
  
  def extract_axioms
    @master_yml.dig("axioms", "foundation") || []
  end
  
  def calculate_correctness_score(content)
    score = 100.0
    score -= 20 if content.match?(/TODO|FIXME|XXX/)
    score -= 30 if content.match?(/raise\s+NotImplementedError/)
    score -= 10 if content.match?(/rescue\s*$/)
    [score, 0].max
  end
  
  def calculate_maintainability_score(content)
    lines = content.lines
    score = 100.0
    score -= 10 if lines.size > 300
    
    method_length = 0
    in_method = false
    lines.each do |line|
      if line.match?(/^\s*def\s+\w+/)
        in_method = true
        method_length = 1
      elsif line.match?(/^\s*end\s*$/) && in_method
        score -= 5 if method_length > 20
        in_method = false
        method_length = 0
      elsif in_method
        method_length += 1
      end
    end
    
    score -= 10 if content.scan(/def\s+\w+\(([^)]*)\)/).any? { |m| m[0].split(",").size > 3 }
    [score, 0].max
  end
  
  def calculate_security_score(content)
    score = 100.0
    score -= 50 if content.match?(/password\s*=\s*['"][^'"]{1,}['"]/) && !content.match?(/password\s*=\s*['"]['"]/)
    score -= 50 if content.match?(/api_key\s*=\s*['"][^'"]{1,}['"]/) && !content.match?(/api_key\s*=\s*['"]['"]/)
    score -= 50 if content.match?(/sk-[a-zA-Z0-9]{32,}/) || content.match?(/ghp_[a-zA-Z0-9]{36}/)
    score -= 20 if content.match?(/eval\(/)
    score -= 20 if content.match?(/system\(/)
    [score, 0].max
  end
  
  def calculate_performance_score(content)
    score = 100.0
    score -= 10 if content.match?(/\.each\s*\{.*\.each/)
    score -= 5 if content.match?(/sleep\(/)
    [score, 0].max
  end
  
  def calculate_consistency_score(content)
    score = 100.0
    score -= 20 if content.match?(/[A-Z][a-z]+[A-Z]/) && !content.match?(/class\s+[A-Z]/)
    score -= 10 if content.match?(/-\w/)
    [score, 0].max
  end
end

# Migration engine for schema versioning
class Migration
  def self.migrate_config(config_path:, from_version:, to_version:)
    return unless File.exist?(config_path)
    
    data = YAML.safe_load_file(config_path) || {}
    
    case [from_version, to_version]
    when ["1.0.0", "2.0.0"]
      migrate_v1_to_v2(data)
    else
      warn "Unknown migration path: #{from_version} -> #{to_version}" if ENV["DEBUG"]
      data
    end
  end
  
  def self.migrate_v1_to_v2(data)
    data["schema_version"] = "2.0.0"
    data["model"] ||= "deepseek/deepseek-r1"
    data["access_level"] ||= "user"
    data
  end
end

# Decision support module - calculate weighted scores
module DecisionSupport
  def self.calculate_weights(options, weights)
    options.transform_values do |factors|
      factors.sum { |factor, value| value * (weights[factor] || 0) }.round(2)
    end
  end

  def self.select_best(options, weights)
    scores = calculate_weights(options, weights)
    best = scores.max_by { |_name, score| score }
    [best[0], best[1], scores]
  end
end

# OpenBSD FFI security module - loaded conditionally
module OpenBSDSecurity
  @available = false

  class << self
    attr_reader :available

    def setup
      return unless OPENBSD
      require "ffi"
      extend FFI::Library
      ffi_lib FFI::Library::LIBC
      attach_function :unveil, [:string, :string], :int
      attach_function :pledge, [:string, :string], :int
      @available = true
    rescue LoadError, FFI::NotFoundError => e
      warn "OpenBSD security unavailable: #{e.message}" if ENV["DEBUG"]
      @available = false
    end

    def apply(level)
      return unless @available

      paths = case level
              when :sandbox then [Dir.pwd, "/tmp"]
              when :user    then [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"]
              else               nil
              end

      unveil_paths(paths)
      pledge("stdio rpath wpath cpath inet dns proc exec fattr", nil)
    rescue => e
      warn "Security apply failed: #{e.message}" if ENV["DEBUG"]
    end

    private

    def unveil_paths(paths)
      map = if paths.nil?
              { ENV.fetch("HOME", "/") => "rwc", "/tmp" => "rwc", "/usr" => "rx", "/etc" => "r", "/var" => "rwc" }
            else
              paths.each_with_object({}) { |p, h| h[p] = "rwc" if Dir.exist?(p) }
                   .merge("/usr" => "rx", "/etc" => "r")
            end

      map.each { |p, perms| unveil(p, perms) }
      unveil(nil, nil)
    end
  end
end

OpenBSDSecurity.setup

# Configuration - persisted non-secrets only
class Config
  PATH = File.expand_path("~/.convergence/config.yml").freeze

  attr_accessor :model, :access_level

  def self.load
    cfg = new
    cfg.model = DEFAULT_MODEL
    cfg.access_level = :user

    if File.exist?(PATH)
      data = YAML.safe_load_file(PATH) || {}
      
      if data["schema_version"] != CONFIG_SCHEMA_VERSION
        data = Migration.migrate_config(
          config_path: PATH,
          from_version: data["schema_version"] || "1.0.0",
          to_version: CONFIG_SCHEMA_VERSION
        )
      end
      
      cfg.model = data["model"] if data["model"]
      cfg.access_level = data["access_level"]&.to_sym if data["access_level"]
    end
    cfg
  end

  def save
    FileUtils.mkdir_p(File.dirname(PATH))
    data = {
      "schema_version" => CONFIG_SCHEMA_VERSION,
      "model" => model,
      "access_level" => access_level.to_s
    }
    File.write(PATH, YAML.dump(data))
    File.chmod(CONFIG_FILE_PERMISSIONS, PATH)
  end
  
  def to_json(*args)
    {
      model: model,
      access_level: access_level,
      schema_version: CONFIG_SCHEMA_VERSION
    }.to_json(*args)
  end
end

# Shell execution tool - zsh only per master.yml
class ShellTool
  ZSH_PATHS = %w[/usr/local/bin/zsh /bin/zsh].freeze

  def execute(command:, timeout: 30)
    shell = ZSH_PATHS.find { |p| File.executable?(p) }
    return { error: "zsh not found" } unless shell

    prefix = 'emulate -L zsh; set -euo pipefail; '

    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(shell, "-c", prefix + command)
      {
        stdout: stdout[0..MAX_STDOUT_SIZE],
        stderr: stderr[0..MAX_STDERR_SIZE],
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

# File sandbox tool - enforces access levels
class FileTool
  def initialize(base_path:, access_level:)
    @base = File.expand_path(base_path)
    @level = access_level
  end

  def read(path:)
    safe = enforce!(path)
    return { error: "not found" } unless File.exist?(safe)
    { content: File.read(safe)[0..MAX_FILE_SIZE], size: File.size(safe), path: safe }
  rescue => e
    { error: e.message }
  end

  def write(path:, content:)
    safe = enforce!(path)
    FileUtils.mkdir_p(File.dirname(safe))
    File.write(safe, content)
    { success: true, bytes: content.bytesize }
  rescue => e
    { error: e.message }
  end

  private

  def enforce!(path)
    expanded = File.expand_path(path, @base)
    allowed = case @level
              when :sandbox then [Dir.pwd, "/tmp"]
              when :user    then [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"]
              else               nil
              end
    return expanded if allowed.nil?
    raise SecurityError, "access denied" unless allowed.any? { |p| expanded.start_with?("#{p}/") || expanded == p }
    expanded
  end
end

# UI Handler - decoupled from business logic
class UIHandler
  def show_welcome(version, level)
    puts "Convergence v#{version} – #{level} level"
    puts "Type /help for commands or message for LLM chat"
    puts
  end

  def show_goodbye
    puts "\nGoodbye"
  end

  def show_help(version)
    puts <<~HELP
      Convergence CLI v#{version} - Constitutional AI Governance Tool
      
      Commands:
        /help                 Show this help message
        /level [mode]         Set access level: sandbox, user, or admin
                              • sandbox: restricted to cwd and /tmp
                              • user: access to $HOME, cwd, and /tmp
                              • admin: full system access (use with caution)
        /export [file]        Export governance state as JSON
                              • Outputs to stdout if no file specified
                              • Example: /export report.json
        /weights              Calculate quality weights for current directory
                              • Analyzes code correctness, maintainability, security
        /codify <text>        Auto-codify wishlist items to YAML
                              • Extracts bullet/numbered lists
                              • Saves to .sessions/wishlist_*.yml
        /quiet                Toggle quiet mode (suppress logs)
        /version              Show version and governance information
        /quit                 Exit the application
      
      Examples:
        > /level sandbox       # Switch to sandbox mode
        > /export out.json     # Export governance report
        > /weights             # Show quality metrics
        > /codify "- Add feature X\\n- Fix bug Y"  # Codify wishlist
      
      Natural Language (requires OPENROUTER_API_KEY):
        > show me the config
        > run the tests
        > what files are in this directory
    HELP
  end

  def show_error(message)
    puts "✗ #{message}"
  end

  def show_info(message)
    puts message
  end

  def show_success(message)
    puts "✓ #{message}"
  end
end

# Governance exporter for JSON output
class GovernanceExporter
  MASTER_FILE = "master.yml"

  def export_to_json
    data = load_governance
    export_structure = build_export_structure(data)
    JSON.pretty_generate(export_structure)
  end

  private

  def load_governance
    return {} unless File.exist?(MASTER_FILE)
    YAML.safe_load_file(MASTER_FILE)
  rescue => e
    warn "Failed to load governance: #{e.message}" if ENV["DEBUG"]
    {}
  end

  def build_export_structure(data)
    {
      export_metadata: {
        timestamp: Time.now.utc.iso8601,
        exporter_version: VERSION,
        format_version: "1.0"
      },
      governance_version: data.dig("meta", "version") || "unknown",
      sections: {
        meta: data["meta"],
        style_constraints: data["style_constraints"],
        rules: data["rules"],
        axioms: data["axioms"],
        thresholds: extract_thresholds(data),
        testing: data["testing"],
        security: data["security"],
        defect_catalog: data["defect_catalog"]
      }
    }
  end

  def extract_thresholds(data)
    data.dig("rules", "thresholds") || {}
  end
end

# Main CLI
class CLI
  attr_reader :quiet
  
  def initialize(quiet: false)
    @quiet = quiet
    @config = Config.load
    @governance = Governance.new
    OpenBSDSecurity.apply(@config.access_level)
    @tools = setup_tools
    @ui = UIHandler.new
  end

  def run
    @ui.show_welcome(VERSION, @config.access_level)

    loop do
      input = Readline.readline("> ", true)&.strip
      break unless input
      next if input.empty?
      input.start_with?("/") ? handle_cmd(input[1..]) : handle_msg(input)
    end
  rescue Interrupt
    @ui.show_goodbye
  end

  private

  def setup_tools
    [
      ShellTool.new,
      FileTool.new(base_path: Dir.pwd, access_level: @config.access_level)
    ]
  end

  def handle_cmd(cmd)
    parts = cmd.strip.split(/\s+/, 2)
    case parts[0]
    when "help"    then @ui.show_help(VERSION)
    when "level"   then switch_level(parts[1])
    when "export"  then export_governance(parts[1])
    when "weights" then show_weights
    when "version" then show_version
    when "quiet"   then toggle_quiet
    when "codify"  then chat_codification(parts[1])
    when "quit"    then exit
    else @ui.show_error("Unknown command: /#{parts[0]} (try /help)")
    end
  end

  def handle_msg(msg)
    key = ENV["OPENROUTER_API_KEY"]
    unless key
      puts "⚠ Set OPENROUTER_API_KEY environment variable to enable LLM chat"
      puts "Example: export OPENROUTER_API_KEY='your-key-here'"
      return
    end
    
    if auto_detect_wishlist(msg)
      log "[Auto-detected wishlist - use /codify to process]"
    end
    
    @ui.show_info("[LLM integration pending - will support natural language code operations]")
  end

  def switch_level(str)
    return @ui.show_error("Usage: /level [sandbox|user|admin]") unless str
    sym = str.to_sym
    return @ui.show_error("Invalid level") unless %i[sandbox user admin].include?(sym)

    @config.access_level = sym
    @config.save
    OpenBSDSecurity.apply(sym)
    @ui.show_success("Access level changed to: #{sym}")
  end
  
  def export_governance(file)
    if file && !file.start_with?("/tmp/")
      expanded = File.expand_path(file)
      allowed = case @config.access_level
                when :sandbox then [Dir.pwd, "/tmp"]
                when :user    then [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"]
                else               nil
                end
      
      unless allowed.nil? || allowed.any? { |p| expanded.start_with?("#{p}/") || expanded == p }
        @ui.show_error("Export denied: path outside allowed directories")
        return
      end
    end
    
    exporter = GovernanceExporter.new
    governance_data = exporter.export_to_json
    
    combined_data = {
      version: VERSION,
      governance_version: GOVERNANCE_VERSION,
      timestamp: Time.now.iso8601,
      config: {
        model: @config.model,
        access_level: @config.access_level
      },
      governance: JSON.parse(governance_data)
    }
    
    json = JSON.pretty_generate(combined_data)
    
    if file
      File.write(file, json)
      @ui.show_success("Exported governance state to: #{file}")
    else
      puts json
    end
  rescue => e
    @ui.show_error("Export failed: #{e.message}")
  end
  
  def show_weights
    ruby_files = Dir.glob("**/*.rb").reject { |f| f.start_with?("vendor/") }
    
    if ruby_files.empty?
      puts "No Ruby files found in current directory"
      return
    end
    
    puts "Analyzing #{ruby_files.size} Ruby files..."
    weights = @governance.calculate_weights(files: ruby_files)
    
    puts "\nQuality Weights:"
    puts "  Correctness:      #{weights[:correctness]}%"
    puts "  Maintainability:  #{weights[:maintainability]}%"
    puts "  Security:         #{weights[:security]}%"
    puts "  Performance:      #{weights[:performance]}%"
    puts "  Consistency:      #{weights[:consistency]}%"
    puts
    
    avg = weights.values.sum / weights.size
    status = avg >= 90 ? "✓ Excellent" : avg >= 70 ? "⚠ Good" : "✗ Needs Improvement"
    puts "Overall: #{avg.round(2)}% (#{status})"
  rescue => e
    @ui.show_error("Analysis failed: #{e.message}")
  end
  
  def show_version
    puts <<~VERSION_INFO
      Convergence CLI
      Version:            #{VERSION}
      Governance Schema:  #{GOVERNANCE_VERSION}
      Config Schema:      #{CONFIG_SCHEMA_VERSION}
      Platform:           #{RUBY_PLATFORM}
      OpenBSD Security:   #{OpenBSDSecurity.available ? "✓ Available" : "✗ Unavailable"}
      Ruby Version:       #{RUBY_VERSION}
    VERSION_INFO
  end
  
  def log(msg)
    puts msg unless @quiet
  end
  
  def toggle_quiet
    @quiet = !@quiet
    puts "Quiet mode: #{@quiet ? 'on' : 'off'}"
  end
  
  def auto_detect_wishlist(msg)
    msg.match?(/wishlist|todo|implement|add.*feature/i)
  end
  
  def chat_codification(text)
    return log "Usage: /codify <text>" unless text
    
    items = extract_wishlist_items(text)
    return log "No wishlist items found" if items.empty?
    
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    yaml_output = codify_to_yaml(items, timestamp)
    log "\n--- Generated YAML ---"
    log yaml_output
    log "--- End YAML ---\n"
    
    save_codification(yaml_output, timestamp)
  end
  
  def extract_wishlist_items(text)
    items = []
    # Match bullet points: - item or * item
    text.scan(/^[-*]\s+(.+)$/).each do |match|
      items << match[0].strip if match[0]
    end
    # Match numbered lists: 1. item
    text.scan(/^\d+\.\s+(.+)$/).each do |match|
      items << match[0].strip if match[0]
    end
    items
  end
  
  def codify_to_yaml(items, timestamp = Time.now.strftime("%Y%m%d_%H%M%S"))
    output = {
      "wishlist_codification" => {
        "generated_at" => timestamp,
        "items" => items.map.with_index(1) do |item, idx|
          {
            "id" => idx,
            "description" => item,
            "status" => "pending",
            "priority" => "normal"
          }
        end
      }
    }
    YAML.dump(output)
  end
  
  def save_codification(yaml_content, timestamp = Time.now.strftime("%Y%m%d_%H%M%S"))
    dir = ".sessions"
    
    begin
      FileUtils.mkdir_p(dir)
      filename = "#{dir}/wishlist_#{timestamp}.yml"
      File.write(filename, yaml_content)
      log "Saved to: #{filename}"
    rescue => e
      log "Error saving: #{e.message}"
    end
  end
end

CLI.new(quiet: ENV["QUIET"] == "true").run if __FILE__ == $0
