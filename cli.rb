
#!/usr/bin/env ruby
# frozen_string_literal: true

# Convergence CLI v0.3.0
# Constitutional AI Governance for Development
# NEW in v0.3: OpenRouter API, ProfileManager, SessionTimer, pub4 refactoring
# Zero external dependencies (stdlib only, ferrum optional)

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
require "digest"
require "time"
require "logger"

VERSION = "0.3.0"

# Platform detection constants
OPENBSD = RUBY_PLATFORM.include?("openbsd")
LINUX = RUBY_PLATFORM.include?("linux")
CYGWIN = RUBY_PLATFORM.include?("cygwin") || RUBY_PLATFORM.include?("mingw")
TERMUX = ENV['PREFIX']&.include?('com.termux') || false
MACOS = RUBY_PLATFORM.include?("darwin")

# Platform detection and classification
module Platform
  @platform = nil

  def self.detect
    @platform ||= begin
      type = if TERMUX
               :termux
             elsif CYGWIN
               :cygwin
             elsif OPENBSD
               :openbsd
             elsif MACOS
               :macos
             elsif LINUX
               :linux
             else
               :unknown
             end

      security = case type
                 when :openbsd then :unveil_pledge
                 when :linux then :seccomp
                 when :cygwin then :acl
                 else :none
                 end

      { type: type, security: security }
    end
  end
  
  def self.type
    detect[:type]
  end
  
  def self.security
    detect[:security]
  end
  
  def self.openbsd?
    type == :openbsd
  end
  
  def self.security_available?
    security != :none
  end
end

# NEW in v0.3: Cross-platform path resolution
module Paths
  # Base paths
  HOME = ENV.fetch("HOME") { ENV.fetch("USERPROFILE", "/tmp") }
  CONFIG_DIR = File.expand_path("~/.convergence")
  MASTER_FILE = File.join(CONFIG_DIR, "master.yml")
  CONFIG_FILE = File.join(CONFIG_DIR, "config.yml")
  LOG_DIR = File.join(CONFIG_DIR, "logs")
  BACKUP_DIR = File.join(CONFIG_DIR, "backups")

  # Platform-specific path resolution
  DEFAULTS = {
    termux: {
      samples: "/sdcard/music/samples",
      rails: "/data/data/com.termux/files/home/rails",
      logs: "/data/data/com.termux/files/home/.convergence/logs",
      config: "/data/data/com.termux/files/home/.convergence"
    },
    cygwin: {
      samples: "/cygdrive/c/Users/#{ENV['USER']}/Music/samples",
      rails: "#{HOME}/rails",
      logs: "#{HOME}/.convergence/logs",
      config: "#{HOME}/.convergence"
    },
    openbsd: {
      samples: "#{HOME}/music/samples",
      rails: "/var/www",
      logs: "#{HOME}/.convergence/logs",
      config: "#{HOME}/.convergence"
    },
    linux: {
      samples: "#{HOME}/music/samples",
      rails: "#{HOME}/rails",
      logs: "#{HOME}/.convergence/logs",
      config: "#{HOME}/.convergence"
    },
    macos: {
      samples: "#{HOME}/Music/samples",
      rails: "#{HOME}/rails",
      logs: "#{HOME}/.convergence/logs",
      config: "#{HOME}/.convergence"
    }
  }.freeze

  def self.for(key)
    platform = Platform.type
    path = DEFAULTS.dig(platform, key) || "#{HOME}/#{key}"
    
    # Expand environment variables
    path = path.gsub(/\$\{?(\w+)\}?/) { |match| ENV[$1] || match }
    
    File.expand_path(path)
  end
  
  def self.ensure_exists(*paths)
    paths.each do |path|
      FileUtils.mkdir_p(path) unless Dir.exist?(path)
      File.chmod(0700, path) if Dir.exist?(path)
    end
  end
end

# OpenBSD security using pledge/unveil via FFI
module OpenBSDSecurity
  @available = false

  class << self
    attr_reader :available

    def setup
      return unless Platform.openbsd?
      require "ffi"
      extend FFI::Library
      ffi_lib FFI::Library::LIBC
      attach_function :unveil, [:string, :string], :int
      attach_function :pledge, [:string, :string], :int
      @available = true
    rescue LoadError, FFI::NotFoundError => e
      warn "⚠️  OpenBSD security unavailable: #{e.message}" if ENV["DEBUG"]
      @available = false
    end

    def apply(level, master_config = nil)
      return unless @available

      paths = paths_for_level(level, master_config)
      promises = promises_for_level(level, master_config)

      unveil_paths(paths) if paths
      pledge(promises, nil)
    rescue => e
      warn "⚠️  Security apply failed: #{e.message}" if ENV["DEBUG"]
    end

    private

    def paths_for_level(level, config)
      return nil unless config

      config.dig("security", "platform", "openbsd", "unveil", level.to_s)
    end

    def promises_for_level(level, config)
      return "stdio rpath wpath cpath inet dns proc exec" unless config

      config.dig("security", "platform", "openbsd", "pledge", level.to_s) ||
        "stdio rpath wpath cpath inet dns proc exec"
    end

    def unveil_paths(paths)
      return unless paths.is_a?(Array)

      paths.each do |entry|
        path = File.expand_path(entry["path"])
        perms = entry["permissions"]
        unveil(path, perms) if Dir.exist?(path) || File.exist?(path)
      end

      unveil(nil, nil) # Lock unveil
    end
  end
end

OpenBSDSecurity.setup

# Configuration management
class Config
  attr_accessor :mode, :access_level, :model, :provider, :verbose, :auto_fix_enabled, :active_profile

  def self.load
    new.tap do |config|
      if File.exist?(Paths::CONFIG_FILE)
        data = YAML.safe_load_file(Paths::CONFIG_FILE) || {}
        config.mode = data["mode"]&.to_sym
        config.access_level = data["access_level"]&.to_sym || :user
        config.model = data["model"] || "deepseek/deepseek-r1"
        config.provider = data["provider"] || "openrouter"
        config.verbose = data["verbose"] || false
        config.auto_fix_enabled = data.fetch("auto_fix_enabled", true)
        config.active_profile = data["active_profile"]&.to_sym || :balanced
      else
        config.mode = nil # Will prompt
        config.access_level = :user
        config.model = "deepseek/deepseek-r1"
        config.provider = "openrouter"
        config.verbose = false
        config.auto_fix_enabled = true
        config.active_profile = :balanced
      end
    end
  end

  def save
    Paths.ensure_exists(File.dirname(Paths::CONFIG_FILE))
    data = {
      "mode" => mode.to_s,
      "access_level" => access_level.to_s,
      "model" => model,
      "provider" => provider,
      "verbose" => verbose,
      "auto_fix_enabled" => auto_fix_enabled,
      "active_profile" => active_profile.to_s
    }
    File.write(Paths::CONFIG_FILE, YAML.dump(data))
    File.chmod(0o600, Paths::CONFIG_FILE)
  end
end

# Master configuration loader
class Master
  attr_reader :data

  def self.load
    unless File.exist?(Paths::MASTER_FILE)
      raise "master.yml not found at #{Paths::MASTER_FILE}"
    end

    new(YAML.safe_load_file(Paths::MASTER_FILE))
  rescue StandardError => e
    raise "Failed to load master.yml: #{e.message}"
  end

  def initialize(data)
    @data = data
    validate!
  end

  def validate!
    required = %w[meta principles evidence personas adversarial catalog]
    missing = required - @data.keys
    raise "Missing required sections: #{missing.join(', ')}" if missing.any?

    validate_counts!
  end

  def validate_counts!
    personas_count = @data.dig("personas", "roles")&.size || 0
    adversarial_count = @data.dig("adversarial", "personas")&.size || 0

    raise "Insufficient personas: #{personas_count} < 6" if personas_count < 6
    raise "Insufficient adversarial: #{adversarial_count} < 10" if adversarial_count < 10
  end

  def version
    @data.dig("meta", "version")
  end

  def principle(key)
    @data.dig("principles", key.to_s)
  end

  def remedy_for(defect_type)
    @data["catalog"]&.each_value do |domain|
      if domain.is_a?(Hash) && domain.key?(defect_type.to_s)
        remedy_data = domain[defect_type.to_s]
        return remedy_data.is_a?(Hash) ? remedy_data : { "remedy" => remedy_data }
      end
    end
    nil
  end

  def auto_fixable?(defect_type)
    remedy_data = remedy_for(defect_type)
    return false unless remedy_data

    remedy_data.is_a?(Hash) && remedy_data["auto_fix"] == true
  end

  def evidence_threshold
    @data.dig("evidence", "thresholds", "production") || 0.95
  end

  def evidence_weights
    @data.dig("evidence", "weights") || { "tests" => 0.5, "static" => 0.3, "complexity" => 0.2 }
  end

  def severity_for(defect_type)
    %w[critical high medium low].each do |level|
      defects = @data.dig("severity", level) || []
      return level.to_sym if defects.include?(defect_type.to_s)
    end
    :unknown
  end

  def auto_fix_config
    @data["auto_fix"] || {}
  end

  def openrouter_config
    @data["openrouter"] || {}
  end

  def profile_config(name)
    @data.dig("profiles", name.to_s)
  end
end

# NEW in v0.3: Version compatibility checker
module VersionChecker
  COMPATIBILITY = {
    "0.3" => {
      min_master: "0.3.0",
      max_master: "0.3.99",
      min_ruby: "3.0.0"
    }
  }.freeze

  def self.check!
    cli_version = VERSION
    master_version = Master.load.version

    cli_major_minor = cli_version.split('.').first(2).join('.')
    master_major_minor = master_version.split('.').first(2).join('.')

    unless cli_major_minor == master_major_minor
      raise "Version mismatch: cli.rb v#{cli_version} incompatible with master.yml v#{master_version}"
    end

    # Check Ruby version
    compat = COMPATIBILITY[cli_major_minor]
    if compat && Gem::Version.new(RUBY_VERSION) < Gem::Version.new(compat[:min_ruby])
      raise "Ruby version #{RUBY_VERSION} too old, requires >= #{compat[:min_ruby]}"
    end
  end
end

# NEW in v0.3: Unified logging
module UnifiedLogger
  @logger = nil
  @cli_logger = nil

  def self.setup(name, verbose: false)
    Paths.ensure_exists(Paths::LOG_DIR)
    
    @logger = Logger.new(File.join(Paths::LOG_DIR, "#{name}.log"), "daily")
    @logger.level = verbose ? Logger::DEBUG : Logger::INFO
    
    @cli_logger = Logger.new($stdout)
    @cli_logger.level = verbose ? Logger::DEBUG : Logger::INFO
    @cli_logger.formatter = proc do |severity, _, _, msg|
      case severity
      when "DEBUG" then "🔍 #{msg}\n"
      when "INFO" then "ℹ️  #{msg}\n"
      when "WARN" then "⚠️  #{msg}\n"
      when "ERROR" then "✗ #{msg}\n"
      when "FATAL" then "💀 #{msg}\n"
      else "#{msg}\n"
      end
    end
  end

  def self.debug(msg)
    @logger&.debug(msg)
    @cli_logger&.debug(msg)
  end

  def self.info(msg)
    @logger&.info(msg)
    @cli_logger&.info(msg)
  end

  def self.warn(msg)
    @logger&.warn(msg)
    @cli_logger&.warn(msg)
  end

  def self.error(msg)
    @logger&.error(msg)
    @cli_logger&.error(msg)
  end

  def self.fatal(msg)
    @logger&.fatal(msg)
    @cli_logger&.fatal(msg)
  end
end

# Shell command execution (allowlist only)
class ShellTool
  ALLOWED_COMMANDS = {
    "rubocop" => ["rubocop", "-a"],
    "test" => ["ruby", "-Itest", "-e", "Dir['test/**/*_test.rb'].each { |f| require_relative f }"],
    "flog" => ["flog", "--all", "--methods-only"],
    "git" => ["git"]
  }.freeze

  Result = Struct.new(:success, :stdout, :stderr, :exit_code, keyword_init: true)

  def self.execute(command, *args, timeout: 30)
    base_cmd = ALLOWED_COMMANDS[command]
    return Result.new(success: false, stderr: "Command not allowed", exit_code: 127) unless base_cmd

    full_cmd = base_cmd + args.map { |arg| Shellwords.escape(arg) }

    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3(*full_cmd)
      Result.new(
        success: status.success?,
        stdout: stdout[0..10_000],
        stderr: stderr[0..2000],
        exit_code: status.exitstatus
      )
    end
  rescue Timeout::Error
    Result.new(success: false, stderr: "Timeout after #{timeout}s", exit_code: 124)
  rescue => e
    Result.new(success: false, stderr: e.message, exit_code: 1)
  end
end

# Git integration for auto-fix commits
class GitTool
  def self.available?
    result = ShellTool.execute("git", "--version")
    result.success
  rescue
    false
  end

  def self.clean_working_tree?
    result = ShellTool.execute("git", "status", "--porcelain")
    result.success && result.stdout.strip.empty?
  end

  def self.commit(message, files = [])
    return { success: false, error: "Git not available" } unless available?

    # Stage specific files or all changes
    if files.any?
      files.each do |file|
        result = ShellTool.execute("git", "add", file)
        return { success: false, error: "Failed to stage #{file}" } unless result.success
      end
    else
      result = ShellTool.execute("git", "add", "-A")
      return { success: false, error: "Failed to stage changes" } unless result.success
    end

    # Commit
    result = ShellTool.execute("git", "commit", "-m", message)
    if result.success
      { success: true }
    else
      { success: false, error: result.stderr }
    end
  end

  def self.diff(file = nil)
    args = ["diff"]
    args << file if file

    result = ShellTool.execute("git", *args)
    result.success ? { success: true, diff: result.stdout } : { success: false }
  end
end

# File operations with sandbox enforcement
class FileTool
  def initialize(base_path:, access_level:)
    @base = File.expand_path(base_path)
    @level = access_level
  end

  def read(path)
    safe_path = enforce_sandbox!(path)
    return { error: "File not found: #{path}" } unless File.exist?(safe_path)

    {
      content: File.read(safe_path)[0..100_000],
      size: File.size(safe_path),
      path: safe_path
    }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "Read error: #{e.message}" }
  end

  def write(path, content)
    safe_path = enforce_sandbox!(path)
    FileUtils.mkdir_p(File.dirname(safe_path))
    File.write(safe_path, content)
    { success: true, bytes: content.bytesize, path: safe_path }
  rescue SecurityError => e
    { error: e.message }
  rescue => e
    { error: "Write error: #{e.message}" }
  end

  private

  def enforce_sandbox!(path)
    expanded = File.expand_path(path, @base)
    allowed = allowed_paths

    return expanded if allowed.nil? # Admin mode

    allowed.each do |allowed_path|
      return expanded if expanded.start_with?("#{allowed_path}/") || expanded == allowed_path
    end

    raise SecurityError, "Access denied: #{path} (level: #{@level})"
  end

  def allowed_paths
    case @level
    when :sandbox then [Dir.pwd, "/tmp"]
    when :user then [Paths::HOME, Dir.pwd, "/tmp", Paths::BACKUP_DIR]
    when :admin then nil
    else [Dir.pwd]
    end
  end
end

# Pattern-based code scanner with enhanced patterns
class Scanner
  # Enhanced patterns for v0.3 (pub4 issues)
  PATTERNS = {
    # Critical security issues
    injection_vulnerability: /system\(|exec\(|`[^`]*\$|eval\(|IO\.popen/,
    token_exposure: /Token [a-zA-Z0-9_-]{32,}|Bearer [a-zA-Z0-9_-]{32,}|sk-[a-zA-Z0-9]{32,}/,
    hardcoded_secret: /password\s*=\s*["'][^"']+["']|api_key\s*=\s*["'][^"']+["']/i,
    sql_injection: /["']\s*\+\s*\w+|execute\([^?]*\#{|where\([^?]*\#{/,
    xss_vulnerability: /html_safe|raw\(|<%=\s*@\w+\s*%>/,
    
    # NEW: pub4-specific issues
    yaml_in_ruby_file: /^[a-z_]+:\s+.+$/m,
    hardcoded_path: /["'](?:\/sdcard|\/home\/[a-z]+|C:\/Users|\/var\/www)/,
    missing_file_lock: /^(?!.*flock\s+).*(?:cron|concurrent)/m,
    
    # Logic issues
    race_condition: /@@\w+|Thread\.new(?!\s*\{)/,
    magic_number: /(?<!\d)([1-9]\d{2,})(?!\d)/,
    mass_assignment: /\.new\(params\[|\.create\(params\[/
  }.freeze

  Defect = Struct.new(
    :type, :severity, :file, :line, :column, :context, :remedy, :auto_fixable,
    keyword_init: true
  )

  def initialize(master:)
    @master = master
  end

  def scan(directory = Dir.pwd)
    ruby_files(directory).flat_map { |file| scan_file(file) }
  end

  private

  def ruby_files(directory)
    Dir.glob("#{directory}/**/*.rb").reject do |path|
      path.match?(%r{vendor/|node_modules/|\.bundle/})
    end
  end

  def scan_file(file_path)
    content = File.read(file_path)
    defects = []

    PATTERNS.each do |type, pattern|
      content.scan(pattern) do
        match_pos = Regexp.last_match.begin(0)
        line_num = content[0..match_pos].count("\n") + 1
        col_num = match_pos - content.rindex("\n", match_pos).to_i

        remedy_data = @master.remedy_for(type)

        defects << Defect.new(
          type: type,
          severity: @master.severity_for(type),
          file: file_path,
          line: line_num,
          column: col_num,
          context: extract_context(content, line_num),
          remedy: remedy_data,
          auto_fixable: @master.auto_fixable?(type)
        )
      end
    end

    defects
  rescue => e
    UnifiedLogger.warn("Error scanning #{file_path}: #{e.message}") if ENV["DEBUG"]
    []
  end

  def extract_context(content, line_num)
    lines = content.lines
    start_line = [line_num - 2, 0].max
    end_line = [line_num + 1, lines.size - 1].min

    lines[start_line..end_line].join.strip[0..200]
  end
end

# Backup manager
class BackupManager
  def initialize
    @backup_dir = Paths::BACKUP_DIR
    Paths.ensure_exists(@backup_dir)
  end

  def create_backup(file_path)
    return { error: "File not found" } unless File.exist?(file_path)

    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_name = "#{File.basename(file_path)}_#{timestamp}.bak"
    backup_path = File.join(@backup_dir, backup_name)

    FileUtils.cp(file_path, backup_path)
    { success: true, backup_path: backup_path }
  rescue => e
    { error: e.message }
  end

  def list_backups(file_pattern = nil)
    pattern = file_pattern ? "#{file_pattern}_*.bak" : "*.bak"
    backups = Dir.glob(File.join(@backup_dir, pattern))
    
    backups.map do |path|
      {
        path: path,
        original_file: extract_original_filename(File.basename(path)),
        timestamp: extract_timestamp(File.basename(path)),
        size: File.size(path)
      }
    end.sort_by { |b| b[:timestamp] }.reverse
  end

  def restore_backup(backup_path, target_path = nil)
    return { error: "Backup not found" } unless File.exist?(backup_path)

    target = target_path || reconstruct_original_path(backup_path)
    
    # Create backup of current state before restoring
    if File.exist?(target)
      rollback_backup = create_backup(target)
      return rollback_backup unless rollback_backup[:success]
    end

    FileUtils.cp(backup_path, target)
    { success: true, restored_to: target }
  rescue => e
    { error: e.message }
  end

  def cleanup_old_backups(days = 7)
    cutoff_time = Time.now - (days * 24 * 60 * 60)
    removed = 0

    Dir.glob(File.join(@backup_dir, "*.bak")).each do |backup|
      if File.mtime(backup) < cutoff_time
        File.delete(backup)
        removed += 1
      end
    end

    { removed: removed }
  rescue => e
    { error: e.message }
  end

  private

  def extract_original_filename(backup_name)
    backup_name.sub(/_\d{8}_\d{6}\.bak$/, "")
  end

  def extract_timestamp(backup_name)
    match = backup_name.match(/_(\d{8}_\d{6})\.bak$/)
    match ? Time.strptime(match[1], "%Y%m%d_%H%M%S") : Time.now
  end

  def reconstruct_original_path(backup_path)
    original_name = extract_original_filename(File.basename(backup_path))
    File.join(Dir.pwd, original_name)
  end
end

# Auto-fixer
class AutoFixer
  def initialize(master:, backup_manager:)
    @master = master
    @backup_manager = backup_manager
  end

  def fix_defects(defects, interactive: true)
    fixable = defects.select(&:auto_fixable)
    
    if fixable.empty?
      return { success: true, fixed: 0, skipped: defects.size, message: "No auto-fixable defects" }
    end

    puts "\nFound #{fixable.size} auto-fixable defects"
    puts "Total defects: #{defects.size}\n\n"

    fixed = []
    skipped = []

    fixable.each do |defect|
      if interactive
        action = prompt_fix_approval(defect)
        next if action == :skip
      end

      result = apply_fix(defect)
      if result[:success]
        fixed << defect
        puts "✓ Fixed #{defect.type} @ #{defect.file}:#{defect.line}"
      else
        skipped << defect
        puts "✗ Failed to fix #{defect.type}: #{result[:error]}"
      end
    end

    { success: true, fixed: fixed.size, skipped: skipped.size + (defects.size - fixable.size) }
  end

  private

  def prompt_fix_approval(defect)
    puts "\n#{'-' * 60}"
    puts "Defect: #{defect.type}"
    puts "File: #{defect.file}:#{defect.line}"
    puts "Severity: #{defect.severity}"
    
    remedy_info = defect.remedy
    remedy_name = remedy_info.is_a?(Hash) ? remedy_info["remedy"] : remedy_info
    puts "Remedy: #{remedy_name}"
    
    puts "\nContext:"
    puts defect.context
    puts "\n#{'-' * 60}"
    
    print "Apply fix? [y/n/q]: "
    response = gets.strip.downcase

    case response
    when "y" then :apply
    when "q" then exit(0)
    else :skip
    end
  end

  def apply_fix(defect)
    # Create backup first
    backup_result = @backup_manager.create_backup(defect.file)
    return backup_result unless backup_result[:success]

    content = File.read(defect.file)
    remedy_info = defect.remedy

    fixed_content = case defect.type
                    when :magic_number
                      fix_magic_number(content, defect, remedy_info)
                    when :injection_vulnerability
                      fix_injection(content, defect, remedy_info)
                    when :hardcoded_secret
                      fix_hardcoded_secret(content, defect, remedy_info)
                    when :token_exposure
                      fix_token_exposure(content, defect, remedy_info)
                    when :hardcoded_path
                      fix_hardcoded_path(content, defect, remedy_info)
                    else
                      return { success: false, error: "No fixer implemented for #{defect.type}" }
                    end

    return fixed_content unless fixed_content[:success]

    File.write(defect.file, fixed_content[:content])
    { success: true, backup: backup_result[:backup_path] }
  rescue => e
    { success: false, error: e.message }
  end

  def fix_magic_number(content, defect, remedy_info)
    lines = content.lines
    target_line = lines[defect.line - 1]

    match = target_line.match(/(?<!\d)(\d{3,})(?!\d)/)
    return { success: false, error: "Could not find magic number" } unless match

    magic_value = match[0]
    
    print "Enter constant name for #{magic_value} (or press enter for default): "
    constant_name = gets.strip
    constant_name = "MAGIC_#{magic_value}" if constant_name.empty?

    insert_line = find_constant_insertion_point(lines)
    lines.insert(insert_line, "#{constant_name} = #{magic_value}\n")

    lines[defect.line] = target_line.gsub(/(?<!\d)#{magic_value}(?!\d)/, constant_name)

    { success: true, content: lines.join }
  end

  def fix_injection(content, defect, remedy_info)
    lines = content.lines
    target_line = lines[defect.line - 1]

    fixed_line = target_line.gsub(/system\((.+?)\)/) do |match|
      arg = $1
      "system(Shellwords.escape(#{arg}))"
    end

    unless content.include?("require \"shellwords\"")
      lines.unshift("require \"shellwords\"\n")
    end

    lines[defect.line - 1] = fixed_line
    { success: true, content: lines.join }
  end

  def fix_hardcoded_secret(content, defect, remedy_info)
    lines = content.lines
    target_line = lines[defect.line - 1]

    match = target_line.match(/(password|api_key)\s*=\s*["']([^"']+)["']/i)
    return { success: false, error: "Could not parse secret" } unless match

    var_name = match[1]
    env_var_name = var_name.upcase

    fixed_line = target_line.gsub(
      /#{var_name}\s*=\s*["'][^"']+["']/i,
      "#{var_name} = ENV.fetch('#{env_var_name}') { raise 'Set #{env_var_name}' }"
    )

    lines[defect.line - 1] = fixed_line
    { success: true, content: lines.join }
  end

  def fix_token_exposure(content, defect, remedy_info)
    lines = content.lines
    
    # Sanitize token in error handling
    lines = lines.map do |line|
      line.gsub(/Token [a-zA-Z0-9_-]{32,}/, "Token [REDACTED]")
          .gsub(/Bearer [a-zA-Z0-9_-]{32,}/, "Bearer [REDACTED]")
          .gsub(/sk-[a-zA-Z0-9]{32,}/, "sk-[REDACTED]")
    end

    { success: true, content: lines.join }
  end

  def fix_hardcoded_path(content, defect, remedy_info)
    lines = content.lines
    target_line = lines[defect.line - 1]

    # Detect path type and suggest Paths module replacement
    path_replacements = {
      '/sdcard' => 'Paths.for(:samples)',
      '/home/' => 'Paths::HOME',
      'C:/Users' => 'Paths::HOME',
      '/var/www' => 'Paths.for(:rails)'
    }

    fixed_line = target_line
    path_replacements.each do |pattern, replacement|
      if target_line.include?(pattern)
        fixed_line = target_line.gsub(/["'].*#{Regexp.escape(pattern)}.*["']/, replacement)
        break
      end
    end

    lines[defect.line - 1] = fixed_line
    { success: true, content: lines.join }
  end

  def find_constant_insertion_point(lines)
    last_require = 0
    lines.each_with_index do |line, idx|
      last_require = idx + 1 if line.match?(/^\s*require/)
    end

    lines.each_with_index do |line, idx|
      next if idx < last_require
      return idx unless line.match?(/^\s*#/)
    end

    last_require
  end
end

# Evidence calculator
class EvidenceCalculator
  def initialize(master:)
    @master = master
    @weights = @master.evidence_weights
  end

  def calculate
    tests = test_score
    static = static_score
    complexity = complexity_score

    score = (tests * @weights["tests"]) +
            (static * @weights["static"]) +
            (complexity * @weights["complexity"])

    {
      score: score,
      tests: tests,
      static: static,
      complexity: complexity,
      pass: score >= @master.evidence_threshold
    }
  end

  private

  def test_score
    result = ShellTool.execute("test")
    result.success ? 1.0 : 0.0
  rescue
    0.0
  end

  def static_score
    result = ShellTool.execute("rubocop", ".")
    result.success ? 1.0 : 0.0
  rescue
    0.0
  end

  def complexity_score
    result = ShellTool.execute("flog", ".")
    return 1.0 unless result.success

    avg = parse_flog_output(result.stdout)
    1.0 - [1.0, avg / 20.0].min
  rescue
    1.0
  end

  def parse_flog_output(output)
    scores = output.scan(/(\d+\.\d+):/).map { |m| m[0].to_f }
    return 0.0 if scores.empty?

    scores.sum / scores.size
  end
end

# Ferrum mode for free browser automation
class FerrumMode
  def initialize
    @browser = nil
    @page = nil
  end

  def start
    require "ferrum"
    @browser = Ferrum::Browser.new(
      headless: true,
      window_size: [1920, 1080],
      timeout: 30
    )
    @page = @browser.create_page
    puts "✓ Browser started (Ferrum mode)"
  rescue LoadError
    puts "✗ Ferrum not installed. Run: gem install ferrum"
    exit 1
  rescue Ferrum::BrowserError
    puts "✗ Chrome/Chromium not found"
    exit 1
  end

  def handle(input)
    cmd, *args = input.split(/\s+/)

    case cmd
    when "goto" then goto_url(args.first)
    when "screenshot" then screenshot(args.first)
    when "scrape" then scrape
    when "help" then show_help
    else puts "Unknown command: #{cmd}. Type 'help' for commands."
    end
  end

  def stop
    @browser&.quit
  end

  private

  def goto_url(url)
    url = "https://#{url}" unless url.start_with?("http")
    @page.goto(url)
    puts "✓ Loaded: #{url}"
  rescue => e
    puts "✗ Error: #{e.message}"
  end

  def screenshot(path = nil)
    path ||= File.join(Paths::CONFIG_DIR, "screenshot_#{Time.now.to_i}.png")
    @page.screenshot(path: path)
    puts "✓ Screenshot saved: #{path}"
  rescue => e
    puts "✗ Error: #{e.message}"
  end

  def scrape
    data = {
      url: @page.current_url,
      title: @page.title,
      text: @page.evaluate("document.body.innerText")[0..2000],
      links: @page.css("a").map { |a| a.attribute("href") }.compact.take(20),
      images: @page.css("img").map { |i| i.attribute("src") }.compact.take(20)
    }

    output = File.join(Paths::CONFIG_DIR, "scrape_#{Time.now.to_i}.json")
    File.write(output, JSON.pretty_generate(data))
    puts "✓ Data saved: #{output}"
  rescue => e
    puts "✗ Error: #{e.message}"
  end

  def show_help
    puts <<~HELP
      Ferrum Mode Commands:
        goto <url>        - Navigate to URL
        screenshot [path] - Take screenshot
        scrape            - Extract page data
        help              - Show this help
        quit              - Exit Ferrum mode
    HELP
  end
end

# NEW in v0.3: OpenRouter API integration
class OpenRouterAPI
  API_URL = "https://openrouter.ai/api/v1/chat/completions"

  def initialize(api_key:, model:, master:)
    @api_key = api_key
    @model = model
    @master = master
    @config = master.openrouter_config
  end

  def analyze_code(code, defects)
    # Use prompt caching for master.yml
    master_context = File.read(Paths::MASTER_FILE)

    request_body = {
      model: @model,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Constitutional Governance:\n\n#{master_context}",
              cache_control: { type: "ephemeral" }
            },
            {
              type: "text",
              text: build_analysis_prompt(code, defects)
            }
          ]
        }
      ],
      stream_options: { include_usage: true },
      max_tokens: 2000
    }

    make_request(request_body)
  end

  def suggest_fixes(defects)
    master_context = File.read(Paths::MASTER_FILE)

    request_body = {
      model: @model,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Constitutional Governance:\n\n#{master_context}",
              cache_control: { type: "ephemeral" }
            },
            {
              type: "text",
              text: build_fix_prompt(defects)
            }
          ]
        }
      ],
      stream_options: { include_usage: true },
      max_tokens: 1500
    }

    make_request(request_body)
  end

  private

  def build_analysis_prompt(code, defects)
    <<~PROMPT
      Analyze this code for defects according to the constitutional governance above.

      Code:
      ```ruby
      #{code}
      ```

      Already detected defects:
      #{defects.map { |d| "- #{d.type} @ line #{d.line}: #{d.context}" }.join("\n")}

      Provide:
      1. Severity assessment
      2. Root cause analysis
      3. Recommended fixes
      4. Priority order

      Format as JSON:
      {
        "analysis": "...",
        "suggestions": [
          {
            "type": "defect_type",
            "priority": "critical|high|medium|low",
            "fix": "description",
            "code": "fixed code snippet"
          }
        ]
      }
    PROMPT
  end

  def build_fix_prompt(defects)
    <<~PROMPT
      Suggest fixes for these defects according to constitutional governance.

      Defects:
      #{defects.map { |d| "- #{d.type} (#{d.severity}) @ #{d.file}:#{d.line}\n  Context: #{d.context}" }.join("\n\n")}

      For each defect, provide:
      1. Specific fix implementation
      2. Testing strategy
      3. Potential side effects

      Format as JSON array.
    PROMPT
  end

  def make_request(body)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = @config.dig("timeout", "read") || 60
    http.open_timeout = @config.dig("timeout", "connect") || 10

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request['HTTP-Referer'] = @config.dig("headers", "recommended", "HTTP-Referer") || "https://github.com/anon987654321/pub4"
    request['X-Title'] = @config.dig("headers", "recommended", "X-Title") || "Convergence CLI v#{VERSION}"
    
    request.body = JSON.generate(body)

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      sanitized_body = sanitize_tokens(response.body)
      raise "API error #{response.code}: #{sanitized_body}"
    end

    JSON.parse(response.body)
  rescue => e
    sanitized_msg = sanitize_tokens(e.message)
    UnifiedLogger.error("API request failed: #{sanitized_msg}")
    nil
  end

  def sanitize_tokens(text)
    text.gsub(/Token [a-zA-Z0-9_-]+/, "Token [REDACTED]")
        .gsub(/Bearer [a-zA-Z0-9_-]+/, "Bearer [REDACTED]")
        .gsub(/sk-[a-zA-Z0-9]+/, "sk-[REDACTED]")
  end
end

# NEW in v0.3: Cost tracking
class CostTracker
  def initialize(master:)
    @master = master
    @total_cost = 0.0
    @cached_savings = 0.0
    @requests = []
  end

  def record(response, model_name)
    usage = response.dig("usage")
    return unless usage

    prompt_tokens = usage["prompt_tokens"] || 0
    completion_tokens = usage["completion_tokens"] || 0
    cached_tokens = usage.dig("prompt_tokens_details", "cached_tokens") || 0

    model_config = find_model_config(model_name)
    return unless model_config

    prompt_cost = (prompt_tokens - cached_tokens) * model_config["cost_per_1m_prompt"] / 1_000_000
    cached_cost = cached_tokens * model_config["cost_per_1m_cached"] / 1_000_000
    completion_cost = completion_tokens * model_config["cost_per_1m_completion"] / 1_000_000

    total_request_cost = prompt_cost + cached_cost + completion_cost
    savings = cached_tokens * (model_config["cost_per_1m_prompt"] - model_config["cost_per_1m_cached"]) / 1_000_000

    @total_cost += total_request_cost
    @cached_savings += savings

    @requests << {
      timestamp: Time.now,
      model: model_name,
      prompt_tokens: prompt_tokens,
      cached_tokens: cached_tokens,
      completion_tokens: completion_tokens,
      cost: total_request_cost,
      savings: savings
    }

    {
      cost: total_request_cost,
      cached_tokens: cached_tokens,
      savings: savings
    }
  end

  def summary
    {
      total_cost: @total_cost,
      total_savings: @cached_savings,
      requests: @requests.size,
      average_cost: @requests.empty? ? 0 : @total_cost / @requests.size
    }
  end

  private

  def find_model_config(model_name)
    models = @master.openrouter_config["models"] || {}
    models.values.find { |m| m["name"] == model_name }
  end
end

# NEW in v0.3: Profile manager
module ProfileManager
  @current_profile = :balanced
  @profiles = {}

  def self.load_profiles(master)
    @profiles = master.data["profiles"] || {}
  end

  def self.switch(name)
    return false unless @profiles.key?(name.to_s)
    
    @current_profile = name
    profile = @profiles[name.to_s]
    
    puts "Switched to #{name} profile"
    puts "  Model: #{profile['model']}"
    puts "  Temperature: #{profile['temperature']}"
    puts "  Focus: #{profile['focus'].join(', ')}"
    
    true
  end

  def self.current
    @profiles[@current_profile.to_s] || default_profile
  end

  def self.current_name
    @current_profile
  end

  def self.available
    @profiles.keys
  end

  def self.default_profile
    {
      "temperature" => 0.5,
      "focus" => ["general"],
      "model" => "deepseek/deepseek-r1"
    }
  end
end

# NEW in v0.3: Session timer
class SessionTimer
  def initialize
    @start_time = Time.now
  end

  def elapsed
    Time.now - @start_time
  end

  def report
    hours = (elapsed / 3600).floor
    minutes = ((elapsed % 3600) / 60).floor
    seconds = (elapsed % 60).floor

    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0 || hours > 0
    parts << "#{seconds}s"

    parts.join(" ")
  end
end

# Main CLI
class CLI
  def initialize
    Paths.ensure_exists(Paths::CONFIG_DIR, Paths::LOG_DIR, Paths::BACKUP_DIR)
    
    UnifiedLogger.setup("convergence", verbose: ENV["DEBUG"])
    
    @master = Master.load
    @config = Config.load
    @platform = Platform.detect
    @backup_manager = BackupManager.new
    @auto_fixer = AutoFixer.new(master: @master, backup_manager: @backup_manager)
    @session_timer = SessionTimer.new
    @cost_tracker = CostTracker.new(master: @master)

    VersionChecker.check!
    ProfileManager.load_profiles(@master)
    
    prompt_mode_if_needed!
    apply_security!
    show_boot_sequence
  end

  def run
    case @config.mode
    when :api then run_api_mode
    when :free then run_free_mode
    when :local then run_local_mode
    else
      puts "Invalid mode: #{@config.mode}"
      exit 1
    end
  end

  private

  def prompt_mode_if_needed!
    return if @config.mode

    puts "\n🚀 Convergence v#{VERSION} - First Run Setup"
    puts "\nSelect mode:"
    puts "  1. API Mode (requires OPENROUTER_API_KEY)"
    puts "  2. Free Mode (requires Chrome/Chromium + gem install ferrum)"
    puts "  3. Local Mode (basic pattern matching + auto-fix)"
    print "\nChoice [1/2/3]: "

    choice = gets.strip
    @config.mode = case choice
                   when "1" then check_api_key! && :api
                   when "2" then check_ferrum! && :free
                   when "3" then :local
                   else
                     puts "Defaulting to Local Mode"
                     :local
                   end

    @config.save
  end

  def check_api_key!
    unless ENV["OPENROUTER_API_KEY"]
      puts "\n⚠️  OPENROUTER_API_KEY not set"
      puts "Set it with: export OPENROUTER_API_KEY='your-key'"
      print "Continue anyway? [y/N]: "
      return false unless gets.strip.downcase == "y"
    end
    true
  end

  def check_ferrum!
    begin
      require "ferrum"
      true
    rescue LoadError
      puts "\n⚠️  Ferrum not installed"
      puts "Install with: gem install ferrum"
      false
    end
  end

  def apply_security!
    return unless Platform.security_available?

    OpenBSDSecurity.apply(@config.access_level, @master.data)
  end

  def show_boot_sequence
    puts "Convergence v#{VERSION}"
    puts "Platform: #{@platform[:type]}"
    puts "Mode: #{@config.mode}"
    puts "Profile: #{ProfileManager.current_name}"
    puts "Access: #{@config.access_level}"
    puts "Security: #{@platform[:security]}"
    puts "Auto-fix: #{@config.auto_fix_enabled ? 'enabled' : 'disabled'}"
    puts ""
  end

  def run_api_mode
    puts "API Mode - Type 'help' for commands"
    defects = []
    api = nil

    if ENV["OPENROUTER_API_KEY"]
      profile = ProfileManager.current
      api = OpenRouterAPI.new(
        api_key: ENV["OPENROUTER_API_KEY"],
        model: profile["model"],
        master: @master
      )
    end

    loop do
      print "convergence> "
      input = Readline.readline("", true)&.strip
      break if input.nil? || %w[quit exit].include?(input)
      next if input.empty?

      handle_api_command(input, defects, api)
    end
  end

  def handle_api_command(input, defects, api)
    cmd, *args = input.split(/\s+/)

    case cmd
    when "help" then show_help
    when "profile" then switch_profile(args.first)
    when "scan" then defects.replace(run_scan)
    when "analyze" then run_llm_analysis(defects, api)
    when "fix" then run_auto_fix(defects)
    when "verify" then run_verification
    when "config" then show_config
    when "mode" then switch_mode
    when "backup" then manage_backups(args)
    when "rollback" then rollback_last_fix
    when "cost" then show_cost_summary
    when "session" then show_session_stats
    else
      puts "Unknown command: #{cmd}. Type 'help' for available commands."
    end
  end

  def run_free_mode
    ferrum = FerrumMode.new
    ferrum.start

    loop do
      print "ferrum> "
      input = gets&.strip
      break if input.nil? || input == "quit"
      next if input.empty?

      ferrum.handle(input)
    end

    ferrum.stop
  end

  def run_local_mode
    puts "Local Mode - Pattern matching + auto-fix"
    puts "Type 'help' for commands"

    defects = []

    loop do
      print "convergence> "
      input = gets&.strip
      break if input.nil? || %w[quit exit].include?(input)
      next if input.empty?

      handle_local_command(input, defects)
    end
  end

  def handle_local_command(input, defects)
    cmd, *args = input.split(/\s+/)

    case cmd
    when "help" then show_help
    when "profile" then switch_profile(args.first)
    when "scan" then defects.replace(run_scan)
    when "fix" then run_auto_fix(defects)
    when "verify" then run_verification
    when "config" then show_config
    when "mode" then switch_mode
    when "backup" then manage_backups(args)
    when "rollback" then rollback_last_fix
    when "session" then show_session_stats
    else
      puts "Unknown command: #{cmd}"
    end
  end

  def switch_profile(name)
    if name.nil?
      puts "\nAvailable profiles:"
      ProfileManager.available.each do |profile_name|
        marker = profile_name == ProfileManager.current_name.to_s ? "* " : "  "
        puts "#{marker}#{profile_name}"
      end
      return
    end

    if ProfileManager.switch(name.to_sym)
      @config.active_profile = name.to_sym
      @config.save
    else
      puts "Unknown profile: #{name}"
    end
  end

  def run_scan
    puts "Scanning codebase..."
    scanner = Scanner.new(master: @master)
    defects = scanner.scan

    if defects.empty?
      puts "✓ No defects found"
    else
      display_defects(defects)
    end

    defects
  end

  def display_defects(defects)
    puts "\nFound #{defects.size} defects:\n"
    
    auto_fixable = defects.count(&:auto_fixable)
    puts "Auto-fixable: #{auto_fixable}\n\n" if auto_fixable > 0

    defects.group_by(&:severity).each do |severity, group|
      puts "\n#{severity.upcase} (#{group.size}):"
      group.take(10).each do |defect|
        marker = defect.auto_fixable ? "🔧" : "  "
        puts "#{marker} #{defect.file}:#{defect.line} - #{defect.type}"
        
        remedy_info = defect.remedy
        remedy_name = remedy_info.is_a?(Hash) ? remedy_info["remedy"] : remedy_info
        puts "     Remedy: #{remedy_name}" if remedy_name
      end
      puts "  ... and #{group.size - 10} more" if group.size > 10
    end
  end

  def run_llm_analysis(defects, api)
    return puts "No API configured" unless api
    return puts "No defects to analyze. Run 'scan' first." if defects.empty?

    puts "\nAnalyzing with LLM..."

    # Group defects by file for efficient analysis
    defects.group_by(&:file).each do |file, file_defects|
      next unless File.exist?(file)
      
      code = File.read(file)[0..10_000]  # Limit context
      
      puts "\n📄 #{file}"
      response = api.analyze_code(code, file_defects)
      
      if response
        @cost_tracker.record(response, ProfileManager.current["model"])
        display_llm_analysis(response)
      else
        puts "  ✗ Analysis failed"
      end
    end
  end

  def display_llm_analysis(response)
    content = response.dig("choices", 0, "message", "content")
    return unless content

    begin
      analysis = JSON.parse(content)
      puts "  Analysis: #{analysis['analysis']}"
      
      if analysis['suggestions']
        puts "\n  Suggestions:"
        analysis['suggestions'].each_with_index do |suggestion, i|
          puts "    #{i + 1}. [#{suggestion['priority']}] #{suggestion['fix']}"
        end
      end
    rescue JSON::ParserError
      puts "  #{content[0..500]}"
    end
  end

  def run_auto_fix(defects)
    unless @config.auto_fix_enabled
      puts "Auto-fix is disabled. Enable in config with 'config set auto_fix true'"
      return
    end

    return puts "No defects to fix. Run 'scan' first." if defects.empty?

    auto_fix_config = @master.auto_fix_config
    interactive = auto_fix_config.dig("approval", "mode") != "auto"

    result = @auto_fixer.fix_defects(defects, interactive: interactive)
    
    puts "\nAuto-fix completed:"
    puts "  Fixed: #{result[:fixed]}"
    puts "  Skipped: #{result[:skipped]}"

    # Run tests after fixes
    if result[:fixed] > 0 && auto_fix_config.dig("safety_rules", "run_tests_after_fix")
      puts "\nRunning tests..."
      run_verification
    end

    # Git commit if enabled
    if result[:fixed] > 0 && auto_fix_config.dig("git", "enabled") && GitTool.available?
      print "\nCommit fixes to git? [y/N]: "
      if gets.strip.downcase == "y"
        commit_fixes(result[:fixed])
      end
    end
  end

  def commit_fixes(fix_count)
    message = "Fix #{fix_count} defects with Convergence auto-fix\n\nConvergence v#{VERSION}"
    result = GitTool.commit(message)
    
    if result[:success]
      puts "✓ Committed fixes"
    else
      puts "✗ Commit failed: #{result[:error]}"
    end
  end

  def run_verification
    puts "Calculating evidence..."
    calculator = EvidenceCalculator.new(master: @master)
    evidence = calculator.calculate

    puts "\nEvidence: #{evidence[:score].round(3)}"
    puts "  Tests: #{evidence[:tests].round(3)}"
    puts "  Static: #{evidence[:static].round(3)}"
    puts "  Complexity: #{evidence[:complexity].round(3)}"
    puts "\n#{evidence[:pass] ? '✓ Pass' : '✗ Fail'}"
  end

  def show_config
    puts "\nConfiguration:"
    puts "  Version: #{VERSION}"
    puts "  Mode: #{@config.mode}"
    puts "  Profile: #{ProfileManager.current_name}"
    puts "  Access Level: #{@config.access_level}"
    puts "  Model: #{ProfileManager.current['model']}" if @config.mode == :api
    puts "  Auto-fix: #{@config.auto_fix_enabled ? 'enabled' : 'disabled'}"
    puts "  Config: #{Paths::CONFIG_FILE}"
    puts "  Master: #{Paths::MASTER_FILE}"
    puts "  Backups: #{Paths::BACKUP_DIR}"
    puts "  Platform: #{Platform.type}"
  end

  def switch_mode
    puts "\nSwitch mode:"
    puts "  1. API"
    puts "  2. Free"
    puts "  3. Local"
    print "Choice: "

    choice = gets.strip
    new_mode = case choice
               when "1" then :api
               when "2" then :free
               when "3" then :local
               else return puts "Cancelled"
               end

    @config.mode = new_mode
    @config.save
    puts "✓ Switched to #{new_mode} mode (restart to apply)"
  end

  def manage_backups(args)
    subcmd = args.first

    case subcmd
    when "list"
      backups = @backup_manager.list_backups
      if backups.empty?
        puts "No backups found"
      else
        puts "\nBackups:"
        backups.take(10).each_with_index do |backup, idx|
          size_kb = backup[:size] / 1024
          puts "  #{idx + 1}. #{backup[:original_file]} (#{backup[:timestamp].strftime('%Y-%m-%d %H:%M:%S')}) [#{size_kb}KB]"
        end
        puts "  ... and #{backups.size - 10} more" if backups.size > 10
      end
    
    when "cleanup"
      days = args[1]&.to_i || 7
      result = @backup_manager.cleanup_old_backups(days)
      if result[:error]
        puts "✗ Error: #{result[:error]}"
      else
        puts "✓ Removed #{result[:removed]} old backups"
      end
    
    else
      puts "Usage: backup [list|cleanup [days]]"
    end
  end

  def rollback_last_fix
    backups = @backup_manager.list_backups
    
    if backups.empty?
      puts "No backups available"
      return
    end

    puts "\nRecent backups:"
    backups.take(5).each_with_index do |backup, idx|
      puts "  #{idx + 1}. #{backup[:original_file]} (#{backup[:timestamp].strftime('%Y-%m-%d %H:%M:%S')})"
    end

    print "\nSelect backup to restore [1-#{[backups.size, 5].min}] or 'c' to cancel: "
    choice = gets.strip

    return if choice.downcase == "c"

    idx = choice.to_i - 1
    return puts "Invalid selection" if idx < 0 || idx >= backups.size

    backup = backups[idx]
    result = @backup_manager.restore_backup(backup[:path])

    if result[:success]
      puts "✓ Restored #{backup[:original_file]}"
    else
      puts "✗ Restore failed: #{result[:error]}"
    end
  end

  def show_cost_summary
    summary = @cost_tracker.summary
    
    puts "\nAPI Cost Summary:"
    puts "  Total Cost: $#{summary[:total_cost].round(6)}"
    puts "  Cached Savings: $#{summary[:total_savings].round(6)}"
    puts "  Requests: #{summary[:requests]}"
    puts "  Avg Cost/Request: $#{summary[:average_cost].round(6)}" if summary[:requests] > 0
  end

  def show_session_stats
    puts "\nSession Statistics:"
    puts "  Duration: #{@session_timer.report}"
    puts "  Mode: #{@config.mode}"
    puts "  Profile: #{ProfileManager.current_name}"
    
    if @config.mode == :api
      summary = @cost_tracker.summary
      puts "  API Requests: #{summary[:requests]}"
      puts "  API Cost: $#{summary[:total_cost].round(6)}"
    end
  end

  def show_help
    mode_commands = case @config.mode
                    when :api
                      "  analyze        - Deep LLM analysis of defects\n  cost           - Show API cost summary"
                    when :free
                      "  goto <url>     - Navigate browser\n  screenshot     - Capture page\n  scrape         - Extract data"
                    else
                      ""
                    end

    puts <<~HELP
      Convergence v#{VERSION} Commands:

        help           - Show this help
        profile [name] - Switch AI profile (architect/security/pragmatist/refactorer/tester)
        scan           - Scan codebase for defects
        fix            - Apply auto-fixes
        verify         - Calculate evidence score
        config         - Show configuration
        mode           - Switch modes
        backup         - Manage backups
        rollback       - Restore from backup
        session        - Show session stats
        quit           - Exit

      #{mode_commands}
      
      Available profiles: #{ProfileManager.available.join(', ')}
    HELP
  end
end

# Bootstrap and run
if __FILE__ == $PROGRAM_NAME
  # Setup interrupt handler
  trap("INT") do
    puts "\n\n👋 Goodbye"
    puts "Session duration: #{SessionTimer.new.report}" rescue nil
    exit 130
  end

  begin
    CLI.new.run
  rescue => e
    UnifiedLogger.fatal("Fatal error: #{e.message}")
    puts e.backtrace.take(5).join("\n") if ENV["DEBUG"]
    exit 1
  end
end

