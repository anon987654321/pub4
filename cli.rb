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

# Constants hoisted for easy reference and maintainability
MAX_STDOUT_SIZE = 10_000
MAX_STDERR_SIZE = 4000
MAX_FILE_SIZE = 100_000
DEFAULT_TIMEOUT = 30
DEFAULT_MODEL = "deepseek/deepseek-r1"
CONFIG_FILE_PERMISSIONS = 0o600

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
      cfg.model = data["model"] if data["model"]
      cfg.access_level = data["access_level"]&.to_sym if data["access_level"]
    end
    cfg
  end

  def save
    FileUtils.mkdir_p(File.dirname(PATH))
    File.write(PATH, YAML.dump({ "model" => model, "access_level" => access_level.to_s }))
    File.chmod(CONFIG_FILE_PERMISSIONS, PATH)
  end
end

# Decision support module - calculate weighted scores
module DecisionSupport
  # Calculate weighted score for multiple options
  # @param options [Hash] Hash of option_name => factors hash
  # @param weights [Hash] Hash of factor_name => weight (should sum to 1.0)
  # @return [Hash] Hash of option_name => score
  # @example
  #   options = {
  #     "Option A" => { speed: 9, safety: 7, maintainability: 8 },
  #     "Option B" => { speed: 5, safety: 10, maintainability: 9 }
  #   }
  #   weights = { speed: 0.3, safety: 0.5, maintainability: 0.2 }
  #   scores = DecisionSupport.calculate_weights(options, weights)
  #   # => { "Option A" => 7.7, "Option B" => 8.0 }
  def self.calculate_weights(options, weights)
    options.transform_values do |factors|
      factors.sum { |factor, value| value * (weights[factor] || 0) }.round(2)
    end
  end

  # Select best option based on weighted scores
  # @param options [Hash] Hash of option_name => factors hash
  # @param weights [Hash] Hash of factor_name => weight
  # @return [Array] [best_option_name, score, all_scores]
  def self.select_best(options, weights)
    scores = calculate_weights(options, weights)
    best = scores.max_by { |_name, score| score }
    [best[0], best[1], scores]
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

# Main CLI
class CLI
  def initialize
    @config = Config.load
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
    when "help"   then @ui.show_help
    when "level"  then switch_level(parts[1])
    when "export" then export_governance(parts[1])
    when "quit"   then exit
    else @ui.show_error("Unknown command: /#{parts[0]}")
    end
  end

  def handle_msg(msg)
    key = ENV["OPENROUTER_API_KEY"]
    unless key
      @ui.show_error("Set OPENROUTER_API_KEY to chat with LLM")
      return
    end
    @ui.show_info("[LLM integration pending]")
  end

  def switch_level(str)
    return @ui.show_error("Usage: /level [sandbox|user|admin]") unless str
    sym = str.to_sym
    return @ui.show_error("Invalid level") unless %i[sandbox user admin].include?(sym)

    @config.access_level = sym
    @config.save
    OpenBSDSecurity.apply(sym)
    @ui.show_success("Level → #{sym}")
  end

  def export_governance(format_arg)
    format = format_arg&.downcase || "json"
    return @ui.show_error("Only JSON format supported currently") unless format == "json"

    begin
      exporter = GovernanceExporter.new
      output = exporter.export_to_json
      filename = "governance_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      File.write(filename, output)
      @ui.show_success("Exported governance to #{filename}")
    rescue => e
      @ui.show_error("Export failed: #{e.message}")
    end
  end
end

# UI Handler - decoupled from business logic
class UIHandler
  def show_welcome(version, level)
    puts "Convergence v#{version} – #{level} level"
    puts "Type /help or message"
  end

  def show_goodbye
    puts "\nGoodbye"
  end

  def show_help
    puts <<~HELP
      Commands:
        /help              Show this help
        /level [mode]      Set access: sandbox, user, admin
        /export [format]   Export governance (json)
        /quit              Exit
    HELP
  end

  def show_error(message)
    puts "Error: #{message}"
  end

  def show_info(message)
    puts message
  end

  def show_success(message)
    puts message
  end
end

# Governance exporter for JSON output
class GovernanceExporter
  MASTER_FILE = File.join(__dir__, "master.yml")

  def export_to_json
    data = load_governance
    export_structure = build_export_structure(data)
    JSON.pretty_generate(export_structure)
  end

  private

  def load_governance
    YAML.safe_load_file(MASTER_FILE)
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

CLI.new.run if __FILE__ == $0
