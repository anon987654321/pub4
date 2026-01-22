#!/usr/bin/env ruby
# frozen_string_literal: true

# Convergence CLI v17.3.0 – secure LLM-assisted dev tool

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
require "ffi"

# ── OpenBSD security (pledge/unveil) ─────────────────────────────────
def apply_openbsd_security(level = :user)
  return unless RUBY_PLATFORM.include?("openbsd")

  module OpenBSD
    extend FFI::Library
    ffi_lib FFI::Library::LIBC
    attach_function :unveil, [:string, :string], :int
    attach_function :pledge, [:string, :string], :int
  end

  paths = case level
          when :sandbox then [Dir.pwd, "/tmp"]
          when :user    then [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"]
          else               :all
          end

  unveil_map = if paths == :all
    { ENV.fetch("HOME", "/") => "rwc", "/tmp" => "rwc", "/usr" => "rx", "/etc" => "r", "/var" => "rwc" }
  else
    paths.each_with_object({}) { |p, h| h[p] = "rwc" if Dir.exist?(p) }
         .merge("/usr" => "rx", "/etc" => "r")
  end

  unveil_map.each { |p, perms| OpenBSD.unveil(p, perms) }
  OpenBSD.unveil(nil, nil)
  OpenBSD.pledge("stdio rpath wpath cpath inet dns proc exec fattr", nil)
rescue LoadError, FFI::NotFoundError
  warn "OpenBSD security unavailable" if ENV["DEBUG"]
end

# ── Minimal config (env vars + persisted non-secrets) ─────────────────
class Config
  PATH = File.expand_path("~/.convergence/config.yml").freeze

  attr_accessor :model, :access_level

  def self.load
    new.tap do |c|
      next unless File.exist?(PATH)
      data = YAML.safe_load_file(PATH) || {}
      c.model        = data["model"] || "deepseek/deepseek-r1"
      c.access_level = data["access_level"]&.to_sym || :user
    end
  end

  def save
    FileUtils.mkdir_p(File.dirname(PATH))
    File.write(PATH, YAML.dump({ "model" => model, "access_level" => access_level.to_s }))
    File.chmod(0o600, PATH)
  end
end

# ── Strict zsh shell tool ─────────────────────────────────────────────
class ShellTool
  def execute(command:, timeout: 30)
    shell = %w[/usr/local/bin/zsh /bin/zsh].find { |p| File.executable?(p) } ||
            return({ error: "zsh not found" })

    prefix = 'emulate -L zsh; set -euo pipefail; ' \
             'trap \'e=$?; echo "zsh error (code $e) at line ${LINENO:-?}" >&2; exit $e\' ERR; '

    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(shell, "-c", prefix + command)
      { stdout: stdout[0..10000], stderr: stderr[0..4000], exit_code: status.exitstatus, success: status.success? }
    end
  rescue Timeout::Error
    { error: "timeout after #{timeout}s" }
  rescue => e
    { error: e.message }
  end
end

# ── File sandbox tool (core security) ─────────────────────────────────
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
    paths = case @level
            when :sandbox then [Dir.pwd, "/tmp"]
            when :user    then [ENV.fetch("HOME", "/tmp"), Dir.pwd, "/tmp"]
            else               :all
            end
    return expanded if paths == :all
    raise SecurityError, "access denied" unless paths.any? { |p| expanded.start_with?("#{p}/") || expanded == p }
    expanded
  end
end

# ── CLI entry ──────────────────────────────────────────────────────────
class CLI
  def initialize
    @config = Config.load
    apply_openbsd_security(@config.access_level)
    @client = setup_client
    @tools  = setup_tools
  end

  def run
    puts "Convergence v17.3.0 – #{@config.access_level} level"
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

  def setup_client
    key = ENV["OPENROUTER_API_KEY"] || abort("Missing OPENROUTER_API_KEY")
    RubyLLM::Client.new(api_key: key, default_model: @config.model)
  end

  def setup_tools
    base = Dir.pwd
    level = @config.access_level
    [
      ShellTool.new,
      FileTool.new(base_path: base, access_level: level)
      # Add GitTool, etc. as needed
    ]
  end

  def handle_cmd(cmd)
    parts = cmd.strip.split(/\s+/, 2)
    case parts[0]
    when "help"   then puts "Commands: /help, /quit, /level [sandbox|user|admin]"
    when "level"  then switch_level(parts[1])
    when "quit"   then exit
    else puts "Unknown command"
    end
  end

  def handle_msg(msg)
    response = @client.chat(messages: [{ role: "user", content: msg }])
    puts response.content
  end

  def switch_level(str)
    sym = str.to_sym
    return puts "Invalid" unless %i[sandbox user admin].include?(sym)

    @config.access_level = sym
    @config.save
    apply_openbsd_security(sym)
    puts "Level → #{sym}"
  end
end

CLI.new.run if __FILE__ == $0