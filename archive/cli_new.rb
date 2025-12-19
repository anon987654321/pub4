#!/usr/bin/env ruby
# frozen_string_literal: true
# CONVERGENCE CLI v2.5.0 - Master.yml Integrated
# Platforms: OpenBSD, Cygwin, Zsh, Linux, macOS
# Security: pledge/unveil (OpenBSD), circuit breakers, input validation
# Merged: DeepSeek production implementation + original features

require "yaml"
require "json"
require "net/http"
require "uri"
require "fileutils"
require "shellwords"
require "open3"
require "timeout"

BEGIN {
  # OpenBSD Security Initialization
  if RUBY_PLATFORM =~ /openbsd/
    begin
      require "pledge"
      Pledge.pledge("stdio rpath wpath cpath inet dns proc exec prot_exec", nil) rescue nil
      if Pledge.respond_to?(:unveil)
        Pledge.unveil(ENV["HOME"], "rwc")
        Pledge.unveil("/tmp", "rwc")
        Pledge.unveil("/usr/local", "r")
        Pledge.unveil("/etc/ssl", "r")
        Pledge.unveil(nil, nil)
      end
      PLEDGE_AVAILABLE = true
    rescue LoadError
      PLEDGE_AVAILABLE = false
    end
  else
    PLEDGE_AVAILABLE = false
  end

  # Optional dependencies
  begin
    require "tty-prompt"
    require "tty-spinner"
    require "pastel"
    TTY_AVAILABLE = true
  rescue LoadError
    TTY_AVAILABLE = false
  end

  begin
    require "anthropic"
    ANTHROPIC_GEM = true
  rescue LoadError
    ANTHROPIC_GEM = false
  end

  begin
    require "ferrum"
    FERRUM_AVAILABLE = true
  rescue LoadError
    FERRUM_AVAILABLE = false
  end
}

# Structured Logging (DeepSeek pattern)
module Log
  def self.structured(level:, msg:, **context)
    entry = {
      timestamp: Time.now.iso8601(3),
      pid: $$,
      level: level,
      message: msg
    }.merge(context)
    $stderr.puts JSON.generate(entry)
  end

  def self.info(msg, **ctx) = structured(level: "INFO", msg: msg, **ctx)
  def self.warn(msg, **ctx) = structured(level: "WARN", msg: msg, **ctx)
  def self.error(msg, **ctx) = structured(level: "ERROR", msg: msg, **ctx)
  def self.fatal(msg, **ctx) = (structured(level: "FATAL", msg: msg, **ctx); exit 1)
  def self.debug(msg, **ctx) = structured(level: "DEBUG", msg: msg, **ctx) if ENV["DEBUG"]
end

# Circuit Breaker (DeepSeek pattern)
class CircuitBreaker
  class OpenError < StandardError; end

  def initialize(threshold: 5, timeout: 60)
    @failure_count = 0
    @threshold = threshold
    @timeout = timeout
    @last_failure = nil
    @state = :closed
  end

  def call
    raise OpenError, "circuit open (retry in #{retry_in}s)" if open?
    yield.tap { success }
  rescue => e
    failure
    raise
  end

  private

  def open? = @state == :open && Time.now - @last_failure < @timeout
  def retry_in = (@timeout - (Time.now - @last_failure)).ceil

  def success
    @failure_count = 0
    @state = :closed
  end

  def failure
    @failure_count += 1
    @last_failure = Time.now
    @state = :open if @failure_count >= @threshold
  end
end

# Exponential Backoff (DeepSeek pattern)
class RetryWithBackoff
  def self.call(max_attempts: 3, base_delay: 1)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue => e
      if attempts < max_attempts
        delay = base_delay * (2 ** (attempts - 1))
        Log.warn("retry #{attempts}/#{max_attempts} in #{delay}s: #{e.message}")
        sleep delay
        retry
      else
        raise
      end
    end
  end
end

# Configuration with Master.yml Integration
class Config
  class ConfigurationError < StandardError; end

  attr_reader :data, :master_config

  def initialize(config_path: nil)
    @config_path = config_path || resolve_canonical_path
    @master_config = load_master_yml
    @data = load_cli_config
    validate!
  end

  def api_key
    key = ENV["ANTHROPIC_API_KEY"] || @data["api_key"]
    return key if key && !key.empty?

    if FERRUM_AVAILABLE
      Log.info("no API key, using webchat fallback")
      nil
    else
      raise ConfigurationError, <<~ERROR
        missing API key
        set: export ANTHROPIC_API_KEY="sk-ant-api03-..."
        or install ferrum for webchat: gem install ferrum
        get key: https://console.anthropic.com/settings/keys
      ERROR
    end
  end

  def shell_interpreter
    @data["shell_interpreter"] || default_shell
  end

  def validate!
    errors = []

    errors << "invalid model" unless @data["model"]&.start_with?("claude-") || @data["model"] == "webchat"
    errors << "shell not executable: #{shell_interpreter}" unless File.executable?(shell_interpreter)
    errors << "invalid max_tokens" unless @data["max_tokens"].is_a?(Integer) && @data["max_tokens"].between?(1, 200_000)
    errors << "invalid temperature" unless @data["temperature"].is_a?(Numeric) && @data["temperature"].between?(0, 1)
    errors << "master.yml not found or invalid" unless @master_config

    raise ConfigurationError, "validation failed:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" if errors.any?

    Log.info("config validated", master_version: @master_config&.dig("framework", "version"))
  end

  def rules
    @rules ||= @master_config&.dig("framework", "enforcement", "tool_policy") || {}
  end

  private

  def resolve_canonical_path
    [
      File.expand_path("~/pub/master.yml"),
      File.join(Dir.pwd, "master.yml"),
      File.join(File.dirname(__FILE__), "master.yml")
    ].find { |path| File.exist?(path) } || File.expand_path("~/pub/master.yml")
  end

  def load_master_yml
    YAML.load_file(File.expand_path("~/pub/master.yml")) rescue nil
  end

  def load_cli_config
    if File.exist?(@config_path)
      YAML.load_file(@config_path)
    else
      default_config
    end
  rescue Psych::SyntaxError => e
    Log.error("config syntax error: #{e.message}")
    default_config
  end

  def default_config
    {
      "model" => "claude-3-5-sonnet-20241022",
      "max_tokens" => 8192,
      "temperature" => 0.7,
      "shell_interpreter" => default_shell
    }
  end

  def default_shell
    candidates = if RUBY_PLATFORM =~ /cygwin|mswin|mingw/
                   ["/usr/bin/zsh", "/bin/zsh", "/usr/bin/bash", ENV["SHELL"]]
                 else
                   ["/usr/local/bin/zsh", "/bin/zsh", "/usr/bin/zsh", "/bin/ksh", ENV["SHELL"]]
                 end
    candidates.compact.find { |s| File.executable?(s) } || "sh"
  end
end

# Rule Validator (Master.yml Compliant)
class RuleValidator
  class ValidationError < StandardError
    attr_reader :suggestion

    def initialize(message, suggestion: nil)
      super(message)
      @suggestion = suggestion
    end
  end

  def initialize(config)
    @config = config
  end

  def validate_command!(command)
    banned = ["python", "bash", "sed", "awk", "wc", "head", "tail", "find", "sudo"]

    banned.each do |tool|
      if command.match?(/\b#{Regexp.escape(tool)}\b/)
        suggestion = case tool
                     when "python" then "use ruby instead"
                     when "bash" then "use zsh instead"
                     when "wc" then 'use zsh: ${#${(f)"$(< file)"}}'
                     when "head", "tail" then "use zsh array slicing: ${lines[1,20]}"
                     when "sed", "awk" then "use ruby or zsh parameter expansion"
                     else "use allowed alternative"
                     end
        raise ValidationError.new("#{tool} not allowed per master.yml", suggestion: suggestion)
      end
    end
  end

  def validate_file!(path)
    forbidden = ["/etc/passwd", "/etc/shadow", "/root", "/etc/sudoers"]
    forbidden.each do |pattern|
      raise ValidationError.new("forbidden path: #{path}") if File.fnmatch(pattern, File.expand_path(path))
    end

    allowed = [ENV["HOME"], File.join(ENV["HOME"], "pub"), Dir.pwd, "/tmp"].compact.map { |p| File.expand_path(p) }
    normalized = File.expand_path(path)
    unless allowed.any? { |ap| normalized.start_with?(ap) }
      raise ValidationError.new("path outside allowed directories: #{path}")
    end
  end
end

# Minimal CLI (placeholder for full implementation)
class CLI
  def initialize
    @config = Config.new
    @validator = RuleValidator.new(@config)
    Log.info("CLI initialized", master_version: @config.master_config&.dig("framework", "version"))
  end

  def run(args)
    case args.first
    when "--check" then check_config
    when "--help", "-h" then show_help
    else
      puts "CONVERGENCE CLI v2.5.0"
      puts "Master.yml: #{@config.master_config&.dig('framework', 'version') || 'not loaded'}"
      puts "Shell: #{@config.shell_interpreter}"
      puts "Security: #{PLEDGE_AVAILABLE ? 'pledge+unveil' : 'standard'}"
    end
  rescue => e
    Log.fatal("error: #{e.message}")
  end

  private

  def check_config
    puts "✓ Configuration valid"
    puts "✓ Master.yml loaded: v#{@config.master_config&.dig('framework', 'version')}"
    puts "✓ Shell: #{@config.shell_interpreter}"
  end

  def show_help
    puts <<~HELP
      CONVERGENCE CLI v2.5.0 - Master.yml Integrated
      
      Usage:
        ./cli.rb [options]
      
      Options:
        --check       Validate configuration
        --help, -h    Show this help
      
      Environment:
        ANTHROPIC_API_KEY    API key for Claude
        DEBUG                Enable debug logging
    HELP
  end
end

# Entry point
if __FILE__ == $0
  CLI.new.run(ARGV)
end
