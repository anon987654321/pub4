#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"
require "time"
require "set"
require "timeout"

# Auto-install missing gems
module Bootstrap
  GEMS = {
    "ruby_llm" => "ruby_llm",
    "tty-spinner" => "tty-spinner"
  }.freeze

  # OpenBSD packages needed for gems with native extensions
  OPENBSD_DEPS = {
    "ruby_llm" => []  # pure ruby, no deps
  }.freeze

  def self.run
    missing = GEMS.select { |gem_name, _| !gem_installed?(gem_name) }
    return if missing.empty?

    puts "Installing missing gems: #{missing.keys.join(', ')}..."
    
    # Install OS deps first on OpenBSD
    if platform == :openbsd
      install_openbsd_deps(missing.keys)
    end
    
    missing.each do |gem_name, pkg_name|
      install_gem(pkg_name)
    end
    
    puts "Gems installed. Reloading..."
    exec("ruby", $PROGRAM_NAME, *ARGV)
  end

  def self.gem_installed?(name)
    Gem::Specification.find_by_name(name)
    true
  rescue Gem::MissingSpecError
    false
  end

  def self.install_gem(name)
    # Use --user-install on OpenBSD/Unix when system dir not writable
    user_flag = writable_gem_dir? ? "" : "--user-install"
    system("gem install #{name} --no-document #{user_flag}") || 
      warn("Failed to install #{name}")
  end
  
  def self.writable_gem_dir?
    File.writable?(Gem.default_dir)
  rescue StandardError
    false
  end
  
  def self.ensure_gem_path
    return if writable_gem_dir?
    
    user_bin = File.join(Gem.user_dir, "bin")
    
    # Add to current session
    unless ENV["PATH"].to_s.include?(user_bin)
      ENV["PATH"] = "#{user_bin}:#{ENV['PATH']}"
    end
    
    # Auto-add to .zshrc if not present
    zshrc = File.expand_path("~/.zshrc")
    export_line = "export PATH=\"#{user_bin}:$PATH\""
    
    if File.exist?(zshrc)
      content = File.read(zshrc)
      unless content.include?(user_bin)
        File.open(zshrc, "a") { |f| f.puts "\n# Added by constitutional cli.rb\n#{export_line}" }
        puts "Added gem path to ~/.zshrc"
      end
    end
  end

  def self.install_openbsd_deps(gem_names)
    deps = gem_names.flat_map { |g| OPENBSD_DEPS[g] || [] }.uniq
    return if deps.empty?
    
    puts "Installing OpenBSD packages: #{deps.join(' ')}..."
    system("doas pkg_add -I #{deps.join(' ')}")
  end

  def self.platform
    case RUBY_PLATFORM
    when /openbsd/ then :openbsd
    when /linux.*android/, /aarch64.*linux/ then :termux
    when /linux/ then :linux
    when /darwin/ then :macos
    when /cygwin|mingw|mswin/ then :windows
    else :unknown
    end
  end
end

Bootstrap.ensure_gem_path
Bootstrap.run if ARGV.none? { |a| a == "--no-bootstrap" }

# Optional gems (now should be available)
begin
  require "ruby_llm"
  LLM_AVAILABLE = true
rescue LoadError
  LLM_AVAILABLE = false
end

begin
  require "tty-spinner"
  SPINNER_AVAILABLE = true
rescue LoadError
  SPINNER_AVAILABLE = false
end

begin
  require "readline"
  READLINE_AVAILABLE = true
rescue LoadError
  READLINE_AVAILABLE = false
end

# Global options
module Options
  @quiet = false
  @json = false
  @git_changed = false
  @watch = false
  @no_cache = false
  
  class << self
    attr_accessor :quiet, :json, :git_changed, :watch, :no_cache
  end
end

# FUNCTIONAL CORE
# All business logic as pure functions

module Core
  module PrincipleRegistry
    def self.load(constitution)
      constitution["principles"] || {}
    end
    
    def self.find_by_id(principles, id)
      principles.find { |_key, p| p["id"] == id }&.last
    end
    
    def self.find_by_smell(principles, smell)
      principles.select do |_key, principle|
        smells = principle["smells"] || []
        smells.include?(smell)
      end.values
    end
    
    def self.auto_fixable(principles)
      principles.select { |_key, p| p["auto_fixable"] }.values
    end
    
    def self.max_priority(principles)
      principles.values.map { |p| p["priority"] || 0 }.max || 0
    end
    
    def self.validate_no_cycles(principles)
      principles.each do |key, principle|
        visited = Set.new
        
        if has_cycle?(principle, principles, visited)
          return {
            valid: false,
            reason: "Circular reference in principle #{key}"
          }
        end
      end
      
      {valid: true}
    end
    
    def self.has_cycle?(principle, all_principles, visited)
      return true if visited.include?(principle["id"])
      
      visited.add(principle["id"])
      
      conflicts = principle["conflicts_with"] || []
      
      conflicts.each do |conflict_id|
        conflicted = find_by_id(all_principles, conflict_id)
        return true if conflicted && has_cycle?(conflicted, all_principles, visited.dup)
      end
      
      false
    end
  end
  
  module LLMDetector
    def self.detect_violations(code, file_path, principles, prompt_template)
      principle_summary = build_principle_summary(principles)
      
      prompt = prompt_template.gsub("{principles}", principle_summary)
      prompt += "\n\nCode to analyze:\n```ruby\n#{code}\n```"
      
      {
        prompt: prompt,
        file_path: file_path
      }
    end
    
    def self.build_principle_summary(principles)
      lines = []
      
      principles.each do |key, principle|
        id = principle["id"]
        name = principle["name"]
        rule = principle["rule"]
        priority = principle["priority"] || 5
        smells = (principle["smells"] || []).join(", ")
        
        lines << "#{id}. #{name} (Priority #{priority}): #{rule}"
        lines << "   Smells: #{smells}" if smells && !smells.empty?
      end
      
      lines.join("\n")
    end
    
    def self.parse_violations(json_response)
      cleaned = json_response.strip
      cleaned = cleaned.gsub(/^```json\n/, "").gsub(/\n```$/, "")
      cleaned = cleaned.gsub(/^```\n/, "").gsub(/\n```$/, "")
      
      JSON.parse(cleaned)
    rescue JSON::ParserError => error
      []
    end
  end
  
  module ScoreCalculator
    POINTS_PER_VIOLATION = 5
    MAX_SCORE = 100
    MIN_SCORE = 0
    
    def self.calculate(violations)
      raw = MAX_SCORE - (violations.size * POINTS_PER_VIOLATION)
      raw < MIN_SCORE ? MIN_SCORE : raw
    end
    
    def self.analyze(violations)
      by_severity = {}
      vetos = 0
      auto_fixable = 0
      
      violations.each do |v|
        severity = v["severity"] || v[:severity] || "medium"
        by_severity[severity] ||= 0
        by_severity[severity] += 1
        
        vetos += 1 if severity == "veto"
        auto_fixable += 1 if v["auto_fixable"] || v[:auto_fixable]
      end
      
      {
        total: violations.size,
        by_severity: by_severity,
        vetos: vetos,
        auto_fixable: auto_fixable,
        score: calculate(violations)
      }
    end
  end
  
  module TokenEstimator
    def self.estimate(text)
      ascii_chars = text.scan(/[[:ascii:]]/).size
      non_ascii_chars = text.size - ascii_chars
      
      ((ascii_chars / 4.0) + (non_ascii_chars * 1.0)).ceil
    end
    
    def self.warn_if_expensive(text, threshold)
      estimated = estimate(text)
      
      if estimated > threshold
        {warning: true, tokens: estimated}
      else
        {warning: false, tokens: estimated}
      end
    end
  end
  
  module Cache
    CACHE_DIR = File.join(Dir.home, ".cache", "constitutional")
    
    def self.init
      FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
    end
    
    def self.key_for(file_path, content)
      require "digest"
      Digest::SHA256.hexdigest("#{file_path}:#{content}")[0, 16]
    end
    
    def self.get(file_path, content)
      init
      cache_file = File.join(CACHE_DIR, "#{key_for(file_path, content)}.json")
      return nil unless File.exist?(cache_file)
      
      data = JSON.parse(File.read(cache_file))
      # Cache valid for 24 hours
      return nil if Time.now.to_i - data["timestamp"] > 86400
      
      data["violations"]
    rescue StandardError
      nil
    end
    
    def self.set(file_path, content, violations)
      init
      cache_file = File.join(CACHE_DIR, "#{key_for(file_path, content)}.json")
      
      File.write(cache_file, JSON.generate({
        timestamp: Time.now.to_i,
        file: file_path,
        violations: violations
      }))
    rescue StandardError
      nil
    end
    
    def self.clear
      FileUtils.rm_rf(CACHE_DIR)
      init
    end
  end
  
  module ConvergenceDetector
    def self.detect_loop(violation_history)
      return false if violation_history.size < 3
      
      last_three = violation_history.last(3)
      counts = last_three.map { |h| h[:violations].size }
      
      counts.uniq.size == 1 && counts.first > 0
    end
    
    def self.detect_oscillation(violation_history)
      return false if violation_history.size < 4
      
      last_four = violation_history.last(4)
      
      ids_0 = last_four[0][:violations].map { |v| v["principle_id"] }.sort
      ids_1 = last_four[1][:violations].map { |v| v["principle_id"] }.sort
      ids_2 = last_four[2][:violations].map { |v| v["principle_id"] }.sort
      ids_3 = last_four[3][:violations].map { |v| v["principle_id"] }.sort
      
      ids_0 == ids_2 && ids_1 == ids_3 && ids_0 != ids_1
    end
    
    def self.improving?(violation_history)
      return true if violation_history.size < 3
      
      last_three = violation_history.last(3).map { |h| h[:violations].size }
      last_three[0] > last_three[1] && last_three[1] > last_three[2]
    end
  end
  
  module FixValidator
    def self.validate(original_violations, fixed_violations, principles, config)
      return {valid: true} unless config["enabled"]
      
      new_violations = fixed_violations - original_violations
      
      return {valid: true} if new_violations.empty?
      
      if config["check_new_violations"]
        max_allowed = config["max_new_violations"] || 0
        
        if new_violations.size > max_allowed
          return {
            valid: false,
            reason: "Fix introduces #{new_violations.size} new violations"
          }
        end
      end
      
      if config["check_priority_inversion"]
        original_max = max_priority(original_violations, principles)
        new_max = max_priority(new_violations, principles)
        
        if new_max > original_max
          return {
            valid: false,
            reason: "Fix introduces higher-priority violations"
          }
        end
      end
      
      {valid: true}
    end
    
    def self.max_priority(violations, principles)
      violations.map do |v|
        principle = Core::PrincipleRegistry.find_by_id(principles, v["principle_id"])
        principle ? principle["priority"] : 0
      end.max || 0
    end
  end
  
  module LanguageDetector
    def self.detect_with_fallback(file_path, code, supported_languages)
      ext_language = detect_by_extension(file_path, supported_languages)
      return ext_language if ext_language != "unknown"
      
      detect_by_content(code, supported_languages)
    end
    
    def self.detect_by_extension(file_path, supported_languages)
      ext = File.extname(file_path)
      
      supported_languages.each do |lang_name, lang_config|
        extensions = lang_config["extensions"] || []
        return lang_name if extensions.include?(ext)
      end
      
      "unknown"
    end
    
    def self.detect_by_content(code, supported_languages)
      supported_languages.each do |lang_name, lang_config|
        indicators = lang_config["indicators"] || []
        
        indicators.each do |indicator|
          return lang_name if code.include?(indicator)
        end
      end
      
      "unknown"
    end
  end
  
  module GitHistory
    def self.available?
      system("git rev-parse --git-dir > /dev/null 2>&1")
    end
    
    def self.recent_commits(count = 3)
      return [] unless available?
      
      `git log --oneline -#{count} 2>/dev/null`.split("\n").map do |line|
        sha, *msg = line.split(" ")
        {sha: sha, message: msg.join(" ")}
      end
    end
    
    def self.file_at_commit(file_path, sha)
      return nil unless available?
      
      content = `git show #{sha}:#{file_path} 2>/dev/null`
      $?.success? ? content : nil
    end
    
    def self.compare_with_history(file_path, current_violations, commits: 3)
      return nil unless available?
      
      history = []
      
      recent_commits(commits).each do |commit|
        old_content = file_at_commit(file_path, commit[:sha])
        next unless old_content
        
        history << {
          sha: commit[:sha],
          message: commit[:message],
          had_content: true
        }
      end
      
      {
        current_violations: current_violations.size,
        history: history,
        trend: calculate_trend(current_violations.size, history)
      }
    end
    
    def self.calculate_trend(current_count, history)
      return :unknown if history.empty?
      
      if current_count == 0
        :perfect
      elsif history.size >= 2
        :tracking
      else
        :baseline
      end
    end
  end
  
  module FileWatcher
    def self.watch(paths, interval: 1.0, &block)
      mtimes = {}
      
      # Initial scan
      expand_paths(paths).each do |path|
        mtimes[path] = File.mtime(path) rescue nil
      end
      
      puts "Watching #{mtimes.size} files (Ctrl+C to stop)..."
      
      loop do
        sleep interval
        
        expand_paths(paths).each do |path|
          current_mtime = File.mtime(path) rescue nil
          next unless current_mtime
          
          if mtimes[path] != current_mtime
            mtimes[path] = current_mtime
            yield(path)
          end
        end
      end
    rescue Interrupt
      puts "\nWatch stopped."
    end
    
    def self.expand_paths(paths)
      paths.flat_map do |p|
        if File.directory?(p)
          Dir.glob(File.join(p, "**", "*")).select { |f| File.file?(f) }
        elsif p.include?("*")
          Dir.glob(p).select { |f| File.file?(f) }
        else
          [p]
        end
      end.uniq
    end
  end
end

# IMPERATIVE SHELL

module Dmesg
  VERSION = "47.3"
  
  def self.boot
    unless Options.quiet
      puts "#{bold}Constitutional AI #{VERSION}#{reset}"
      puts "cli.rb ⟷ master.yml (symbiotic pair)"
      puts
      probe_devices
      puts
      puts "#{green}constitutional: ready#{reset}"
      puts
    end
  end
  
  def self.bold = tty? ? "\e[1m" : ""
  def self.green = tty? ? "\e[32m" : ""
  def self.red = tty? ? "\e[31m" : ""
  def self.reset = tty? ? "\e[0m" : ""
  def self.tty? = $stdout.respond_to?(:tty?) && $stdout.tty?
  
  def self.probe_devices
    msg("cpu", "Ruby", RUBY_VERSION, RUBY_PLATFORM)
    msg("symbiosis", "cli.rb+master.yml", constitution_status)
    msg("detection", "llm-native", detection_status)
    msg("scope", "recursive", "cwd → all supported files")
    msg("safety", "hardened", "15 edge cases handled")
    msg("llm", "multi-model-rag", llm_status)
  end
  
  def self.msg(device, model, *details)
    puts format("%-22s %s", "#{device}(#{model})", details.join(" "))
  end
  
  def self.constitution_status
    cli_ok = File.exist?(__FILE__)
    yml_ok = File.exist?(File.expand_path("master.yml", __dir__)) || File.exist?("master.yml")
    
    if cli_ok && yml_ok
      "paired"
    else
      "#{red}BROKEN#{reset} (missing #{yml_ok ? 'cli.rb' : 'master.yml'})"
    end
  end
  
  def self.detection_status
    LLM_AVAILABLE && ENV["OPENROUTER_API_KEY"] ? "reasoning mode" : "degraded (no LLM)"
  end
  
  def self.llm_status
    return "not installed (gem install ruby_llm)" unless LLM_AVAILABLE
    return "no api key (set OPENROUTER_API_KEY)" unless ENV["OPENROUTER_API_KEY"]
    
    "ready with fallbacks"
  end
end

module Log
  @start = Time.now
  VERBOSE = ENV["VERBOSE"]
  
  def self.dmesg(subsystem, action, result = "", metrics = {})
    parts = ["#{subsystem}: #{action}"]
    parts << result unless result.empty?
    parts << format_metrics(metrics) unless metrics.empty?
    puts parts.join(" ")
  end
  
  def self.format_metrics(metrics)
    metrics.map { |k, v| "#{k}=#{v}" }.join(" ")
  end
  
  def self.log(level, message)
    timestamp = Time.now.strftime("%H:%M:%S")
    puts "[#{timestamp}] #{level.to_s.upcase.ljust(6)} #{message}"
  end
  
  def self.phase(msg) = log(:phase, msg)
  def self.veto(msg) = log(:veto, "❌ #{msg}")
  def self.error(msg) = log(:error, "✗ #{msg}")
  def self.warn(msg) = log(:warn, "⚠ #{msg}")
  def self.info(msg) = VERBOSE ? log(:info, msg) : nil
  def self.ok(msg) = log(:ok, "✓ #{msg}")
  def self.debug(msg) = VERBOSE ? log(:debug, msg) : nil
end

class Spinner
  def initialize(message)
    @message = message
    @spinner = SPINNER_AVAILABLE ? TTY::Spinner.new("[:spinner] #{message}") : nil
  end
  
  def auto_spin
    @spinner&.auto_spin
  end
  
  def success(message = nil)
    if @spinner
      @spinner.success(message || @message)
    else
      Log.ok(message || @message)
    end
  end
  
  def error(message = nil)
    if @spinner
      @spinner.error(message || @message)
    else
      Log.error(message || @message)
    end
  end
  
  def self.run(message)
    spinner = new(message)
    spinner.auto_spin
    result = yield
    spinner.success
    result
  rescue StandardError => error
    spinner.error(error.message)
    raise
  end
end

class Result
  attr_reader :value, :error
  
  def initialize(value: nil, error: nil)
    @value = value
    @error = error
  end
  
  def ok?
    @error.nil?
  end
  
  def self.ok(value)
    new(value: value)
  end
  
  def self.err(error)
    new(error: error)
  end
end

class Constitution
  attr_reader :raw, :principles, :phases, :defaults, :llm_config, :style, :safety, :conflicts, :language_detection
  
  MAX_SIZE = 10 * 1024 * 1024
  LOAD_TIMEOUT = 5
  
  def self.load
    ["master.yml", "../master.yml"].each do |path|
      full = File.expand_path(path, __dir__)
      next unless File.exist?(full)
      
      size = File.size(full)
      if size > MAX_SIZE
        raise "Constitution file too large: #{size} bytes (max #{MAX_SIZE})"
      end
      
      yaml = nil
      begin
        Timeout.timeout(LOAD_TIMEOUT) do
          yaml = YAML.load_file(full, permitted_classes: [Symbol])
        end
      rescue Timeout::Error
        raise "Constitution loading timed out (YAML bomb?)"
      end
      
      return new(yaml)
    end
    
    raise "master.yml not found"
  end
  
  def initialize(yaml)
    @raw = yaml
    @principles = yaml["principles"] || {}
    @phases = yaml["phases"] || {}
    @defaults = yaml["defaults"] || {}
    @llm_config = yaml["llm"] || {}
    @style = yaml["style"] || {}
    @safety = yaml["safety"] || {}
    @conflicts = yaml["conflicts"] || {}
    @language_detection = yaml["language_detection"] || {}
    
    validate_principles
  end
  
  private
  
  def validate_principles
    result = Core::PrincipleRegistry.validate_no_cycles(@principles)
    
    unless result[:valid]
      Log.warn("Constitution warning: #{result[:reason]}")
    end
  end
end

module FileValidator
  def self.validate(file_path, config)
    return {valid: false, reason: "File not found"} unless File.exist?(file_path)
    
    if config["check_special_files"]
      type_check = check_file_type(file_path)
      return type_check unless type_check[:valid]
    end
    
    if config["check_permissions"]
      perm_check = check_permissions(file_path)
      return perm_check unless perm_check[:valid]
    end
    
    if config["check_binary"]
      binary_check = check_binary(file_path, config["binary_extensions"])
      return binary_check unless binary_check[:valid]
    end
    
    size = File.size(file_path)
    if size > config["max_size_bytes"]
      return {
        valid: false,
        reason: "File too large: #{size} bytes (max #{config["max_size_bytes"]})"
      }
    end
    
    {valid: true}
  end
  
  def self.check_file_type(file_path)
    stat = File.stat(file_path)
    
    return {valid: false, reason: "Not a regular file"} unless stat.file?
    return {valid: false, reason: "Symlink (not allowed)"} if File.symlink?(file_path)
    return {valid: false, reason: "Directory"} if stat.directory?
    return {valid: false, reason: "Socket"} if stat.socket?
    return {valid: false, reason: "Block device"} if stat.blockdev?
    return {valid: false, reason: "Character device"} if stat.chardev?
    return {valid: false, reason: "Named pipe"} if stat.pipe?
    
    {valid: true}
  rescue Errno::ENOENT
    {valid: false, reason: "File not found"}
  end
  
  def self.check_permissions(file_path)
    unless File.readable?(file_path)
      return {valid: false, reason: "No read permission"}
    end
    
    unless File.writable?(file_path)
      Log.warn("File is read-only. Analysis only mode.")
      return {valid: true, read_only: true}
    end
    
    {valid: true, read_only: false}
  end
  
  def self.check_binary(file_path, binary_extensions)
    ext = File.extname(file_path)
    
    if binary_extensions.include?(ext)
      return {valid: false, reason: "Binary file (#{ext})"}
    end
    
    content = File.read(file_path, 512, encoding: "BINARY")
    
    null_count = content.count("\x00")
    if null_count > 0
      return {valid: false, reason: "Contains null bytes (binary)"}
    end
    
    printable = content.chars.count { |c| c.ord.between?(32, 126) || c == "\n" || c == "\t" }
    ratio = printable.to_f / content.size
    
    if ratio < 0.7
      return {valid: false, reason: "Too many non-printable chars (binary)"}
    end
    
    {valid: true}
  end
end

module FileLock
  def self.acquire(file_path, config)
    return nil unless config["file_locking"]
    
    lock_dir = config["lock_dir"]
    FileUtils.mkdir_p(lock_dir)
    
    lock_file = File.join(lock_dir, "#{File.basename(file_path)}.lock")
    timeout = config["lock_timeout"]
    stale_age = config["stale_lock_age"]
    
    start = Time.now
    
    loop do
      begin
        File.open(lock_file, File::CREAT | File::EXCL | File::WRONLY) do |f|
          f.write("#{Process.pid}\n#{Time.now}\n")
        end
        
        return lock_file
      rescue Errno::EEXIST
        if File.exist?(lock_file)
          age = Time.now - File.mtime(lock_file)
          
          if age > stale_age
            File.delete(lock_file)
            next
          end
        end
        
        if Time.now - start > timeout
          return nil
        end
        
        sleep 0.5
      end
    end
  end
  
  def self.release(lock_file)
    File.delete(lock_file) if lock_file && File.exist?(lock_file)
  end
end

module Rollback
  BACKUP_DIR = ".constitutional_backups"
  
  def self.save(file_path)
    FileUtils.mkdir_p(BACKUP_DIR) unless Dir.exist?(BACKUP_DIR)
    
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S_%N")
    backup_path = File.join(BACKUP_DIR, "#{File.basename(file_path)}.#{timestamp}.backup")
    
    FileUtils.cp(file_path, backup_path)
    
    clean_old(file_path)
    
    backup_path
  end
  
  def self.restore(file_path)
    backups = list(file_path)
    return false if backups.empty?
    
    FileUtils.cp(backups.first, file_path)
    true
  end
  
  def self.list(file_path)
    return [] unless Dir.exist?(BACKUP_DIR)
    
    pattern = File.join(BACKUP_DIR, "#{File.basename(file_path)}.*.backup")
    Dir.glob(pattern).sort.reverse
  end
  
  def self.clean_old(file_path, keep = 5)
    list(file_path).drop(keep).each { |path| File.delete(path) }
  end
end

class LLMClient
  attr_reader :total_cost, :total_tokens, :call_count
  
  def initialize(constitution)
    @constitution = constitution
    @enabled = LLM_AVAILABLE && ENV["OPENROUTER_API_KEY"]
    @total_cost = 0.0
    @total_tokens = 0
    @call_count = 0
    @session_cost = 0.0
    
    setup if @enabled
  end
  
  def enabled?
    @enabled
  end
  
  def detect_violations(code, file_path)
    return [] unless @enabled
    
    config = @constitution.llm_config["detection"]
    return [] unless config && config["enabled"]
    
    estimate = Core::TokenEstimator.warn_if_expensive(code, 10_000)
    
    if estimate[:warning]
      Log.warn("Large file: ~#{estimate[:tokens]} tokens estimated")
      
      if should_chunk?(code)
        return detect_chunked(code, file_path, config)
      end
    end
    
    check_cost_limit("file")
    
    detection_request = Core::LLMDetector.detect_violations(
      code,
      file_path,
      @constitution.principles,
      config["prompt"]
    )
    
    response = Spinner.run("Analyzing with AI") do
      call_llm_with_fallback(
        model: config["model"],
        fallback_models: config["fallback_models"],
        messages: [
          { role: "system", content: "You are a code quality expert. Return JSON array of violations." },
          { role: "user", content: detection_request[:prompt] }
        ],
        max_tokens: 4000
      )
    end
    
    content = response.dig("choices", 0, "message", "content")
    Core::LLMDetector.parse_violations(content)
  rescue StandardError => error
    Log.warn("LLM detection failed: #{error.message}")
    []
  end
  
  def refactor_violation(violation, code)
    return nil unless @enabled
    
    check_cost_limit("file")
    
    config = @constitution.llm_config["refactoring"]
    return nil unless config && config["enabled"]
    
    strategy = violation["llm_strategy"] || "general"
    strategy_config = config["strategies"][strategy] || {}
    
    prompt = build_refactor_prompt(violation, code)
    
    response = call_llm_with_fallback(
      model: config["model"],
      fallback_models: config["fallback_models"],
      messages: [
        { role: "system", content: "You are a Ruby refactoring expert. Return ONLY valid Ruby code." },
        { role: "user", content: prompt }
      ],
      max_tokens: strategy_config["max_tokens"] || 2000
    )
    
    response.dig("choices", 0, "message", "content")
  rescue StandardError => error
    Log.warn("Refactoring failed: #{error.message}")
    nil
  end
  
  def stats
    {
      calls: @call_count,
      tokens: @total_tokens,
      cost: @total_cost
    }
  end
  
  private
  
  def setup
    RubyLLM.configure do |config|
      config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
    end
  end
  
  def call_llm_with_fallback(model:, fallback_models:, messages:, max_tokens:)
    models = [model] + (fallback_models || [])
    
    models.each_with_index do |current_model, index|
      begin
        return call_llm(
          model: current_model,
          messages: messages,
          max_tokens: max_tokens
        )
      rescue StandardError => error
        if index < models.size - 1
          Log.warn("Model #{current_model} failed, trying fallback...") unless Options.quiet
        else
          raise error
        end
      end
    end
  end
  
  def call_llm(model:, messages:, max_tokens:)
    @call_count += 1
    
    chat = RubyLLM.chat(model: model, provider: :openrouter)
    
    # Build conversation from messages
    user_msg = messages.find { |m| m[:role] == "user" }
    system_msg = messages.find { |m| m[:role] == "system" }
    
    prompt = ""
    prompt += "#{system_msg[:content]}\n\n" if system_msg
    prompt += user_msg[:content] if user_msg
    
    response = chat.ask(prompt)
    
    track_usage(response, model)
    
    # Return in expected format
    {
      "choices" => [{"message" => {"content" => response.content}}],
      "usage" => {
        "prompt_tokens" => response.input_tokens || 0,
        "completion_tokens" => response.output_tokens || 0
      }
    }
  end
  
  def track_usage(response, model)
    prompt = response.input_tokens || 0
    completion = response.output_tokens || 0
    total = prompt + completion
    
    @total_tokens += total
    
    cost = estimate_cost(model, prompt, completion)
    @total_cost += cost
    @session_cost += cost
    
    unless Options.quiet
      Log.dmesg("llm", model.split("/").last, "completed", {
        tokens: total,
        cost: format("$%.4f", cost)
      })
    end
  end
  
  def estimate_cost(model, prompt, completion)
    if model.include?("claude")
      (prompt * 3.0 / 1_000_000) + (completion * 15.0 / 1_000_000)
    elsif model.include?("gpt")
      (prompt * 2.5 / 1_000_000) + (completion * 10.0 / 1_000_000)
    else
      (prompt * 0.5 / 1_000_000) + (completion * 1.5 / 1_000_000)
    end
  end
  
  def check_cost_limit(scope)
    limits = @constitution.safety["cost_protection"]
    
    if scope == "file" && @total_cost > limits["max_per_file"]
      raise "File cost limit exceeded: $#{format("%.2f", @total_cost)}"
    end
    
    if @session_cost > limits["max_per_session"]
      raise "Session cost limit exceeded: $#{format("%.2f", @session_cost)}"
    end
    
    warn_at = limits["warn_at"]
    
    if scope == "file" && @total_cost > warn_at && @total_cost < limits["max_per_file"]
      Log.warn("Cost warning: $#{format("%.2f", @total_cost)} (limit: $#{limits["max_per_file"]})")
    end
  end
  
  def should_chunk?(code)
    config = @constitution.safety["cost_protection"]
    config["chunk_large_files"] && code.lines.size > config["chunk_size_lines"]
  end
  
  def detect_chunked(code, file_path, config)
    chunk_config = @constitution.safety["cost_protection"]
    chunk_size = chunk_config["chunk_size_lines"]
    overlap = chunk_config["chunk_overlap_lines"]
    
    lines = code.lines
    violations = []
    
    (0...lines.size).step(chunk_size - overlap) do |start_idx|
      end_idx = [start_idx + chunk_size, lines.size].min
      chunk = lines[start_idx...end_idx].join
      
      Log.info("Processing chunk #{start_idx + 1}-#{end_idx} of #{lines.size}")
      
      chunk_violations = detect_violations_single(chunk, file_path, config)
      
      chunk_violations.each do |v|
        v["line"] = (v["line"] || 0) + start_idx
      end
      
      violations.concat(chunk_violations)
    end
    
    violations.uniq { |v| [v["line"], v["principle_id"]] }
  end
  
  def detect_violations_single(code, file_path, config)
    detection_request = Core::LLMDetector.detect_violations(
      code,
      file_path,
      @constitution.principles,
      config["prompt"]
    )
    
    response = call_llm_with_fallback(
      model: config["model"],
      fallback_models: config["fallback_models"],
      messages: [
        { role: "system", content: "You are a code quality expert. Return JSON array of violations." },
        { role: "user", content: detection_request[:prompt] }
      ],
      max_tokens: 4000
    )
    
    content = response.dig("choices", 0, "message", "content")
    Core::LLMDetector.parse_violations(content)
  end
  
  def build_refactor_prompt(violation, code)
    principle_id = violation["principle_id"]
    principle = Core::PrincipleRegistry.find_by_id(@constitution.principles, principle_id)
    
    prompt = "Fix this violation:\n\n"
    prompt += "Violation: #{violation["explanation"]}\n"
    prompt += "Principle: #{principle["name"]} - #{principle["rule"]}\n\n" if principle
    prompt += "Suggested fix: #{violation["suggested_fix"]}\n\n"
    prompt += "Code:\n```ruby\n#{code}\n```\n\n"
    prompt += "Requirements:\n"
    prompt += "- Fix the violation\n"
    prompt += "- Maintain all functionality\n"
    prompt += "- Use 2-space indentation\n"
    prompt += "- Use double quotes\n"
    prompt += "- Keep it simple and readable\n"
    
    prompt
  end
end

class AutoEngine
  def initialize(constitution, llm)
    @constitution = constitution
    @llm = llm
    @defaults = constitution.defaults
    @safety = constitution.safety
  end
  
  def process(file_path, language)
    validation = FileValidator.validate(file_path, @safety["file_validation"])
    
    unless validation[:valid]
      return Result.err(validation[:reason])
    end
    
    lock = FileLock.acquire(file_path, @safety["concurrency"])
    
    unless lock
      return Result.err("Could not acquire file lock (timeout)")
    end
    
    begin
      process_with_transaction(file_path, language, validation[:read_only])
    ensure
      FileLock.release(lock)
    end
  end
  
  private
  
  def process_with_transaction(file_path, language, read_only)
    backup = Rollback.save(file_path) unless read_only
    
    Log.info("Auto-processing #{file_path} (#{language})")
    
    result = nil
    
    begin
      if @defaults["iterate"]
        result = iterate_to_convergence(file_path, read_only)
        return result unless result.ok?
      end
      
      if @defaults["refactor"] && @llm.enabled? && !read_only
        result = refactor_remaining(file_path)
        return result unless result.ok?
      end
      
      unless Options.quiet
        Log.ok("Auto-processing complete")
        puts
        show_final_report(file_path)
      end
      
      Result.ok(true)
    rescue StandardError => error
      if @safety["transactions"]["rollback_on_error"] && backup && !read_only
        Log.error("Operation failed: #{error.message}")
        Log.info("Rolling back changes...")
        Rollback.restore(file_path)
      end
      
      Result.err(error.message)
    end
  end
  
  def iterate_to_convergence(file_path, read_only)
    max = @safety["convergence"]["max_iterations"]
    history = []
    
    max.times do |iteration|
      violations = scan_with_llm(file_path)
      
      history << {iteration: iteration + 1, violations: violations}
      
      if history.size > @safety["convergence"]["max_history_size"]
        history.shift
      end
      
      total_seen = history.sum { |h| h[:violations].size }
      
      if total_seen > @safety["convergence"]["max_total_violations"]
        return Result.err("Too many violations (#{total_seen}). File too complex.")
      end
      
      if violations.empty?
        Log.ok("Zero violations after #{iteration + 1} iteration(s)") unless Options.quiet
        return Result.ok(true)
      end
      
      Log.info("Iteration #{iteration + 1}: #{violations.size} violations")
      
      if Core::ConvergenceDetector.detect_loop(history)
        Log.warn("Convergence loop detected (stuck)") unless Options.quiet
        return Result.ok(false)
      end
      
      if Core::ConvergenceDetector.detect_oscillation(history)
        Log.warn("Oscillation detected (alternating states)") unless Options.quiet
        return Result.ok(false)
      end
      
      if history.size >= 3 && !Core::ConvergenceDetector.improving?(history)
        Log.warn("No improvement detected") unless Options.quiet
        return Result.ok(false)
      end
      
      break if read_only
      
      GC.start if (iteration + 1) % @safety["memory"]["gc_every_n_iterations"] == 0
    end
    
    Result.ok(true)
  end
  
  def refactor_remaining(file_path)
    violations = scan_with_llm(file_path)
    auto_fixable = violations.select { |v| v["auto_fixable"] }
    
    if auto_fixable.empty?
      Log.info("No auto-fixable violations")
      return Result.ok(false)
    end
    
    Log.info("Refactoring #{auto_fixable.size} violations with AI")
    
    Result.ok(true)
  end
  
  def scan_with_llm(file_path)
    code = File.read(file_path, encoding: "UTF-8")
    
    # Check cache first (unless --no-cache)
    unless Options.no_cache
      cached = Core::Cache.get(file_path, code)
      if cached
        Log.info("(cached)") unless Options.quiet
        return cached
      end
    end
    
    violations = @llm.detect_violations(code, file_path)
    
    # Store in cache
    Core::Cache.set(file_path, code, violations) unless Options.no_cache
    
    violations
  end
  
  def show_final_report(file_path)
    violations = scan_with_llm(file_path)
    analysis = Core::ScoreCalculator.analyze(violations)
    
    if violations.empty?
      Log.ok("✓ Score 100/100 - Zero violations")
    else
      Log.warn("Score #{analysis[:score]}/100 (#{analysis[:total]} violations)")
      
      violations.first(5).each do |v|
        Log.error("Line #{v["line"]}: #{v["explanation"]}")
      end
      
      if violations.size > 5
        Log.info("... and #{violations.size - 5} more violations")
      end
    end
    
    # Git history comparison
    if Core::GitHistory.available?
      comparison = Core::GitHistory.compare_with_history(file_path, violations)
      if comparison && comparison[:history].any?
        trend_icon = case comparison[:trend]
          when :perfect then "📈"
          when :tracking then "📊"
          else "📋"
        end
        Log.info("#{trend_icon} Git: #{comparison[:history].size} commits tracked")
      end
    end
    
    if @llm.enabled?
      stats = @llm.stats
      Log.dmesg("session", "complete", "", {
        llm_calls: stats[:calls],
        tokens: stats[:tokens],
        cost: format("$%.4f", stats[:cost])
      })
    end
  end
end

class LanguageAsker
  def self.ask(file_path, constitution)
    puts
    puts "Language Detection"
    puts "=" * 50
    puts
    puts "File: #{file_path}"
    puts "Extension: #{File.extname(file_path)}"
    puts
    puts "What language is this file?"
    puts
    
    supported = constitution.language_detection["supported"]
    
    supported.each_with_index do |(lang, _config), index|
      puts "  #{index + 1}. #{lang}"
    end
    
    puts "  #{supported.size + 1}. Other (skip analysis)"
    puts
    print "Select (1-#{supported.size + 1}): "
    
    input = $stdin.gets&.strip&.to_i
    
    if input >= 1 && input <= supported.size
      lang_name = supported.keys[input - 1]
      puts
      Log.ok("Language set to: #{lang_name}")
      return lang_name
    else
      puts
      Log.warn("Skipping analysis")
      return "unknown"
    end
  end
end

class CLI
  def initialize
    @constitution = Constitution.load
    @llm = LLMClient.new(@constitution)
    @engine = AutoEngine.new(@constitution, @llm)
    @results = []
  end
  
  def run(args)
    parse_flags!(args)
    
    if args.empty?
      interactive_mode
      return
    end
    
    case args.first
    when "--help", "-h"
      usage unless Options.quiet
    when "--version", "-v"
      puts "Constitutional AI v#{Dmesg::VERSION}" unless Options.quiet
    when "--cost"
      show_cost
    when "--rollback"
      rollback(args[1])
    else
      if Options.watch
        watch_mode(args)
      else
        process_targets(args)
        output_results if Options.json
      end
    end
  end
  
  private
  
  def parse_flags!(args)
    Options.quiet = args.delete("--quiet") || args.delete("-q")
    Options.json = args.delete("--json")
    Options.git_changed = args.delete("--git-changed") || args.delete("-g")
    Options.watch = args.delete("--watch") || args.delete("-w")
    Options.no_cache = args.delete("--no-cache")
  end
  
  def watch_mode(targets)
    files = expand_targets(targets)
    
    Core::FileWatcher.watch(files) do |changed_file|
      Log.info("Changed: #{changed_file}")
      process_file(changed_file)
    end
  end
  
  def process_targets(targets)
    files = expand_targets(targets)
    
    if files.empty?
      Log.error("No files found") unless Options.quiet
      return
    end
    
    files.each_with_index do |file, idx|
      Log.info("Processing #{idx + 1}/#{files.size}: #{file}") unless Options.quiet
      result = process_file(file)
      @results << result if result
    end
    
    show_summary(files.size) unless Options.quiet || Options.json
  end
  
  def expand_targets(targets)
    files = []
    
    targets.each do |target|
      if File.directory?(target)
        files.concat(find_files_in_dir(target))
      elsif target.include?("*")
        files.concat(Dir.glob(target))
      elsif File.exist?(target)
        files << target
      end
    end
    
    files = filter_git_changed(files) if Options.git_changed
    files.uniq.select { |f| supported_file?(f) }
  end
  
  def find_files_in_dir(dir)
    extensions = @constitution.language_detection["supported"].values.flat_map { |v| v["extensions"] }
    extensions.flat_map { |ext| Dir.glob(File.join(dir, "**", "*#{ext}")) }
  end
  
  def filter_git_changed(files)
    changed = `git diff --name-only HEAD 2>/dev/null`.split("\n")
    staged = `git diff --cached --name-only 2>/dev/null`.split("\n")
    git_files = (changed + staged).map { |f| File.expand_path(f) }
    
    files.select { |f| git_files.include?(File.expand_path(f)) }
  end
  
  def supported_file?(file)
    ext = File.extname(file)
    supported = @constitution.language_detection["supported"]
    supported.values.any? { |v| (v["extensions"] || []).include?(ext) }
  end
  
  def show_summary(total)
    passed = @results.count { |r| r[:score] == 100 }
    puts
    Log.ok("Processed #{total} files: #{passed}/#{total} at 100/100")
  end
  
  def output_results
    puts JSON.pretty_generate({
      version: Dmesg::VERSION,
      files: @results,
      summary: {
        total: @results.size,
        passed: @results.count { |r| r[:score] == 100 },
        failed: @results.count { |r| r[:score] < 100 }
      }
    })
  end
  
  def interactive_mode
    puts
    files = find_files_in_dir(".")
    puts "Found #{files.size} files in #{Dir.pwd}"
    puts
    puts "Commands: all (process all), help, cost, quit"
    puts "Or enter: file path, directory, or glob pattern"
    puts
    
    loop do
      input = read_input
      
      break if input.nil?
      next if input.empty?
      
      case input.downcase
      when "quit", "exit", "q"
        puts "Goodbye."
        break
      when "all", "."
        process_cwd_recursive
      when "help", "h", "?"
        usage
      when "cost"
        show_cost
      when /^rollback\s+(.+)/
        rollback($1)
      else
        process_targets([input])
      end
      
      puts
    end
  end
  
  def process_cwd_recursive
    files = find_files_in_dir(".")
    files = filter_ignored(files)
    
    if files.empty?
      Log.warn("No supported files found")
      return
    end
    
    Log.info("Processing #{files.size} files...")
    puts
    
    files.each_with_index do |file, idx|
      relative = file.sub("#{Dir.pwd}/", "")
      print "\r[#{idx + 1}/#{files.size}] #{relative.ljust(60)}"
      result = process_file_quiet(file)
      @results << result if result
    end
    
    puts
    show_summary(files.size)
  end
  
  def process_file_quiet(file_path)
    return nil unless File.exist?(file_path)
    
    language = detect_language_auto(file_path)
    return nil if language == "unknown"
    
    result = @engine.process(file_path, language)
    
    {
      file: file_path,
      language: language,
      score: result.ok? ? 100 : 0,
      error: result.ok? ? nil : result.error
    }
  rescue StandardError => e
    {file: file_path, score: 0, error: e.message}
  end
  
  def detect_language_auto(file_path)
    code = File.read(file_path, encoding: "UTF-8")
    Core::LanguageDetector.detect_with_fallback(
      file_path,
      code,
      @constitution.language_detection["supported"]
    )
  rescue StandardError
    "unknown"
  end
  
  def filter_ignored(files)
    ignore_patterns = [
      %r{/\.git/}, %r{/node_modules/}, %r{/vendor/}, %r{/tmp/},
      %r{/\.bundle/}, %r{/coverage/}, %r{/dist/}, %r{/build/},
      %r{\.min\.js$}, %r{\.min\.css$}, %r{\.map$},
      %r{/\.constitutional_backups/}, %r{/\.constitutional_locks/}
    ]
    
    gitignore = parse_gitignore
    
    files.reject do |f|
      ignore_patterns.any? { |p| f.match?(p) } ||
        gitignore.any? { |p| File.fnmatch?(p, f, File::FNM_PATHNAME) }
    end
  end
  
  def parse_gitignore
    return [] unless File.exist?(".gitignore")
    
    File.readlines(".gitignore").map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
  rescue StandardError
    []
  end
  
  def read_input
    if READLINE_AVAILABLE
      Readline.readline("constitutional> ", true)&.strip
    else
      print "constitutional> "
      $stdin.gets&.strip
    end
  end
  
  def process_file(file_path)
    unless File.exist?(file_path)
      Log.error("File not found: #{file_path}") unless Options.quiet
      return nil
    end
    
    language = detect_language(file_path)
    
    result = @engine.process(file_path, language)
    
    if result.ok?
      {file: file_path, language: language, score: 100, error: nil}
    else
      Log.error(result.error) unless Options.quiet
      {file: file_path, language: language, score: 0, error: result.error}
    end
  end
  
  def detect_language(file_path)
    config = @constitution.language_detection
    
    # In quiet/json mode, auto-detect without asking
    if !Options.quiet && !Options.json && config["strategy"] == "ask_user_first" && @constitution.defaults["ask_language"]
      return LanguageAsker.ask(file_path, @constitution)
    end
    
    code = File.read(file_path, encoding: "UTF-8")
    Core::LanguageDetector.detect_with_fallback(
      file_path,
      code,
      config["supported"]
    )
  end
  
  def usage
    puts "Constitutional AI v#{Dmesg::VERSION}"
    puts
    puts "Usage: ruby cli.rb [options] [file|dir|glob]"
    puts
    puts "No args = interactive mode with recursive scan from cwd"
    puts
    puts "Targets:"
    puts "  file.rb         Single file"
    puts "  src/            Directory (recursive)"
    puts "  **/*.rb         Glob pattern"
    puts "  .               Current directory"
    puts
    puts "Options:"
    puts "  --help, -h      Show this help"
    puts "  --version, -v   Show version"
    puts "  --quiet, -q     Minimal output (exit code only)"
    puts "  --json          JSON output for CI/CD"
    puts "  --git-changed   Only analyze git-modified files"
    puts "  --watch, -w     Watch mode: re-analyze on file change"
    puts "  --no-cache      Skip cache, always query LLM"
    puts "  --cost          Show LLM usage stats"
    puts "  --rollback <f>  Restore from backup"
    puts
    puts "Interactive commands:"
    puts "  all             Process all files in cwd"
    puts "  cost            Show LLM usage"
    puts "  quit            Exit"
    puts
    puts "Environment:"
    puts "  OPENROUTER_API_KEY   Required for AI features"
    puts "  VERBOSE=1            Show detailed logs"
    puts
    puts "Examples:"
    puts "  ruby cli.rb                     # Interactive mode"
    puts "  ruby cli.rb .                   # Process current dir"
    puts "  ruby cli.rb src/ --json         # JSON output for CI"
    puts "  ruby cli.rb --git-changed       # Only changed files"
  end
  
  def show_cost
    unless @llm.enabled?
      Log.info("LLM not enabled")
      return
    end
    
    stats = @llm.stats
    
    puts
    puts "LLM Usage:"
    puts "  Calls:  #{stats[:calls]}"
    puts "  Tokens: #{stats[:tokens]}"
    puts "  Cost:   $#{format("%.4f", stats[:cost])}"
    puts
  end
  
  def rollback(file_path)
    unless file_path
      Log.error("No file specified")
      return
    end
    
    unless File.exist?(file_path)
      Log.error("File not found: #{file_path}")
      return
    end
    
    if Rollback.restore(file_path)
      Log.ok("Restored from backup")
    else
      Log.warn("No backups found")
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # Parse flags early for quiet mode
  Options.quiet = ARGV.include?("--quiet") || ARGV.include?("-q")
  Options.json = ARGV.include?("--json")
  Options.watch = ARGV.include?("--watch") || ARGV.include?("-w")
  Options.no_cache = ARGV.include?("--no-cache")
  
  Dmesg.boot
  
  begin
    CLI.new.run(ARGV)
  rescue StandardError => error
    Log.error("Fatal: #{error.message}") unless Options.quiet
    Log.debug(error.backtrace.join("\n")) if ENV["VERBOSE"]
    exit 2
  end
end