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

VERSION = "17.1.0"
OPENBSD = RUBY_PLATFORM.include?("openbsd")

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
    cfg.model = "deepseek/deepseek-r1"
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
    File.chmod(0o600, PATH)
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
        stdout: stdout[0..10_000],
        stderr: stderr[0..4000],
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
    { content: File.read(safe)[0..100_000], size: File.size(safe), path: safe }
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
  end

  def run
    puts "Convergence v#{VERSION} – #{@config.access_level} level"
    puts "Type /help or message"

    loop do
      input = Readline.readline("> ", true)&.strip
      break unless input
      next if input.empty?
      input.start_with?("/") ? handle_cmd(input[1..]) : handle_msg(input)
    end
  rescue Interrupt
    puts "\nGoodbye"
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
    when "help"  then show_help
    when "level" then switch_level(parts[1])
    when "quit"  then exit
    else puts "Unknown: /#{parts[0]}"
    end
  end

  def handle_msg(msg)
    key = ENV["OPENROUTER_API_KEY"]
    unless key
      puts "Set OPENROUTER_API_KEY to chat with LLM"
      return
    end
    puts "[LLM integration pending]"
  end

  def show_help
    puts <<~HELP
      Commands:
        /help              Show this help
        /level [mode]      Set access: sandbox, user, admin
        /quit              Exit
    HELP
  end

  def switch_level(str)
    return puts "Usage: /level [sandbox|user|admin]" unless str
    sym = str.to_sym
    return puts "Invalid level" unless %i[sandbox user admin].include?(sym)

    @config.access_level = sym
    @config.save
    OpenBSDSecurity.apply(sym)
    puts "Level → #{sym}"
  end
end

CLI.new.run if __FILE__ == $0
