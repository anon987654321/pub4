#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# Force UTF-8 encoding for OpenBSD compatibility
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Add user gem path for OpenBSD (gems installed with --user-install)
user_gem_dir = File.expand_path("~/.local/share/gem/ruby/#{RUBY_VERSION[0..2]}/gems")
if Dir.exist?(user_gem_dir)
  Dir.glob("#{user_gem_dir}/*/lib").each { |path| $LOAD_PATH.unshift(path) }
end

# MASTER.YML v1.7.0
# Code governance agent with chat-first UX
# Inspired by: Claude Code, Aider, OpenCode

require "yaml"
require "json"
require "fileutils"
require "optparse"
require "digest"
require "net/http"
require "uri"
require "readline"
require "timeout"
require "shellwords"

# History file for readline
HISTORY_FILE = File.expand_path("~/.convergence_history")

# Model aliases for quick switching
MODEL_ALIASES = {
  "fast" => "deepseek/deepseek-chat",
  "smart" => "anthropic/claude-sonnet-4",
  "opus" => "anthropic/claude-opus-4",
  "cheap" => "deepseek/deepseek-chat",
  "gpt" => "openai/gpt-4o",
  "local" => "ollama/llama3"
}.freeze

# Command aliases
COMMAND_ALIASES = {
  "s" => "scan",
  "f" => "fix",
  "c" => "converge",
  "h" => "help",
  "q" => "quit",
  "m" => "model",
  "b" => "browse",
  "?" => "help"
}.freeze

# Auto-install missing dependencies
module DependencyManager
  GEMS = {
    "ferrum" => { pkg: "chromium", desc: "web browsing" },
    "async" => { desc: "async I/O" },
    "falcon" => { desc: "fast web server (Rails 8 default)" },
    "protocol-http" => { desc: "HTTP protocol support" }
  }
  
  PACKAGES = {
    "chromium" => "chromium",
    "piper" => "piper",      # TTS
    "whisper" => "whisper",  # STT
    "sox" => "sox"           # Audio recording
  }
  
  class << self
    def openbsd?
      RUBY_PLATFORM.include?("openbsd") || File.exist?("/bsd")
    end
    
    def install_gem(name)
      puts "Installing gem: #{name}..."
      system("gem install #{name} --no-document") || 
        system("gem install --user-install #{name} --no-document")
    end
    
    def install_package(name)
      return false unless openbsd?
      pkg = PACKAGES[name] || name
      puts "Installing package: #{pkg}..."
      # Try doas first, fall back to pkg_add if already root
      system("doas pkg_add -I #{pkg} 2>/dev/null") ||
        system("pkg_add -I #{pkg} 2>/dev/null")
    end
    
    def ensure_gem(name)
      require name
      true
    rescue LoadError
      if install_gem(name)
        begin
          require name
          true
        rescue LoadError
          false
        end
      else
        false
      end
    end
    
    def ensure_package(name)
      return true if system("which #{name} > /dev/null 2>&1")
      install_package(name)
    end
    
    def setup_all
      # Install core gems that are missing
      GEMS.each do |gem, info|
        begin
          require gem
        rescue LoadError
          if $stdout.tty?
            puts "Optional: #{gem} (#{info[:desc]}) not found"
            install_gem(gem)
            install_package(info[:pkg]) if info[:pkg] && openbsd?
          end
        end
      end
    end
  end
end

# Run dependency check on load
DependencyManager.setup_all if $stdout.tty? && ENV["SKIP_DEPS"] != "1"

# Optional: Ferrum for web browsing
FERRUM_AVAILABLE = begin
  require "ferrum"
  true
rescue LoadError
  false
end

# Optional: Falcon for async web server
FALCON_AVAILABLE = begin
  require "async"
  require "async/http/server"
  require "async/http/endpoint"
  true
rescue LoadError
  false
end

# ANSI colors (disabled if terminal doesn't support)
module C
  ENABLED = $stdout.tty? && ENV['TERM'] && ENV['TERM'] != 'dumb'
  
  def self.g(s) ENABLED ? "[32m#{s}[0m" : s end
  def self.r(s) ENABLED ? "[31m#{s}[0m" : s end
  def self.y(s) ENABLED ? "[33m#{s}[0m" : s end
  def self.d(s) ENABLED ? "[90m#{s}[0m" : s end
  def self.b(s) ENABLED ? "[1m#{s}[0m" : s end
end

# Graceful AST/RuboCop dependency handling
begin
  require "parser/current"
  require "rubocop"
  AST_AVAILABLE = true
rescue LoadError
  AST_AVAILABLE = false
end

# Result monad for Railway Oriented Programming
class Result
  attr_reader :value, :error

  def initialize(value: nil, error: nil)
    @value = value
    @error = error
    @success = error.nil?
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def and_then
    return self if failure?
    yield(value)
  end

  def or_else(default)
    success? ? value : default
  end

  def self.success(value)
    new(value: value)
  end

  def self.failure(error)
    new(error: error)
  end
end

# Logger - dmesg-style output
module Logger
  @start_time = Time.now
  @indicators = {}
  @prefixes = {}
  @quiet = false
  @verbose = false
  @debug = false

  class << self
    def init(config)
      ux = config["ux"] || {}
      @indicators = ux["indicators"] || {}
      @prefixes = ux["prefixes"] || {}
      @timing_enabled = ux.dig("timing", "enabled")
      @timing_threshold = ux.dig("timing", "threshold_warn") || 1000
    end

    def set_quiet(val)
      @quiet = val
    end

    def set_verbose(val)
      @verbose = val
    end

    def set_debug(val)
      @debug = val
    end

    def operation(subsystem, action)
      return if @quiet
      elapsed = elapsed_ms
      indicator = @prefixes[subsystem] || subsystem
      puts "[#{format_time(elapsed)}] #{indicator}: #{action}"
    end

    def result(subsystem, status, details = "")
      return if @quiet
      elapsed = elapsed_ms
      indicator = status == :success ? @indicators["success"] || "✓" : @indicators["failure"] || "✗"
      puts "[#{format_time(elapsed)}] #{indicator} #{subsystem}: #{details}"
    end

    def state(from, to, context = "")
      return if @quiet
      elapsed = elapsed_ms
      prefix = @prefixes["state"] || "state"
      puts "[#{format_time(elapsed)}] #{prefix}: #{from} → #{to} #{context}"
    end

    def metric(name, value, unit = "")
      return if @quiet || !@verbose
      elapsed = elapsed_ms
      prefix = @prefixes["metric"] || "metric"
      puts "[#{format_time(elapsed)}] #{prefix}: #{name} = #{value}#{unit}"
    end

    def filesystem(action, path)
      return if @quiet || !@verbose
      elapsed = elapsed_ms
      prefix = @prefixes["filesystem"] || "fs"
      puts "[#{format_time(elapsed)}] #{prefix}: #{action} #{path}"
    end

    def validation(check, status)
      return if @quiet
      elapsed = elapsed_ms
      prefix = @prefixes["validation"] || "val"
      indicator = status ? @indicators["success"] || "✓" : @indicators["failure"] || "✗"
      puts "[#{format_time(elapsed)}] #{prefix}: #{check} #{indicator}"
    end

    def info(msg)
      return if @quiet
      elapsed = elapsed_ms
      puts "[#{format_time(elapsed)}] #{msg}"
    end

    def success(msg)
      return if @quiet
      indicator = @indicators["success"] || "✓"
      puts "#{indicator} #{msg}"
    end

    def error(msg)
      elapsed = elapsed_ms
      indicator = @indicators["failure"] || "✗"
      puts "[#{format_time(elapsed)}] #{indicator} #{msg}"
    end

    def debug(msg)
      return unless @debug
      elapsed = elapsed_ms
      puts "[#{format_time(elapsed)}] DEBUG: #{msg}"
    end

    def timed(label)
      start = Time.now
      result = yield
      duration = ((Time.now - start) * 1000).round(2)
      
      if duration > @timing_threshold
        indicator = @indicators["warning"] || "⚠"
        puts "#{indicator} #{label}: #{duration}ms (threshold: #{@timing_threshold}ms)"
      elsif @verbose
        puts "#{label}: #{duration}ms"
      end
      
      result
    end

    private

    def elapsed_ms
      ((Time.now - @start_time) * 1000).round(2)
    end

    def format_time(ms)
      format("%9.2fms", ms)
    end
  end
end

# StateManager - Manages .convergence_* state files
module StateManager
  class << self
    def init(config)
      @config = config
      @tracking = config["tracking"] || {}
      @workflow = config["workflow"] || {}
      @integration = config["integration"] || {}
    end

    def pre_work_snapshot
      return unless @integration["pre_work_snapshot"]
      
      tree_sh = @integration["tree_sh"] || "sh/tree.sh"
      if File.exist?(tree_sh)
        Logger.operation("snapshot", "running tree.sh")
        system("zsh #{tree_sh} . > .convergence_tree.txt 2>/dev/null")
        Logger.filesystem("write", ".convergence_tree.txt")
      end
      
      save_initial_state
    end

    def save_initial_state
      return unless @tracking.dig("violations", "enabled")
      
      state = {
        timestamp: Time.now.iso8601,
        git_sha: `git rev-parse HEAD 2>/dev/null`.strip,
        pwd: Dir.pwd,
        ruby_version: RUBY_VERSION
      }
      
      File.write(".convergence_state.yml", YAML.dump(state))
      Logger.filesystem("write", ".convergence_state.yml")
    end

    def update_context(current_file, violations, progress)
      return unless @tracking.dig("context", "enabled")
      
      context = <<~CTX
        # CONVERGENCE CONTEXT
        
        **Updated**: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
        
        ## Current Focus
        - File: `#{current_file}`
        - Violations: #{violations.size}
        - Laws: #{violations.group_by(&:law).keys.join(', ')}
        
        ## Overall Progress
        - Total Files: #{progress[:total]}
        - Converged: #{progress[:converged]} (#{progress[:percent]}%)
        - Remaining: #{progress[:remaining]}
        - Veto Count: #{progress[:veto]} #{progress[:veto].zero? ? '✓' : '✗'}
        
        ## Blockers
        #{progress[:blockers].empty? ? '- None' : progress[:blockers].map { |b| "- #{b}" }.join("
")}
        
        ## Next Steps
        #{progress[:next_steps].map { |s| "- #{s}" }.join("
")}
      CTX
      
      File.write(".convergence_context.md", context)
      Logger.filesystem("write", ".convergence_context.md")
    end

    def ensure_directories
      dirs = [
        @tracking.dig("violations", "history_dir"),
        @tracking.dig("patterns", "library_dir"),
        @tracking.dig("personas", "journal_dir")
      ].compact
      
      dirs.each do |dir|
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        Logger.debug("ensured directory: #{dir}")
      end
    end
  end
end

# ViolationTracker - Tracks violation recurrence
module ViolationTracker
  class << self
    def init(config)
      @config = config["tracking"] || {}
      @enabled = @config.dig("violations", "enabled")
      @history_dir = @config.dig("violations", "history_dir") || ".convergence_history"
      FileUtils.mkdir_p(@history_dir) if @enabled && !Dir.exist?(@history_dir)
    end

    def track(file, violation)
      return unless @enabled
      
      history_file = "#{@history_dir}/#{File.basename(file)}.jsonl"
      
      entry = {
        timestamp: Time.now.iso8601,
        file: file,
        line: violation.line,
        type: violation.rule,
        law: violation.law,
        severity: violation.severity
      }
      
      File.open(history_file, 'a') { |f| f.puts(JSON.generate(entry)) }
      Logger.debug("tracked violation: #{file}:#{violation.line} #{violation.rule}")
    end

    def analyze_recurrence(file)
      return {} unless @enabled
      
      history_file = "#{@history_dir}/#{File.basename(file)}.jsonl"
      return {} unless File.exist?(history_file)
      
      entries = File.readlines(history_file).map { |l| JSON.parse(l) rescue nil }.compact
      
      # Count by line + type
      recurrence = Hash.new(0)
      entries.each do |entry|
        key = "L#{entry['line']} #{entry['type']}"
        recurrence[key] += 1
      end
      
      recurrence.select { |_, count| count >= 3 }
    end

    def get_recurrence_report(file)
      recurring = analyze_recurrence(file)
      return nil if recurring.empty?
      
      "⚠ Recurring violations detected:
" + recurring.map { |k, v| "  #{k}: #{v}x" }.join("
")
    end
  end
end

# ContextInjector - Injects convergence headers
module ContextInjector
  class << self
    def init(config)
      @config = config["tracking"] || {}
      @enabled = @config.dig("context", "header_injection")
    end

    def inject(file, violations, personas)
      return unless @enabled
      return unless File.exist?(file)
      return unless file.end_with?('.rb')
      
      content = File.read(file)
      
      # Remove old header
      content.sub!(/^# CONVERGENCE:.*?
(?:# LAST_SCAN:.*?
)?(?:# PERSONAS:.*?
)?/, '')
      
      # Build new header
      breakdown = violations.group_by(&:law).transform_values(&:count)
      breakdown_str = breakdown.map { |l, c| "#{l}:#{c}" }.join(' ')
      
      header = "# CONVERGENCE: #{violations.size} violations (#{breakdown_str})
"
      header += "# LAST_SCAN: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
"
      header += "# PERSONAS: #{personas.join(' ')}
" unless personas.empty?
      
      # Inject at top (after shebang if present)
      if content.start_with?('#!')
        lines = content.lines
        content = lines[0] + header + lines[1..].join
      else
        content = header + content
      end
      
      File.write(file, content)
      Logger.debug("injected header: #{file}")
    end

    def remove(file)
      return unless @enabled
      return unless File.exist?(file)
      
      content = File.read(file)
      content.sub!(/^# CONVERGENCE:.*?
(?:# LAST_SCAN:.*?
)?(?:# PERSONAS:.*?
)?/, '')
      File.write(file, content)
      Logger.debug("removed header: #{file}")
    end
  end
end

# PersonaJournal - Logs persona observations
module PersonaJournal
  class << self
    def init(config)
      @config = config["tracking"] || {}
      @enabled = @config.dig("personas", "enabled")
      @journal_dir = @config.dig("personas", "journal_dir") || ".convergence_personas"
      FileUtils.mkdir_p(@journal_dir) if @enabled && !Dir.exist?(@journal_dir)
    end

    def log(persona, observation, context = {})
      return unless @enabled
      
      journal_file = "#{@journal_dir}/#{persona}.log"
      
      entry = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{observation}"
      entry += " | #{context.map { |k, v| "#{k}:#{v}" }.join(' ')}" unless context.empty?
      
      File.open(journal_file, 'a') { |f| f.puts(entry) }
      Logger.debug("persona journal: #{persona} - #{observation}")
    end

    def read(persona)
      journal_file = "#{@journal_dir}/#{persona}.log"
      return [] unless File.exist?(journal_file)
      
      File.readlines(journal_file).map(&:strip)
    end

    def recent(persona, count = 10)
      read(persona).last(count)
    end
  end
end

# RefactoringJournal - Append-only refactoring log
module RefactoringJournal
  class << self
    def init(config)
      @config = config["tracking"] || {}
      @enabled = @config.dig("refactoring", "enabled")
      @journal_file = @config.dig("refactoring", "journal_file") || ".convergence_journal.md"
    end

    def log_fix(file, line, before, after, law, violation_type, rationale = "")
      return unless @enabled
      
      entry = <<~ENTRY
        
        ## #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} | #{file}:#{line}
        
        **BEFORE:**
        ```ruby
        #{before}
        ```
        
        **AFTER:**
        ```ruby
        #{after}
        ```
        
        **LAW:** #{law} (#{violation_type})  
        **RATIONALE:** #{rationale}
        
        ---
      ENTRY
      
      File.open(@journal_file, 'a') { |f| f.write(entry) }
      Logger.debug("logged refactoring: #{file}:#{line}")
    end

    def read_recent(count = 10)
      return [] unless File.exist?(@journal_file)
      
      content = File.read(@journal_file)
      entries = content.split(/^---s*$/).reject(&:empty?)
      entries.last(count)
    end
  end
end

# LearningEngine - Pattern extraction from fixes
module LearningEngine
  class << self
    def init(config)
      @config = config["learning"] || {}
      @enabled = @config["enabled"]
      @capture_fixes = @config["capture_fixes"]
      @min_samples = @config["min_samples"] || 10
      @confidence_threshold = @config["confidence_threshold"] || 0.85
      @pattern_dir = config.dig("tracking", "patterns", "library_dir") || ".convergence_patterns"
      FileUtils.mkdir_p(@pattern_dir) if @enabled && !Dir.exist?(@pattern_dir)
    end

    def capture_fix(file, line, before, after, law, violation_type)
      return unless @enabled && @capture_fixes
      
      pattern_file = "#{@pattern_dir}/#{violation_type}.yml"
      
      entry = {
        timestamp: Time.now.iso8601,
        file: file,
        line: line,
        before: before.strip,
        after: after.strip,
        law: law
      }
      
      patterns = load_patterns(pattern_file)
      patterns << entry
      
      File.write(pattern_file, YAML.dump(patterns))
      Logger.debug("captured pattern: #{violation_type} (#{patterns.size} samples)")
      
      # Auto-generate rule if threshold met
      if patterns.size >= @min_samples
        rule = generate_rule(violation_type, patterns)
        Logger.info("learned pattern: #{violation_type} (confidence: #{rule[:confidence]})")
      end
    end

    def generate_rule(violation_type, patterns)
      # Find most common transformation
      transformations = patterns.map { |p| [p[:before], p[:after]] }
      most_common = transformations.group_by(&:itself).max_by { |_, v| v.size }
      
      return nil unless most_common
      
      before_pattern, after_pattern = most_common.first
      confidence = most_common.last.size.to_f / patterns.size
      
      {
        name: "learned_#{violation_type}",
        law: patterns.first[:law],
        severity: "medium",
        before: before_pattern,
        after: after_pattern,
        confidence: confidence.round(2),
        sample_count: patterns.size,
        learned: true
      }
    end

    def get_suggestions(violation_type)
      pattern_file = "#{@pattern_dir}/#{violation_type}.yml"
      return [] unless File.exist?(pattern_file)
      
      patterns = load_patterns(pattern_file)
      return [] if patterns.empty?
      
      rule = generate_rule(violation_type, patterns)
      return [] unless rule && rule[:confidence] >= @confidence_threshold
      
      [
        "Based on #{rule[:sample_count]} previous fixes:",
        "  → REPLACE: #{rule[:before]}",
        "  → WITH: #{rule[:after]}",
        "  (confidence: #{(rule[:confidence] * 100).round}%)"
      ]
    end

    private

    def load_patterns(file)
      return [] unless File.exist?(file)
      YAML.load_file(file) || []
    rescue
      []
    end
  end
end

# WorkflowStateMachine - State transitions
module WorkflowStateMachine
  class << self
    def init(config)
      @config = config["workflow"] || {}
      @enabled = @config["enabled"]
      @states = @config["states"] || %w[clean scan analyze fix validate commit]
      @state_file = @config["state_file"] || ".convergence_workflow"
      @checkpoints = @config["checkpoints"]
    end

    def current_state
      return "clean" unless File.exist?(@state_file)
      File.read(@state_file).strip
    rescue
      "clean"
    end

    def transition_to(new_state)
      return false unless @enabled
      return false unless @states.include?(new_state)
      
      old_state = current_state
      File.write(@state_file, new_state)
      Logger.state(old_state, new_state, "workflow")
      
      checkpoint if @checkpoints
      true
    end

    def checkpoint
      checkpoint_file = "#{@state_file}.checkpoint"
      checkpoint_data = {
        state: current_state,
        timestamp: Time.now.iso8601,
        pwd: Dir.pwd
      }
      File.write(checkpoint_file, YAML.dump(checkpoint_data))
      Logger.debug("checkpoint saved")
    end

    def restore
      checkpoint_file = "#{@state_file}.checkpoint"
      return nil unless File.exist?(checkpoint_file)
      
      data = YAML.load_file(checkpoint_file)
      Logger.info("restored checkpoint: #{data['state']} @ #{data['timestamp']}")
      data
    rescue
      nil
    end
  end
end

# CommitHooks - Git hook management
module CommitHooks
  class << self
    def init(config)
      @config = config.dig("integration", "commit_hooks") || {}
    end

    def install
      return unless @config["enabled"]
      return unless Dir.exist?(".git")
      
      FileUtils.mkdir_p(".git/hooks") unless Dir.exist?(".git/hooks")
      
      pre_commit_path = ".git/hooks/pre-commit"
      
      pre_commit = <<~HOOK
        #!/usr/bin/env zsh
        # CONVERGENCE PRE-COMMIT HOOK
        # Generated by convergence v1.4.0
        
        if ! command -v convergence >/dev/null 2>&1; then
          echo "✗ convergence not found in PATH"
          exit 1
        fi
        
        echo "→ Running convergence veto check..."
        
        if ! convergence --veto-only --quiet; then
          echo "✗ VETO violations detected"
          echo "  Fix violations or bypass with: git commit --no-verify"
          exit 1
        fi
        
        echo "✓ No veto violations"
        exit 0
      HOOK
      
      File.write(pre_commit_path, pre_commit)
      FileUtils.chmod(0755, pre_commit_path)
      
      Logger.success("installed pre-commit hook")
    end

    def uninstall
      pre_commit_path = ".git/hooks/pre-commit"
      if File.exist?(pre_commit_path)
        content = File.read(pre_commit_path)
        if content.include?("CONVERGENCE PRE-COMMIT HOOK")
          FileUtils.rm(pre_commit_path)
          Logger.success("removed pre-commit hook")
        else
          Logger.error("pre-commit hook exists but wasn't created by convergence")
        end
      else
        Logger.info("no pre-commit hook to remove")
      end
    end
  end
end

# DependencyAnalyzer - Builds file dependency graph
module DependencyAnalyzer
  class << self
    def init(config)
      @config = config
      @enabled = config.dig("priority", "dependency_analysis")
    end

    def analyze(files)
      return {} unless @enabled
      
      dependencies = {}
      
      files.each do |file|
        next unless file.end_with?('.rb')
        
        content = File.read(file) rescue next
        requires = content.scan(/^require(?:_relative)?s+['"]([^'"]+)['"]/).flatten
        
        dependencies[file] = requires.map { |r| resolve_require(r, file) }.compact
      end
      
      Logger.debug("analyzed dependencies: #{files.size} files")
      dependencies
    end

    def sort_by_dependency(files, dependencies)
      # Simple topological sort (leaves first)
      sorted = []
      remaining = files.dup
      
      while remaining.any?
        # Find files with no dependencies in remaining set
        leaves = remaining.select do |f|
          deps = dependencies[f] || []
          (deps & remaining).empty?
        end
        
        if leaves.empty?
          # Circular dependency or external deps, just add rest
          sorted.concat(remaining)
          break
        end
        
        sorted.concat(leaves)
        remaining -= leaves
      end
      
      sorted
    end

    def generate_dot(dependencies)
      output_file = @config.dig("priority", "dependency_graph_output") || ".convergence_deps.dot"
      
      dot = "digraph dependencies {\n"
      dot += "  rankdir=LR;\n"
      dot += "  node [shape=box];\n\n"
      
      dependencies.each do |file, deps|
        short_name = File.basename(file, '.*')
        deps.each do |dep|
          dep_short = File.basename(dep, '.*')
          dot += "  \"#{short_name}\" -> \"#{dep_short}\";\n"
        end
      end
      
      dot += "}\n"
      
      File.write(output_file, dot)
      Logger.filesystem("write", output_file)
      output_file
    end

    private

    def resolve_require(path, from_file)
      # Simple resolution (doesn't handle all cases)
      if path.start_with?('.')
        File.expand_path(path + '.rb', File.dirname(from_file))
      else
        path + '.rb'
      end
    end
  end
end

# PriorityQueue - Intelligent file ordering
module PriorityQueue
  class << self
    def init(config)
      @config = config["priority"] || {}
      @rules = @config["rules"] || []
    end

    def sort(files, violations_by_file, dependencies = {})
      scored_files = files.map do |file|
        score = calculate_score(file, violations_by_file[file] || [], dependencies)
        [file, score]
      end
      
      scored_files.sort_by { |_, score| -score }.map(&:first)
    end

    private

    def calculate_score(file, violations, dependencies)
      score = 0
      
      @rules.each do |rule|
        case rule
        when "veto_count_desc"
          veto_count = violations.count { |v| v.veto? }
          score += veto_count * 1000
        when "dependency_order"
          # Files with fewer dependencies first (leaves)
          deps = dependencies[file] || []
          score -= deps.size * 10
        when "recent_changes_first"
          if File.exist?(file)
            mtime = File.mtime(file)
            age_hours = (Time.now - mtime) / 3600
            score += (1000 - age_hours).clamp(0, 1000)
          end
        when "size_asc"
          if File.exist?(file)
            size = File.size(file)
            score -= size / 1000 # Smaller files first
          end
        end
      end
      
      score
    end
  end
end

# CleanIntegration - sh/clean.sh integration
module CleanIntegration
  class << self
    def init(config)
      @config = config["scanning"] || {}
      @enabled = @config["auto_clean"]
      @clean_script = @config["clean_script"] || "sh/clean.sh"
    end

    def clean(file)
      return unless @enabled
      return unless File.exist?(@clean_script)
      return unless File.exist?(file)
      
      Logger.operation("clean", file)
      `zsh #{@clean_script} #{File.dirname(file)} 2>/dev/null`
      Logger.debug("cleaned: #{file}")
    end

    def clean_all(directory = ".")
      return unless @enabled
      return unless File.exist?(@clean_script)
      
      Logger.operation("clean", "all files in #{directory}")
      `zsh #{@clean_script} #{directory} 2>/dev/null`
      Logger.success("cleaned all files")
    end
  end
end

# Dashboard - Status overview
module Dashboard
  class << self
    def init(config)
      @config = config["dashboard"] || {}
      @enabled = @config["enabled"]
      @format = @config["format"] || "box"
      @show = @config["show"] || []
    end

    def display(results)
      return unless @enabled
      
      stats = calculate_stats(results)
      
      case @format
      when "box"
        display_box(stats)
      when "compact"
        display_compact(stats)
      else
        display_simple(stats)
      end
    end

    private

    def calculate_stats(results)
      total_files = results.size
      converged_files = results.count { |_, violations| violations.empty? }
      remaining_files = total_files - converged_files
      
      all_violations = results.values.flatten
      veto_count = all_violations.count(&:veto?)
      high_count = all_violations.count { |v| v.severity == "high" }
      
      law_breakdown = all_violations.group_by(&:law).transform_values(&:count)
      
      blockers = []
      blockers << "#{veto_count} veto violations" if veto_count > 0
      blockers << "#{high_count} high severity" if high_count > 5
      
      {
        total_files: total_files,
        converged_files: converged_files,
        remaining_files: remaining_files,
        veto_count: veto_count,
        high_count: high_count,
        law_breakdown: law_breakdown,
        progress_percent: total_files.zero? ? 0 : (converged_files * 100 / total_files),
        blockers: blockers
      }
    end

    def display_box(stats)
      width = 40
      puts "┌" + "─" * (width - 2) + "┐"
      puts "│" + " CONVERGENCE STATUS".ljust(width - 2) + "│"
      puts "├" + "─" * (width - 2) + "┤"
      
      @show.each do |item|
        case item
        when "total_files"
          puts "│ Files:       #{stats[:total_files]} total".ljust(width - 1) + "│"
        when "converged_files"
          puts "│ Converged:   #{stats[:converged_files]} (#{stats[:progress_percent]}%)".ljust(width - 1) + "│"
        when "remaining_files"
          puts "│ Remaining:   #{stats[:remaining_files]} files".ljust(width - 1) + "│"
        when "veto_count"
          status = stats[:veto_count].zero? ? "✓" : "✗"
          puts "│ Veto:        #{stats[:veto_count]} #{status}".ljust(width - 1) + "│"
        when "high_severity_count"
          puts "│ High:        #{stats[:high_count]}".ljust(width - 1) + "│"
        when "law_breakdown"
          if stats[:law_breakdown].any?
            puts "│ Laws:".ljust(width - 1) + "│"
            stats[:law_breakdown].sort_by { |_, v| -v }.each do |law, count|
              puts "│   #{law}: #{count}".ljust(width - 1) + "│"
            end
          end
        when "blockers"
          if stats[:blockers].any?
            puts "│ Blockers:".ljust(width - 1) + "│"
            stats[:blockers].each do |blocker|
              puts "│   - #{blocker}".ljust(width - 1) + "│"
            end
          else
            puts "│ Blockers:    None ✓".ljust(width - 1) + "│"
          end
        end
      end
      
      puts "└" + "─" * (width - 2) + "┘"
    end

    def display_compact(stats)
      puts "convergence: #{stats[:converged_files]}/#{stats[:total_files]} (#{stats[:progress_percent]}%) | veto: #{stats[:veto_count]} | high: #{stats[:high_count]}"
    end

    def display_simple(stats)
      puts "Total: #{stats[:total_files]}, Converged: #{stats[:converged_files]} (#{stats[:progress_percent]}%)"
      puts "Veto: #{stats[:veto_count]}, High: #{stats[:high_count]}"
      puts "Remaining: #{stats[:remaining_files]}" if stats[:remaining_files] > 0
    end
  end
end

# InlineSuggestions - Generate fix suggestions
module InlineSuggestions
  class << self
    def init(config)
      @config = config.dig("convergence", "inline_suggestions") || {}
      @enabled = @config["enabled"]
      @max_per_violation = @config["max_per_violation"] || 3
      @format = @config["format"] || "  → {action}: {code}"
    end

    def generate(violation, file_content = nil)
      return [] unless @enabled
      
      suggestions = []
      
      # Add learned pattern suggestions
      learned = LearningEngine.get_suggestions(violation.rule)
      suggestions.concat(learned) if learned.any?
      
      # Add rule-specific suggestions
      case violation.rule
      when "magic_numbers"
        suggestions << format_suggestion("EXTRACT", "TIMEOUT = #{extract_number(violation.details)}")
        suggestions << format_suggestion("REPLACE", "if elapsed > TIMEOUT")
      when "long_method"
        suggestions << format_suggestion("EXTRACT", "extract_#{violation.details.downcase}_logic")
        suggestions << format_suggestion("SPLIT", "into smaller methods")
      when "too_many_params"
        param_count = violation.details[/d+/].to_i
        suggestions << format_suggestion("OBJECT", "replace #{param_count} params with options hash")
        suggestions << format_suggestion("BUILDER", "use builder pattern")
      when "deep_nesting"
        suggestions << format_suggestion("GUARD", "use early return / guard clauses")
        suggestions << format_suggestion("EXTRACT", "extract nested logic to methods")
      when "god_class"
        suggestions << format_suggestion("SPLIT", "extract responsibilities to new classes")
        suggestions << format_suggestion("FACADE", "use facade pattern")
      end
      
      suggestions.take(@max_per_violation)
    end

    private

    def format_suggestion(action, code)
      @format.sub('{action}', action).sub('{code}', code)
    end

    def extract_number(details)
      details[/d+/] || "VALUE"
    end
  end
end

# OpenRouterChat - Chat with LLMs via OpenRouter API
module OpenRouterChat
  ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
  DEFAULT_MODEL = "anthropic/claude-sonnet-4"
  
  class << self
    attr_reader :total_cost, :total_tokens
    
    # Tool definitions for Claude
    TOOLS = [
      {
        type: "function",
        function: {
          name: "read_file",
          description: "Read contents of a file",
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "Absolute or relative file path" }
            },
            required: ["path"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "write_file",
          description: "Write content to a file (creates or overwrites)",
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "File path to write" },
              content: { type: "string", description: "Content to write" }
            },
            required: ["path", "content"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "list_dir",
          description: "List files in a directory",
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "Directory path (default: current)" }
            },
            required: []
          }
        }
      },
      {
        type: "function",
        function: {
          name: "run_command",
          description: "Execute a shell command and return output",
          parameters: {
            type: "object",
            properties: {
              command: { type: "string", description: "Shell command to execute" }
            },
            required: ["command"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "search_files",
          description: "Search for pattern in files (grep)",
          parameters: {
            type: "object",
            properties: {
              pattern: { type: "string", description: "Regex pattern to search" },
              path: { type: "string", description: "Directory to search (default: .)" },
              glob: { type: "string", description: "File glob pattern (default: *)" }
            },
            required: ["pattern"]
          }
        }
      }
    ].freeze
    
    def init(config)
      @config = config
      @api_key = ENV["OPENROUTER_API_KEY"]
      @model = config.dig("chat", "model") || DEFAULT_MODEL
      @conversation = []
      @context_files = []
      @system_prompt = build_system_prompt(config)
      @total_cost = 0.0
      @total_tokens = 0
      @last_cost = 0.0
      @tools_enabled = true
    end
    
    def available?
      !@api_key.nil? && !@api_key.empty?
    end
    
    def set_model(model)
      @model = model
    end
    
    def current_model
      @model
    end
    
    def toggle_tools
      @tools_enabled = !@tools_enabled
      @tools_enabled
    end
    
    def tools_enabled?
      @tools_enabled
    end
    
    # Execute a tool call from Claude
    def execute_tool(name, args)
      case name
      when "read_file"
        path = args["path"]
        if File.exist?(path)
          content = File.read(path, encoding: "UTF-8")
          { success: true, content: content[0..50000] }  # Limit size
        else
          { success: false, error: "File not found: #{path}" }
        end
      when "write_file"
        path = args["path"]
        content = args["content"]
        begin
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
          { success: true, message: "Wrote #{content.bytesize} bytes to #{path}" }
        rescue => e
          { success: false, error: e.message }
        end
      when "list_dir"
        path = args["path"] || "."
        if Dir.exist?(path)
          entries = Dir.entries(path).reject { |e| e.start_with?(".") }.sort
          { success: true, entries: entries }
        else
          { success: false, error: "Directory not found: #{path}" }
        end
      when "run_command"
        command = args["command"]
        begin
          output = `#{command} 2>&1`
          { success: $?.success?, output: output[0..20000], exit_code: $?.exitstatus }
        rescue => e
          { success: false, error: e.message }
        end
      when "search_files"
        pattern = args["pattern"]
        path = args["path"] || "."
        glob = args["glob"] || "*"
        begin
          output = `grep -rn --include='#{glob}' '#{pattern}' #{path} 2>&1 | head -50`
          { success: true, matches: output }
        rescue => e
          { success: false, error: e.message }
        end
      else
        { success: false, error: "Unknown tool: #{name}" }
      end
    end
    
    def add_context_file(path)
      return false unless File.exist?(path)
      content = File.read(path, encoding: "UTF-8")
      @context_files << { path: path, content: content }
      true
    end
    
    def add_context(name, content)
      @context_files << { path: "[#{name}]", content: content }
    end
    
    def clear_context_files
      @context_files = []
    end
    
    def chat(message, retries: 3)
      return Result.failure("OPENROUTER_API_KEY not set") unless available?

      @conversation << { role: "user", content: message }

      # Tool execution loop
      max_tool_rounds = 10
      tool_round = 0
      final_content = ""

      loop do
        response = nil
        retries.times do |i|
          response = send_request
          break unless response[:error]&.include?("timeout") || response[:error]&.include?("rate")
          sleep(2 ** i)
        end

        return Result.failure(response[:error]) if response[:error]

        if response[:usage]
          @total_tokens += response[:usage][:total_tokens] || 0
          @last_cost = response[:usage][:cost] || 0.0
          @total_cost += @last_cost
        end

        if response[:tool_calls] && !response[:tool_calls].empty? && @tools_enabled
          tool_round += 1
          break if tool_round > max_tool_rounds

          @conversation << { role: "assistant", content: response[:content], tool_calls: response[:tool_calls] }

          response[:tool_calls].each do |tc|
            func = tc["function"]
            name = func["name"]
            args = JSON.parse(func["arguments"]) rescue {}

            puts C.d("[Tool] #{name}(#{args.map { |k,v| "#{k}=#{v.to_s[0..30]}" }.join(", ")})")
            result = execute_tool(name, args)
            puts C.d("[Tool] -> #{result[:success] ? 'OK' : 'FAIL'}")

            @conversation << { role: "tool", tool_call_id: tc["id"], content: JSON.generate(result) }
          end
          next
        end

        final_content = response[:content] || ""
        break
      end

      assistant_message = final_content.to_s.gsub(/[^ -~]/, '')
      @conversation << { role: "assistant", content: assistant_message }
      Result.success(assistant_message)
    end
    def last_cost
      @last_cost
    end
    
    def clear_conversation
      @conversation = []
      @context_files = []
      Logger.info("conversation cleared")
    end
    
    def conversation_length
      @conversation.size
    end
    
    def save_session(path)
      data = { model: @model, conversation: @conversation, context_files: @context_files.map { |f| f[:path] } }
      File.write(path, data.to_yaml)
    end
    
    def restore_session(path)
      return false unless File.exist?(path)
      data = YAML.load_file(path)
      @model = data[:model] || @model
      @conversation = data[:conversation] || []
      (data[:context_files] || []).each { |p| add_context_file(p) }
      true
    end
    
    def export_conversation
      @conversation.dup
    end
    
    def import_conversation(conv)
      @conversation = conv || []
    end
    
    def token_estimate
      # Rough estimate: ~4 chars per token
      total_chars = @conversation.sum { |m| m[:content].to_s.length }
      total_chars += @system_prompt.to_s.length
      total_chars += @context_files.sum { |f| f[:content].to_s.length }
      (total_chars / 4.0).to_i
    end
    
    def model_name
      @model || DEFAULT_MODEL
    end
    
    def set_persona_prompt(prompt)
      @persona_prompt = prompt
    end
    
    def clear_persona
      @persona_prompt = nil
    end
    
    private
    
    def build_system_prompt(config)
      laws = (config["laws"] || {}).map { |name, data| "#{name}: #{data['principle']}" }.join("\n")
      
      # Get tree context if available
      tree = ""
      if File.exist?(".convergence_tree.txt")
        tree = File.read(".convergence_tree.txt", encoding: "UTF-8").lines.first(50).join
      end
      
      <<~PROMPT
        You are Master.yml, a code governance agent on OpenBSD.
        Current directory: #{Dir.pwd}
        
        FILES:
        #{tree}
        
        TOOLS AVAILABLE:
        - ```zsh``` blocks execute shell commands
        - ```ruby``` blocks execute Ruby code
        - /browse <url> fetches web pages (you can ask user to run this)
        - /search <query> searches DuckDuckGo
        
        DIRECT COMMANDS (output these and they auto-execute):
        - /view <file> [start] [end] - View file with line numbers
        - /edit <file> <line> "<old>" "<new>" - Replace text at specific line
        - /grep <pattern> [path] - Search files for pattern
        - /create <file> - Create new file
        - /diff [file] - Show uncommitted changes
        - /todo add <task> - Track a task
        
        AUTONOMOUS RESEARCH:
        Before answering technical questions, CHECK LATEST DOCS:
        - Ruby: https://docs.ruby-lang.org/en/master/NEWS_md.html
        - Rails: https://rubyonrails.org/blog (or github releases)
        - OpenBSD: https://man.openbsd.org/<topic>
        - Papers: https://ar5iv.org/search?query=<topic> (arXiv HTML)
        - General: use /search to find current info
        
        If you need to verify current syntax, versions, or best practices,
        tell the user: "Let me check the latest docs" then provide a /browse command.
        
        WORKFLOW:
        1. When asked about code: first /view the relevant file
        2. When fixing bugs: /grep to find occurrences, then /edit each
        3. When creating features: /create file, then /edit to populate
        4. Always /diff before suggesting commit
        
        RULES:
        - ONE shell command per response, wrapped in ```zsh```
        - Use ONLY zsh builtins and parameter expansion (NO sed/awk/grep/cut)
        - For file edits prefer /edit over shell
        - NO citations, NO web references, NO explanations
        - Be terse: max 2 sentences outside code blocks
        
        ZSH NATIVE PATTERNS:
        - String replace: ${var//old/new}
        - Case: ${(L)var} ${(U)var}
        - Split to array: arr=( ${(s:,:)var} )
        - Get column: ${${(s:,:)line}[4]}
        - Filter match: ${(M)arr:#*pattern*}
        - Filter exclude: ${arr:#*pattern*}
        - Unique: ${(u)arr}
        - Sort: ${(o)arr}
        - Join: ${(j:,:)arr}
        - Slice: ${arr[1,10]} ${arr[-5,-1]}
        - Trim: ${${var##[[:space:]]#}%%[[:space:]]#}
        
        Core laws: #{laws}
      PROMPT
    end
    
    def send_request
      uri = URI.parse(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      
      request = Net::HTTP::Post.new(uri.path)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request["HTTP-Referer"] = "https://github.com/anon987654321/pub4"
      request["X-Title"] = "Master.yml CLI"
      
      # Build context from added files
      context = @context_files.map { |f| "--- #{f[:path]} ---\n#{f[:content]}" }.join("\n\n")
      
      # Use persona prompt if set, otherwise default system prompt
      base_prompt = @persona_prompt || @system_prompt
      
      # Add context analysis instruction when files are loaded
      context_instruction = ""
      unless context.empty?
        context_instruction = <<~INST
          
          IMPORTANT: Files have been loaded into your context below.
          When asked about code, bugs, or features - ANALYZE THESE FILES FIRST.
          Do NOT search the web for generic solutions. Read the actual code provided.
          If asked to "find" or "fix" something, look in the CONTEXT FILES below.
        INST
      end
      
      system_with_context = context.empty? ? base_prompt : "#{base_prompt}#{context_instruction}\n\nCONTEXT FILES:\n#{context}"
      
      messages = [{ role: "system", content: system_with_context }] + @conversation
      
      payload = {
        model: @model,
        messages: messages,
        max_tokens: 4096,
        temperature: @persona_prompt ? 0.9 : 0.7
      }
      
      # Add tools if enabled
      payload[:tools] = TOOLS if @tools_enabled
      
      request.body = JSON.generate(payload)
      
      response = http.request(request)
      body = JSON.parse(response.body)
      
      if response.code.to_i == 200
        message = body.dig("choices", 0, "message")
        content = message["content"]
        tool_calls = message["tool_calls"]
        usage = body["usage"] || {}
        
        # Extract cost from OpenRouter response
        cost = 0.0
        if usage["cost"]
          cost = usage["cost"].to_f
        elsif usage["total_tokens"]
          cost = (usage["total_tokens"].to_f / 1000) * 0.003
        end
        
        { content: content, tool_calls: tool_calls, usage: { total_tokens: usage["total_tokens"], cost: cost } }
      else
        error = body.dig("error", "message") || "HTTP #{response.code}"
        { error: error }
      end
    rescue => e
      { error: e.message }
    end
  end
end

# Voice - TTS and STT for voice interaction
# Falls back to browser Web Speech API if native tools unavailable
# Uses Falcon async server (Rails 8 default)
require "socket"
require "json"

module Voice
  WHISPER_MODEL = "base.en"
  WEB_PORT = 8787
  
  # Default voice settings (overridden by persona)
  DEFAULT_MODEL = "en_US-lessac-medium"
  DEFAULT_RATE = 1.0
  
  # ElevenLabs voice IDs (pre-made voices from their library)
  # https://elevenlabs.io/voice-library
  ELEVENLABS_VOICES = {
    "ares" => "pNInz6obpgDQGcFmaJgB",      # Adam - deep male
    "noir" => "VR6AewLTigWG4xSOukaG",       # Arnold - gravelly
    "glitch" => "jBpfuIE2acCO8z3wKNLl",     # Gigi - energetic female
    "cosmic_barista" => "EXAVITQu4vr4xnSDxMaL", # Bella - young female
    "victorian_ghost" => "onwK4e9ZLuTAKqWW03F9", # Daniel - British
    "chaos_gremlin" => "jBpfuIE2acCO8z3wKNLl", # Gigi - energetic
    "sleepy_sage" => "yoZ06aMxZJJ28mfd3POQ",   # Sam - calm male
    "anxious_guru" => "21m00Tcm4TlvDq8ikWAM",  # Rachel - nervous energy
    "depressed_coach" => "pNInz6obpgDQGcFmaJgB", # Adam - flat
    "southern_alien" => "EXAVITQu4vr4xnSDxMaL",  # Bella - sweet
    "dragon_librarian" => "VR6AewLTigWG4xSOukaG", # Arnold - gruff
    "upside_down" => "jBpfuIE2acCO8z3wKNLl",     # Gigi
    "enthusiastic_mortician" => "21m00Tcm4TlvDq8ikWAM", # Rachel - upbeat
    "jazz_robot" => "pNInz6obpgDQGcFmaJgB",      # Adam - smooth
    "vampire_teacher" => "onwK4e9ZLuTAKqWW03F9", # Daniel - British accent
    "default" => "pNInz6obpgDQGcFmaJgB"          # Adam
  }.freeze
  
  # ElevenLabs voice settings per persona
  ELEVENLABS_SETTINGS = {
    "ares" => { stability: 0.5, similarity: 0.75, style: 0.3 },
    "glitch" => { stability: 0.2, similarity: 0.6, style: 0.8 },    # Unstable
    "noir" => { stability: 0.7, similarity: 0.8, style: 0.2 },      # Steady
    "sleepy_sage" => { stability: 0.8, similarity: 0.7, style: 0.1 }, # Very stable, slow
    "chaos_gremlin" => { stability: 0.15, similarity: 0.5, style: 0.9 }, # Maximum chaos
    "anxious_guru" => { stability: 0.3, similarity: 0.7, style: 0.6 },
    "broken" => { stability: 0.1, similarity: 0.4, style: 0.7 },    # Glitchy
    "default" => { stability: 0.5, similarity: 0.75, style: 0.3 }
  }.freeze
  
  # Audio degradation presets (FFmpeg filter chains)
  # VHS, tape, vinyl, radio, transmission effects
  AUDIO_EFFECTS = {
    "clean" => "",  # No degradation
    "warm" => [
      "lowpass=f=8000",
      "highpass=f=80",
      "equalizer=f=200:t=q:w=1:g=3",
      "acompressor=threshold=-20dB:ratio=4:attack=5:release=50"
    ],
    "vhs" => [
      "lowpass=f=6000",                           # VHS frequency loss
      "highpass=f=100",                           # Rumble
      "aecho=0.8:0.7:15:0.5",                     # Tape echo/smear
      "tremolo=f=0.5:d=0.3",                      # Wow from bad tracking
      "equalizer=f=1000:t=q:w=2:g=-4",            # Hollow midrange
      "volume=0.9"
    ],
    "vhs_heavy" => [
      "lowpass=f=4000",                           # Heavy frequency loss
      "highpass=f=150",                           # More rumble
      "aecho=0.8:0.6:20:0.6",                     # More smear
      "tremolo=f=1.5:d=0.4",                      # Warped tracking
      "chorus=0.5:0.9:50:0.4:0.25:2",             # Tape flutter
      "equalizer=f=800:t=q:w=3:g=-6",             # Very hollow
      "anoisesrc=d=0.001:c=pink:a=0.02[n];[0][n]amix=inputs=2:duration=first",  # Tape hiss
      "volume=0.8"
    ],
    "vinyl" => [
      "lowpass=f=12000",                          # Vinyl rolloff
      "highpass=f=40",                            # Rumble from turntable
      "equalizer=f=100:t=q:w=1:g=4",              # Warm bass boost
      "equalizer=f=8000:t=q:w=1:g=-3",            # High rolloff
      "tremolo=f=0.1:d=0.1",                      # Subtle wow
      "volume=1.1"
    ],
    "vinyl_crackle" => [
      "lowpass=f=10000",
      "highpass=f=50",
      "equalizer=f=100:t=q:w=1:g=5",
      "equalizer=f=3000:t=q:w=2:g=2",             # Presence boost
      "tremolo=f=0.08:d=0.15",                    # Slow wow
      "volume=1.0"
      # Note: real crackle would need external sample or noise gen
    ],
    "radio" => [
      "lowpass=f=5000",                           # AM radio bandwidth
      "highpass=f=300",                           # No bass on AM
      "acompressor=threshold=-15dB:ratio=8:attack=1:release=100",  # Heavy compression
      "equalizer=f=1500:t=q:w=2:g=4",             # Nasal midrange
      "volume=1.4"
    ],
    "shortwave" => [
      "lowpass=f=3500",                           # Narrower bandwidth
      "highpass=f=400",                           # Very thin
      "acompressor=threshold=-10dB:ratio=10:attack=1:release=50",
      "tremolo=f=3:d=0.3",                        # Signal flutter
      "equalizer=f=1200:t=q:w=3:g=6",             # Very nasal
      "volume=1.2"
    ],
    "transmission" => [
      "lowpass=f=4000",                           # Military radio
      "highpass=f=500",                           # Very narrow
      "acompressor=threshold=-8dB:ratio=12:attack=0.5:release=30",  # Crushed
      "aphaser=type=t:speed=0.5:decay=0.3",       # Phase distortion
      "volume=1.3"
    ],
    "phone" => [
      "lowpass=f=3400",                           # Phone bandwidth
      "highpass=f=300",
      "acompressor=threshold=-12dB:ratio=6:attack=2:release=80",
      "equalizer=f=2000:t=q:w=2:g=3",
      "volume=1.2"
    ],
    "cassette" => [
      "lowpass=f=10000",                          # Cassette rolloff
      "highpass=f=60",
      "aecho=0.8:0.5:8:0.4",                      # Head smear
      "tremolo=f=0.3:d=0.15",                     # Wow
      "chorus=0.7:0.9:25:0.4:0.3:2",              # Flutter
      "equalizer=f=150:t=q:w=1:g=2",              # Warm bass
      "volume=0.95"
    ],
    "lo-fi" => [
      "lowpass=f=6000",
      "aresample=8000",                           # Downsample
      "aresample=22050",                          # Upsample (aliasing)
      "equalizer=f=400:t=q:w=2:g=3",
      "volume=1.0"
    ],
    "underwater" => [
      "lowpass=f=800",                            # Heavy muffling
      "highpass=f=100",
      "aphaser=type=t:speed=0.3:decay=0.6",
      "aecho=0.8:0.8:100:0.5",                    # Reverb
      "chorus=0.6:0.9:75:0.5:0.4:3",
      "volume=0.7"
    ],
    "ghostly" => [
      "lowpass=f=5000",
      "highpass=f=200",
      "aecho=0.8:0.9:100:0.7|0.8:0.85:200:0.5",   # Multi-delay reverb
      "aphaser=type=t:speed=0.2:decay=0.7",
      "tremolo=f=0.5:d=0.4",
      "volume=0.6"
    ],
    "broken" => [
      "lowpass=f=3000",
      "highpass=f=200",
      "tremolo=f=5:d=0.6",                        # Rapid flutter
      "chorus=0.3:0.9:20:0.7:0.5:4",              # Pitch instability
      "aphaser=type=t:speed=2:decay=0.5",
      "volume=0.8"
    ]
  }.freeze
  
  class << self
    attr_reader :current_persona, :current_effect
    
    def init(config)
      @config = config
      @enabled = true  # Auto-enable voice
      @queue = Queue.new
      @server = nil
      @personas = config.dig("voice_personas") || {}
      @random_mode = true  # Start in random mode
      @current_effect = "warm"  # Default analog warmth
      @audio_file = nil
      @audio_ready = false
      
      # Pick random chaotic persona on startup
      pick = random_persona
      @current_persona = pick
      apply_persona(pick)
      
      # Check TTS engines in priority order: ElevenLabs > Piper > Browser
      # Try master.yml config first, then env var
      @elevenlabs_key = @personas.dig("config", "elevenlabs_api_key") || ENV["ELEVENLABS_API_KEY"]
      @elevenlabs_model = @personas.dig("config", "elevenlabs_model") || "eleven_turbo_v2_5"
      @elevenlabs_available = !@elevenlabs_key.nil? && !@elevenlabs_key.empty?
      @tts_available = system("which piper > /dev/null 2>&1")
      @stt_available = system("which whisper > /dev/null 2>&1") || 
                       system("which whisper-cpp > /dev/null 2>&1")
      @sox_available = system("which sox > /dev/null 2>&1") ||
                       system("which rec > /dev/null 2>&1")
      @web_tts = !@tts_available && !@elevenlabs_available
      
      if @elevenlabs_available
        puts C.d("TTS: ElevenLabs (#{@elevenlabs_model})")
      elsif @tts_available
        puts C.d("TTS: Piper")
      else
        puts C.d("TTS: Browser (Web Speech API)")
      end
      
      # Auto-start web server for UI
      start_web_server if FALCON_AVAILABLE
    end
    
    def audio_file
      @audio_file
    end
    
    def audio_ready?
      @audio_ready
    end
    
    def clear_audio
      @audio_ready = false
    end
    
    def elevenlabs_available?
      @elevenlabs_available
    end
    
    def set_persona(name)
      name = name.to_s.downcase
      
      # Handle special modes
      if name == "random"
        @random_mode = true
        pick = random_persona
        apply_persona(pick)
        @current_persona = pick
        return pick
      end
      
      @random_mode = false
      if @personas.key?(name)
        apply_persona(name)
        @current_persona = name
        true
      else
        false
      end
    end
    
    def random_persona
      # Exclude 'default' and 'ares' from random for max chaos
      chaotic = @personas.keys - ["default", "ares"]
      chaotic.sample || "ares"
    end
    
    def random_mode?
      @random_mode
    end
    
    # Set audio degradation effect
    def set_effect(name)
      name = name.to_s.downcase
      if name == "random"
        @random_effect_mode = true
        @current_effect = random_effect
        return @current_effect
      end
      
      @random_effect_mode = false
      if AUDIO_EFFECTS.key?(name)
        @current_effect = name
        true
      else
        false
      end
    end
    
    def random_effect
      # Exclude 'clean' from random for max chaos
      chaotic = AUDIO_EFFECTS.keys - ["clean"]
      chaotic.sample || "warm"
    end
    
    def available_effects
      AUDIO_EFFECTS.keys
    end
    
    def apply_persona(name)
      persona = @personas[name] || {}
      @model = find_voice_model(persona["voice_model"] || DEFAULT_MODEL)
      @speech_rate = persona["speech_rate"]&.to_f || DEFAULT_RATE
      @pitch = persona["pitch"]&.to_f || 1.0
      @persona_prompt = persona["system_prompt"]
    end
    
    def persona_prompt
      @persona_prompt
    end
    
    def available_personas
      @personas.keys
    end
    
    def find_voice_model(preferred)
      model_dirs = [
        File.expand_path("~/.local/share/piper-voices"),
        "/usr/share/piper-voices",
        "/usr/local/share/piper-voices"
      ]
      
      # Try preferred model
      model_dirs.each do |dir|
        path = File.join(dir, "#{preferred}.onnx")
        return preferred if File.exist?(path)
      end
      
      # Fall back to default
      DEFAULT_MODEL
    end
    
    def model_name
      @model || DEFAULT_MODEL
    end
    
    def speech_rate
      @speech_rate || DEFAULT_RATE
    end
    
    def available?
      @elevenlabs_available || @tts_available || @stt_available || @web_tts
    end
    
    def tts_available?
      @elevenlabs_available || @tts_available || @web_tts
    end
    
    def stt_available?
      @stt_available && @sox_available
    end
    
    def enabled?
      @enabled
    end
    
    def toggle
      @enabled = !@enabled
      @enabled
    end
    
    def enable
      @enabled = true
    end
    
    def disable
      @enabled = false
    end
    
    # Text-to-speech: ElevenLabs > Piper > Browser
    def speak(text)
      puts C.d("[Voice] speak() called, enabled=#{@enabled}, tts=#{tts_available?}")
      return unless @enabled && tts_available?
      return if text.nil? || text.strip.empty?
      
      # Clean text for speech
      clean = text.gsub(/```.*?```/m, "code block omitted")
                  .gsub(/\[.*?\]\(.*?\)/, "")  # Remove markdown links
                  .gsub(/[#*_`]/, "")           # Remove markdown formatting
                  .strip
      
      return if clean.empty?
      
      # Random mode: pick new persona each utterance
      if @random_mode
        pick = random_persona
        apply_persona(pick)
        @current_persona = pick
      end
      
      # Random effect mode: pick new effect each utterance
      if @random_effect_mode
        @current_effect = random_effect
      end
      
      rate = @speech_rate || DEFAULT_RATE
      pitch_shift = @pitch || 1.0
      
      if @elevenlabs_available
        # ElevenLabs API - highest quality
        speak_elevenlabs(clean)
      elsif @tts_available
        # Piper → FFmpeg analog chain → playback
        speak_piper(clean, rate, pitch_shift)
      elsif @web_tts
        # Queue for browser TTS
        start_web_server unless @server
        @queue << clean
      end
    end
    
    # ElevenLabs TTS via API - saves to file for browser streaming
    def speak_elevenlabs(text)
      voice_id = ELEVENLABS_VOICES[@current_persona] || ELEVENLABS_VOICES["default"]
      settings = ELEVENLABS_SETTINGS[@current_persona] || ELEVENLABS_SETTINGS["default"]
      model = @elevenlabs_model || "eleven_turbo_v2_5"
      
      puts C.d("[ElevenLabs] Persona: #{@current_persona}, Voice: #{voice_id[0..8]}...")
      
      uri = URI("https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")
      
      body = {
        text: text,
        model_id: model,
        voice_settings: {
          stability: settings[:stability],
          similarity_boost: settings[:similarity],
          style: settings[:style],
          use_speaker_boost: true
        }
      }.to_json
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      
      request = Net::HTTP::Post.new(uri)
      request["xi-api-key"] = @elevenlabs_key
      request["Content-Type"] = "application/json"
      request["Accept"] = "audio/mpeg"
      request.body = body
      
      response = http.request(request)
      
      if response.code == "200"
        puts C.g("[ElevenLabs] Got audio (#{response.body.bytesize} bytes)")
        
        # Save to temp file
        @audio_file = "/tmp/ares_audio_#{$$}.mp3"
        
        # Apply analog effects if set
        effect_chain = AUDIO_EFFECTS[@current_effect] || []
        if effect_chain.is_a?(Array) && effect_chain.any?
          raw_file = "/tmp/ares_raw_#{$$}.mp3"
          File.binwrite(raw_file, response.body)
          ffmpeg_fx = effect_chain.join(",")
          system("ffmpeg -y -i #{raw_file.shellescape} -af '#{ffmpeg_fx}' #{@audio_file.shellescape} 2>/dev/null")
          File.delete(raw_file) if File.exist?(raw_file)
        else
          File.binwrite(@audio_file, response.body)
        end
        
        @audio_ready = true
        
        # PLAY the audio locally (OpenBSD: aucat, ffplay, mpv fallback)
        puts C.d("[ElevenLabs] Playing #{@audio_file}...")
        Thread.new do
          system("ffplay -nodisp -autoexit #{@audio_file.shellescape} 2>/dev/null || " \
                 "mpv --no-video #{@audio_file.shellescape} 2>/dev/null || " \
                 "aucat -i #{@audio_file.shellescape} 2>/dev/null || " \
                 "play #{@audio_file.shellescape} 2>/dev/null")
        end
        
        true
      else
        puts C.r("[ElevenLabs] API error: #{response.code} - #{response.body[0..100]}")
        # Fallback to browser TTS on error
        @queue << text if @web_tts
        false
      end
    rescue => e
      puts C.r("[ElevenLabs] Exception: #{e.message}")
      # Silent fail, queue for browser
      @queue << text if @web_tts
      false
    end
    
    # Piper TTS with FFmpeg effects
    def speak_piper(text, rate, pitch_shift)
      Thread.new do
        base_effects = [
          "asetrate=22050*#{pitch_shift}",
          "atempo=#{rate/pitch_shift}"
        ]
        
        effect_chain = AUDIO_EFFECTS[@current_effect] || AUDIO_EFFECTS["warm"]
        effect_filters = effect_chain.is_a?(Array) ? effect_chain : []
        
        ffmpeg_analog = (base_effects + effect_filters + ["volume=1.3"]).join(",")
        
        IO.popen([
          "sh", "-c",
          "echo #{text.shellescape} | piper --model #{@model} --output_raw 2>/dev/null | " \
          "ffmpeg -f s16le -ar 22050 -ac 1 -i - -af '#{ffmpeg_analog}' -f s16le -ar 22050 -ac 1 pipe: 2>/dev/null | " \
          "ffplay -nodisp -autoexit -f s16le -ar 22050 -ac 1 -i - 2>/dev/null || " \
          "play -q -t raw -r 22050 -e signed -b 16 -c 1 - 2>/dev/null || aplay -q -f S16_LE -r 22050 -c 1 - 2>/dev/null"
        ]) { |p| p.read }
      end
    end
    
    # Download Wheatley or other quirky voice models
    def install_voice(name = "wheatley1")
      voice_dir = File.expand_path("~/.local/share/piper-voices")
      FileUtils.mkdir_p(voice_dir)
      
      models = {
        "wheatley1" => "https://huggingface.co/davet2001/wheatley1/resolve/main/wheatley1.onnx",
        "glados" => "https://huggingface.co/csukuangfj/vits-piper-en_US-glados-high/resolve/main/en_US-glados-high.onnx",
        "kronk" => "https://huggingface.co/russdill/kronk/resolve/main/kronk.onnx"
      }
      
      url = models[name]
      return puts "Unknown voice: #{name}. Available: #{models.keys.join(', ')}" unless url
      
      onnx_path = File.join(voice_dir, "#{name}.onnx")
      json_path = File.join(voice_dir, "#{name}.onnx.json")
      
      if File.exist?(onnx_path)
        puts "Voice #{name} already installed"
        return true
      end
      
      puts "Downloading #{name} voice model..."
      system("curl -L -o #{onnx_path.shellescape} #{url.shellescape}")
      
      # Create minimal config JSON if needed
      File.write(json_path, JSON.generate({
        "audio" => {"sample_rate" => 22050},
        "espeak" => {"voice" => "en-us"}
      })) unless File.exist?(json_path)
      
      puts "Installed: #{name}"
      true
    end
    
    # Start Falcon async server for browser TTS
    def start_web_server
      return if @server
      return unless FALCON_AVAILABLE
      
      ip = local_ip
      cli_html_path = File.expand_path("cli.html", __dir__)
      
      @server = Thread.new do
        require "async"
        require "async/http/server"
        require "async/http/endpoint"
        require "protocol/http/body/buffered"
        
        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{WEB_PORT}")
        
        app = proc do |request|
          path = request.path
          
          case path
          when "/", "/cli.html"
            # Serve cli.html with no-cache headers
            if File.exist?(cli_html_path)
              html = File.read(cli_html_path, encoding: "UTF-8")
            else
              html = "<h1>cli.html not found</h1>"
            end
            body = Protocol::HTTP::Body::Buffered.wrap(html)
            Protocol::HTTP::Response[200, {
              "content-type" => "text/html",
              "cache-control" => "no-cache, no-store, must-revalidate",
              "pragma" => "no-cache",
              "expires" => "0"
            }, body]
          when "/poll"
            # Check for queued text OR ready audio
            text = @queue.empty? ? nil : @queue.pop(true) rescue nil
            audio_url = nil
            if Voice.audio_ready? && Voice.audio_file && File.exist?(Voice.audio_file)
              audio_url = "/audio?t=#{Time.now.to_i}"
              Voice.clear_audio
            end
            body = Protocol::HTTP::Body::Buffered.wrap({ 
              text: text, 
              audio: audio_url,
              persona: Voice.current_persona 
            }.to_json)
            Protocol::HTTP::Response[200, {"content-type" => "application/json", "cache-control" => "no-store"}, body]
          when /^\/audio/
            # Serve ElevenLabs audio file
            if Voice.audio_file && File.exist?(Voice.audio_file)
              audio_data = File.binread(Voice.audio_file)
              Voice.clear_audio
              body = Protocol::HTTP::Body::Buffered.wrap(audio_data)
              Protocol::HTTP::Response[200, {
                "content-type" => "audio/mpeg",
                "cache-control" => "no-store"
              }, body]
            else
              Protocol::HTTP::Response[404, {}, nil]
            end
          when "/chat"
            # Handle chat messages via POST
            if request.method == "POST"
              input = request.body&.read.to_s
              data = JSON.parse(input) rescue {}
              message = data["message"]
              if message && OpenRouterChat.available?
                result = OpenRouterChat.chat(message)
                response = result.success? ? result.value : result.error
                
                # Generate ElevenLabs audio if available
                audio_url = nil
                if Voice.elevenlabs_available? && response && !response.empty?
                  if Voice.speak_elevenlabs(response)
                    audio_url = "/audio?t=#{Time.now.to_i}"
                  end
                end
                
                body = Protocol::HTTP::Body::Buffered.wrap({ 
                  response: response,
                  audio: audio_url
                }.to_json)
                Protocol::HTTP::Response[200, {"content-type" => "application/json"}, body]
              else
                body = Protocol::HTTP::Body::Buffered.wrap({ error: "unavailable" }.to_json)
                Protocol::HTTP::Response[503, {"content-type" => "application/json"}, body]
              end
            else
              Protocol::HTTP::Response[405, {}, nil]
            end
          when "/persona"
            # Switch persona via POST
            if request.method == "POST"
              input = request.body&.read.to_s
              data = JSON.parse(input) rescue {}
              name = data["name"]
              if name && Voice.set_persona(name)
                OpenRouterChat.set_persona_prompt(Voice.persona_prompt) if Voice.persona_prompt
                body = Protocol::HTTP::Body::Buffered.wrap({ ok: true, persona: name }.to_json)
                Protocol::HTTP::Response[200, {"content-type" => "application/json"}, body]
              else
                body = Protocol::HTTP::Body::Buffered.wrap({ error: "unknown persona" }.to_json)
                Protocol::HTTP::Response[400, {"content-type" => "application/json"}, body]
              end
            else
              Protocol::HTTP::Response[405, {}, nil]
            end
          else
            Protocol::HTTP::Response[404, {}, nil]
          end
        end
        
        Async do
          server = Async::HTTP::Server.new(app, endpoint)
          server.run
        end
      end
      
      puts C.d("UI: http://#{ip}:#{WEB_PORT}")
    end
    
    def local_ip
      Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }&.ip_address || "127.0.0.1"
    end
    
    # Speech-to-text via Whisper
    def listen(duration: 5)
      return nil unless @enabled && stt_available?
      
      # Record audio with sox/rec
      tmpfile = "/tmp/voice_input_#{$$}.wav"
      
      puts "[listening #{duration}s...]"
      system("rec -q #{tmpfile} rate 16k silence 1 0.1 1% 1 2.0 3% trim 0 #{duration} 2>/dev/null")
      
      return nil unless File.exist?(tmpfile) && File.size(tmpfile) > 1000
      
      # Transcribe with Whisper
      result = `whisper #{tmpfile} --model #{WHISPER_MODEL} --output_format txt 2>/dev/null`.strip
      result = `whisper-cpp -m #{WHISPER_MODEL} -f #{tmpfile} 2>/dev/null`.strip if result.empty?
      
      File.delete(tmpfile) if File.exist?(tmpfile)
      
      result.empty? ? nil : result
    end
    
    def status
      parts = []
      tts_engine = if @elevenlabs_available
        "elevenlabs"
      elsif @tts_available
        "piper"
      elsif @web_tts
        "web"
      else
        "no"
      end
      parts << "tts:#{tts_engine}"
      parts << (@enabled ? "on" : "off")
      parts << "persona:#{@random_mode ? 'random' : @current_persona}"
      parts << "fx:#{@random_effect_mode ? 'random' : @current_effect}"
      parts.join(" ")
    end
    
    def stop_server
      @server&.kill
      @server = nil
    end
  end
end

# Web - Autonomous web agent via Ferrum
# Supports persistent browsing sessions, screenshots for LLM reasoning,
# and structured page extraction for navigation
module Web
  class << self
    def init
      @browser = nil
      @page = nil  # Persistent page for session
      @available = FERRUM_AVAILABLE && chrome_available?
    end
    
    def available?
      @available
    end
    
    def chrome_available?
      %w[chromium chrome google-chrome chromium-browser].any? do |cmd|
        system("which #{cmd} > /dev/null 2>&1")
      end
    end
    
    def browser
      return nil unless @available
      @browser ||= Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1280, 800],
        browser_options: { "no-sandbox": nil }
      )
    end
    
    # Get or create persistent page
    def page
      return nil unless @available
      @page ||= browser.create_page
    end
    
    # Navigate to URL and return structured page info for LLM
    def goto(url)
      return { error: "Ferrum not available" } unless @available
      
      begin
        url = "https://#{url}" unless url.match?(%r{^https?://})
        page.go_to(url)
        sleep 2
        
        extract_page_info
      rescue => e
        { error: e.message, url: url }
      end
    end
    
    # Extract structured page info for LLM reasoning
    def extract_page_info
      title = page.at_css("title")&.text || ""
      url = page.current_url
      
      # Get all clickable links with indices
      links = page.css("a[href]").map.with_index do |el, i|
        text = el.text.strip[0..60]
        href = el.attribute("href")
        next nil if text.empty? || href.nil? || href.start_with?("#", "javascript:")
        { id: i, text: text, href: href }
      end.compact.first(30)
      
      # Get all form inputs
      inputs = page.css("input, textarea, select").map.with_index do |el, i|
        {
          id: i,
          type: el.attribute("type") || el.tag_name,
          name: el.attribute("name"),
          placeholder: el.attribute("placeholder")
        }
      end.first(15)
      
      # Get buttons
      buttons = page.css("button, input[type='submit']").map.with_index do |el, i|
        { id: i, text: el.text.strip[0..30] || el.attribute("value") }
      end.compact.first(10)
      
      # Get main text content (truncated)
      content = page.at_css("article, main, .content, #content, body")&.text || ""
      content = content.gsub(/\s+/, " ").strip[0..4000]
      
      {
        url: url,
        title: title,
        content: content,
        links: links,
        inputs: inputs,
        buttons: buttons
      }
    end
    
    # Take screenshot and return base64 for LLM vision (if supported)
    def screenshot_base64
      return { error: "Ferrum not available" } unless @available
      
      begin
        data = page.screenshot(format: :png, encoding: :base64)
        { base64: data, url: page.current_url }
      rescue => e
        { error: e.message }
      end
    end
    
    # Save screenshot to file
    def screenshot(path: nil)
      return { error: "Ferrum not available" } unless @available
      
      begin
        path ||= "/tmp/screenshot_#{Time.now.to_i}.png"
        page.screenshot(path: path, full: true)
        { path: path, url: page.current_url }
      rescue => e
        { error: e.message }
      end
    end
    
    # Click a link by index (from extract_page_info)
    def click(index)
      return { error: "Ferrum not available" } unless @available
      
      begin
        links = page.css("a[href]").to_a
        if index < links.length
          links[index].click
          sleep 2
          extract_page_info
        else
          { error: "Link index #{index} out of range" }
        end
      rescue => e
        { error: e.message }
      end
    end
    
    # Type into input by index
    def type(index, text)
      return { error: "Ferrum not available" } unless @available
      
      begin
        inputs = page.css("input, textarea").to_a
        if index < inputs.length
          inputs[index].focus.type(text)
          { success: true, typed: text }
        else
          { error: "Input index #{index} out of range" }
        end
      rescue => e
        { error: e.message }
      end
    end
    
    # Submit form (press enter or click submit)
    def submit
      return { error: "Ferrum not available" } unless @available
      
      begin
        btn = page.at_css("input[type='submit'], button[type='submit'], button")
        if btn
          btn.click
        else
          page.keyboard.type(:Enter)
        end
        sleep 2
        extract_page_info
      rescue => e
        { error: e.message }
      end
    end
    
    # Go back
    def back
      return { error: "Ferrum not available" } unless @available
      page.back
      sleep 1
      extract_page_info
    end
    
    # Execute JavaScript
    def evaluate(script)
      return { error: "Ferrum not available" } unless @available
      
      begin
        result = page.evaluate(script)
        { result: result }
      rescue => e
        { error: e.message }
      end
    end
    
    # Convenience: fetch URL and return text only
    def fetch(url)
      result = goto(url)
      return result if result[:error]
      
      { title: result[:title], content: result[:content], url: result[:url] }
    end
    
    # Search DuckDuckGo
    def search(query)
      return { error: "Ferrum not available" } unless @available
      
      begin
        goto("https://lite.duckduckgo.com/lite/")
        type(0, query)
        submit
        
        results = page.css(".result-link, a.result-link").map do |link|
          { title: link.text.strip, url: link.attribute("href") }
        end.first(5)
        
        # Fallback: get all links if .result-link not found
        if results.empty?
          results = page.css("a[href^='http']").map do |link|
            text = link.text.strip
            next nil if text.empty? || text.length < 5
            { title: text[0..80], url: link.attribute("href") }
          end.compact.first(10)
        end
        
        { query: query, results: results }
      rescue => e
        { error: e.message }
      end
    end
    
    # Research: check changelogs/docs before answering
    def research(topic, sources: nil)
      sources ||= [
        "https://docs.ruby-lang.org/en/master/NEWS_md.html",
        "https://ar5iv.org/search?query=#{URI.encode_www_form_component(topic)}",
        "https://man.openbsd.org/#{topic}"
      ]
      
      results = []
      sources.each do |url|
        data = fetch(url)
        next if data[:error]
        results << { source: url, title: data[:title], excerpt: data[:content][0..500] }
      end
      
      results
    end
    
    def quit
      @page&.close
      @page = nil
      @browser&.quit
      @browser = nil
    end
    
    def status
      if @available
        "ferrum:ok chrome:#{chrome_available? ? 'ok' : 'no'} page:#{@page ? 'active' : 'none'}"
      else
        "ferrum:no"
      end
    end
  end
end

# Violation - Represents a single violation
class Violation
  attr_reader :file, :line, :rule, :law, :severity, :details, :message

  def initialize(file:, line:, rule:, law:, severity:, details: "", message: "")
    @file = file
    @line = line
    @rule = rule
    @law = law
    @severity = severity
    @details = details
    @message = message
  end

  def veto?
    @severity == "veto"
  end

  def to_s
    "L#{@line}: #{@rule} [#{@law}] #{@details}".strip
  end

  def to_h
    {
      file: @file,
      line: @line,
      rule: @rule,
      law: @law,
      severity: @severity,
      details: @details
    }
  end
end

# Scanner - Pattern-based violation detection
class Scanner
  def initialize(config)
    @config = config
    @registry = config["registry"] || []
  end

  def scan(path)
    return Result.failure("file not found: #{path}") unless File.exist?(path)

    Logger.operation("scan", path)

    violations = []

    # Pattern-based rules (work on all files)
    content = File.read(path, encoding: "UTF-8")
    lines = content.lines

    @registry.each do |rule|
      next if rule["ast"] # Skip AST rules in pattern scan
      next if skip_for_file_type?(rule, path)

      pattern = Regexp.new(rule["pattern"]) rescue next

      lines.each_with_index do |line, idx|
        if line.match(pattern)
          violations << Violation.new(
            file: path,
            line: idx + 1,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: extract_details(line, pattern)
          )
          
          # Track violation
          ViolationTracker.track(path, violations.last)
        end
      end
    end

    # AST-based rules (Ruby files only) if AST available
    if AST_AVAILABLE && path.end_with?('.rb')
      ast_violations = ASTAnalyzer.analyze(path, @registry)
      ast_violations.each { |v| ViolationTracker.track(path, v) }
      violations.concat(ast_violations)
    end

    Result.success(violations)
  end

  def scan_recursive(dir = ".", patterns: nil, exclude: nil)
    patterns ||= @config.dig("scanning", "patterns") || ["**/*.rb"]
    exclude ||= @config.dig("scanning", "exclude") || []

    files = []
    patterns.each do |pattern|
      Dir.glob(File.join(dir, pattern)).each do |f|
        next unless File.file?(f)
        next if exclude.any? { |ex| File.fnmatch(ex, f) }
        files << f
      end
    end

    Logger.metric("files", files.size, "")
    
    # Auto-clean before scan if enabled
    files.each { |f| CleanIntegration.clean(f) }
    
    results = {}
    files.each do |f|
      scan_result = scan(f)
      violations = scan_result.or_else([])
      results[f] = violations unless violations.empty?
    end

    results
  end

  private

  def skip_for_file_type?(rule, path)
    if rule["yaml_only"] && !path.match?(/.ya?ml$/)
      true
    elsif rule["ruby_only"] && !path.end_with?('.rb')
      true
    else
      false
    end
  end

  def extract_details(line, pattern)
    match = line.match(pattern)
    match[0].strip if match
  end
end

# ASTAnalyzer - AST-based violation detection
module ASTAnalyzer
  class << self
    def analyze(path, rules)
      return [] unless AST_AVAILABLE

      buffer = Parser::Source::Buffer.new(path)
      buffer.source = File.read(path)
      
      ast = Parser::CurrentRuby.new.parse(buffer)
      return [] unless ast

      violations = []

      rules.each do |rule|
        next unless rule["ast"]
        
        case rule["name"]
        when "long_method"
          violations.concat(check_long_methods(ast, rule, path))
        when "high_complexity"
          violations.concat(check_complexity(ast, rule, path))
        when "too_many_params"
          violations.concat(check_params(ast, rule, path))
        when "duplicate_code"
          violations.concat(check_duplication(ast, rule, path))
        when "god_class"
          violations.concat(check_class_size(ast, rule, path))
        when "feature_envy"
          violations.concat(check_feature_envy(ast, rule, path))
        end
      end

      violations
    rescue Parser::SyntaxError => e
      Logger.error("syntax error in #{path}: #{e.message}")
      []
    end

    private

    def check_long_methods(ast, rule, path)
      violations = []
      threshold = rule["threshold"] || 20

      ast.each_node(:def, :defs) do |node|
        location = node.loc
        method_name = node.children[0]
        
        start_line = location.line
        end_line = location.last_line
        length = end_line - start_line + 1

        if length > threshold
          violations << Violation.new(
            file: path,
            line: start_line,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: "method '#{method_name}' is #{length} lines (threshold: #{threshold})"
          )
        end
      end

      violations
    end

    def check_complexity(ast, rule, path)
      violations = []
      threshold = rule["threshold"] || 10

      ast.each_node(:def, :defs) do |node|
        complexity = calculate_complexity(node)
        method_name = node.children[0]
        
        if complexity > threshold
          violations << Violation.new(
            file: path,
            line: node.loc.line,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: "method '#{method_name}' complexity: #{complexity} (threshold: #{threshold})"
          )
        end
      end

      violations
    end

    def check_params(ast, rule, path)
      violations = []
      threshold = rule["threshold"] || 3

      ast.each_node(:def, :defs) do |node|
        args = node.children[1]
        param_count = count_params(args)
        method_name = node.children[0]

        if param_count > threshold
          violations << Violation.new(
            file: path,
            line: node.loc.line,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: "method '#{method_name}' has #{param_count} params (threshold: #{threshold})"
          )
        end
      end

      violations
    end

    def check_duplication(ast, rule, path)
      # Simplified duplication detection
      violations = []
      threshold = rule["threshold"] || 6
      
      # Find repeated method bodies
      method_bodies = {}
      
      ast.each_node(:def, :defs) do |node|
        body_hash = node.children[2].to_s
        method_bodies[body_hash] ||= []
        method_bodies[body_hash] << [node.loc.line, node.children[0]]
      end
      
      method_bodies.each do |hash, methods|
        if methods.size >= 2
          methods.each do |line, name|
            violations << Violation.new(
              file: path,
              line: line,
              rule: rule["name"],
              law: rule["law"],
              severity: rule["severity"],
              details: "method '#{name}' duplicates #{methods.size - 1} other method(s)"
            )
          end
        end
      end
      
      violations
    end

    def check_class_size(ast, rule, path)
      violations = []
      threshold = rule["threshold"] || 300

      ast.each_node(:class) do |node|
        class_name = node.children[0]
        location = node.loc
        
        start_line = location.line
        end_line = location.last_line
        length = end_line - start_line + 1

        if length > threshold
          violations << Violation.new(
            file: path,
            line: start_line,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: "class '#{class_name}' is #{length} lines (threshold: #{threshold})"
          )
        end
      end

      violations
    end

    def check_feature_envy(ast, rule, path)
      # Simplified feature envy detection
      violations = []
      
      ast.each_node(:def, :defs) do |node|
        method_name = node.children[0]
        external_calls = count_external_calls(node)
        internal_calls = count_internal_calls(node)
        
        if external_calls > internal_calls * 2 && external_calls > 3
          violations << Violation.new(
            file: path,
            line: node.loc.line,
            rule: rule["name"],
            law: rule["law"],
            severity: rule["severity"],
            details: "method '#{method_name}' has #{external_calls} external vs #{internal_calls} internal calls"
          )
        end
      end
      
      violations
    end

    def calculate_complexity(node)
      complexity = 1
      
      node.each_node do |n|
        complexity += 1 if [:if, :while, :until, :for, :rescue, :when, :and, :or].include?(n.type)
      end
      
      complexity
    end

    def count_params(args)
      return 0 unless args
      args.children.size
    end

    def count_external_calls(node)
      count = 0
      node.each_node(:send) do |n|
        receiver = n.children[0]
        count += 1 if receiver && receiver.type != :self
      end
      count
    end

    def count_internal_calls(node)
      count = 0
      node.each_node(:send) do |n|
        receiver = n.children[0]
        count += 1 if !receiver || receiver.type == :self
      end
      count
    end
  end
end

# RuboCopFixer - Safe auto-correct
module RuboCopFixer
  class << self
    def fix(path, cops: nil)
      return false unless AST_AVAILABLE

      cops_str = cops ? "--only #{cops.join(',')}" : ""
      Logger.operation("fix", "rubocop #{path}")
      
      success = system("rubocop --autocorrect-all #{cops_str} #{path} >/dev/null 2>&1")
      
      if success
        Logger.success("auto-fixed: #{path}")
      else
        Logger.error("auto-fix failed: #{path}")
      end
      
      success
    end
  end
end

# CLI - Command-line interface
class CLI
  def initialize
    @config = load_config
    init_modules
    
    @scanner = Scanner.new(@config)
    @running = true
    @commands = build_commands
  end

  def run
    parse_options
    display_banner
    ensure_api_key
    
    # Check for --veto-only flag
    if @veto_only
      results = @scanner.scan_recursive
      veto_violations = results.values.flatten.select(&:veto?)
      
      if veto_violations.any?
        # H9: Help recognize/recover from errors - specific count
        puts "✗ #{veto_violations.size} veto violations"
        exit 1
      else
        puts "✓ no veto violations"
        exit 0
      end
    end

    # Interactive mode
    repl
  end

  private

  def load_config
    config_path = File.expand_path("master.yml", __dir__)
    YAML.load_file(config_path)
  end

  def init_modules
    Logger.init(@config)
    StateManager.init(@config)
    ViolationTracker.init(@config)
    ContextInjector.init(@config)
    PersonaJournal.init(@config)
    RefactoringJournal.init(@config)
    LearningEngine.init(@config)
    WorkflowStateMachine.init(@config)
    CommitHooks.init(@config)
    DependencyAnalyzer.init(@config)
    PriorityQueue.init(@config)
    CleanIntegration.init(@config)
    Dashboard.init(@config)
    InlineSuggestions.init(@config)
    OpenRouterChat.init(@config)
    Voice.init(@config)
    Web.init
    
    # Auto-set Ares persona for chat
    if Voice.persona_prompt
      OpenRouterChat.set_persona_prompt(Voice.persona_prompt)
    end
    
    # Ensure directories exist
    StateManager.pre_work_snapshot if @config.dig("integration", "pre_work_snapshot")
    StateManager.ensure_directories
  end

  def parse_options
    @veto_only = false
    
    OptionParser.new do |opts|
      opts.banner = "Usage: convergence [options]"
      
      opts.on("-q", "--quiet", "Minimal output") { Logger.set_quiet(true) }
      opts.on("-v", "--verbose", "Detailed output") { Logger.set_verbose(true) }
      opts.on("-d", "--debug", "Debug output") { Logger.set_debug(true) }
      opts.on("--veto-only", "Check veto violations only (exit 0/1)") { @veto_only = true }
      opts.on("-h", "--help", "Show help") { puts opts; exit }
    end.parse!
  end

  def display_banner
    puts "Master.yml #{@config['version']}"
    puts "Code governance / Chat-first CLI"
    puts
  end

  def ensure_api_key
    if OpenRouterChat.available?
      puts C.g("* Sonnet 4.5 ready")
      # Auto-load core files into context
      %w[master.yml cli.rb].each do |f|
        path = File.expand_path(f, __dir__)
        OpenRouterChat.add_context_file(path) if File.exist?(path)
      end
      puts C.d("Context: master.yml, cli.rb loaded")
      puts C.d("Type to chat, /help for commands")
    else
      puts C.y("- No API key")
      print "Paste OPENROUTER_API_KEY (Enter to skip): "
      key = gets&.strip
      
      if key && !key.empty?
        ENV["OPENROUTER_API_KEY"] = key
        OpenRouterChat.init(@config)
        
        if OpenRouterChat.available?
          puts C.g("* Key accepted")
          
          print "Save to ~/.zshrc? [y/N]: "
          save = gets&.strip&.downcase
          if save == "y"
            File.open(File.expand_path("~/.zshrc"), "a") do |f|
              f.puts "
export OPENROUTER_API_KEY="#{key}""
            end
            puts C.d("Saved")
          end
        else
          puts C.y("Key set, check failed")
        end
      else
        puts C.d("Offline mode")
      end
    end
    puts
  end

  def build_commands
    {
      "scan" => method(:cmd_scan),
      "recursive" => method(:cmd_recursive),
      "fix" => method(:cmd_fix),
      "converge" => method(:cmd_converge),
      "dogfood" => method(:cmd_dogfood),
      "status" => method(:cmd_status),
      "chat" => method(:cmd_chat),
      "clear" => method(:cmd_clear_chat),
      "voice" => method(:cmd_voice),
      "persona" => method(:cmd_persona),
      "listen" => method(:cmd_listen),
      "browse" => method(:cmd_browse),
      "search" => method(:cmd_search),
      "model" => method(:cmd_model),
      "reload" => method(:cmd_reload),
      "update" => method(:cmd_update),
      "save" => method(:cmd_save),
      "restore" => method(:cmd_restore),
      "add" => method(:cmd_add),
      "load" => method(:cmd_load),
      "undo" => method(:cmd_undo),
      "cost" => method(:cmd_cost),
      "deps" => method(:cmd_deps),
      "install-hook" => method(:cmd_install_hook),
      "uninstall-hook" => method(:cmd_uninstall_hook),
      "journal" => method(:cmd_journal),
      "patterns" => method(:cmd_patterns),
      "export" => method(:cmd_export),
      "import" => method(:cmd_import),
      "sync" => method(:cmd_sync),
      "help" => method(:cmd_help),
      "exit" => method(:cmd_exit),
      "quit" => method(:cmd_exit),
      # P0 Copilot-style commands
      "view" => method(:cmd_view),
      "edit" => method(:cmd_edit),
      "grep" => method(:cmd_grep),
      "create" => method(:cmd_create),
      "diff" => method(:cmd_diff),
      "todo" => method(:cmd_todo),
      "checkpoint" => method(:cmd_checkpoint),
      "checkpoints" => method(:cmd_restore_checkpoint)
    }
  end

  def setup_readline
    # Load history
    if File.exist?(HISTORY_FILE)
      File.readlines(HISTORY_FILE).each { |line| Readline::HISTORY << line.chomp }
    end
    
    # Tab completion for commands and files
    Readline.completion_proc = proc do |input|
      if input.start_with?("/")
        # Complete commands
        cmd = input[1..]
        matches = @commands.keys.select { |c| c.start_with?(cmd) }
        matches += COMMAND_ALIASES.keys.select { |c| c.start_with?(cmd) }
        matches.map { |c| "/#{c}" }
      else
        # Complete file paths
        Dir.glob("#{input}*").first(20)
      end
    end
  end
  
  def save_history
    File.open(HISTORY_FILE, "w") do |f|
      Readline::HISTORY.to_a.last(1000).each { |line| f.puts line }
    end
  rescue => e
    # Silent fail on history save
  end
  
  def build_prompt
    parts = []
    turns = OpenRouterChat.conversation_length
    tokens = OpenRouterChat.token_estimate
    model_short = OpenRouterChat.model_name.split("/").last.split("-").first(2).join("-") rescue "?"
    
    parts << C.d("[#{turns}]") if turns > 0
    parts << C.d("[#{model_short}]")
    parts << C.y("[#{(tokens/1000.0).round(1)}k]") if tokens > 1000
    parts << "> "
    parts.join(" ")
  end

  def repl
    setup_readline
    
    while @running
      prompt = build_prompt
      
      begin
        input = Readline.readline(prompt, true)
      rescue Interrupt
        puts ""
        next
      end
      
      break unless input
      
      # Remove empty/duplicate from history
      Readline::HISTORY.pop if input.strip.empty? || 
        (Readline::HISTORY.length > 1 && Readline::HISTORY[-2] == input)
      
      input = input.strip.force_encoding("UTF-8")
      next if input.empty?
      
      # Multi-line input with backslash
      while input.end_with?("\\")
        input = input[0..-2] + "\n"
        continuation = Readline.readline("... ", false)
        break unless continuation
        input += continuation
      end
      
      # H3: User control - Ctrl+C handled, /clear to reset
      # H7: Flexibility - / prefix for commands, plain text for chat
      if input.start_with?("/")
        parts = input[1..].split(/\s+/)
        command = parts[0].downcase
        args = parts[1..]
        
        # Resolve aliases
        command = COMMAND_ALIASES[command] || command
        
        if @commands.key?(command)
          @commands[command].call(*args)
        else
          # H6: Recognition - suggest similar commands
          similar = @commands.keys.select { |c| c.start_with?(command[0]) }
          if similar.any?
            puts "unknown: /#{command}. did you mean: #{similar.map { |c| "/#{c}" }.join(', ')}?"
          else
            puts "unknown: /#{command} (/help for list)"
          end
        end
      else
        # Check if first word is a known command (allow commands without /)
        parts = input.split(/\s+/)
        first_word = parts[0]&.downcase
        if first_word && @commands.key?(first_word)
          @commands[first_word].call(*parts[1..])
        else
          chat_with_llm(input)
        end
      end
    end
  rescue Interrupt
    # H3: User control - clean exit on Ctrl+C
    puts "
[interrupted]"
  end
  
  def chat_with_llm(message)
    unless OpenRouterChat.available?
      puts "Chat unavailable: set OPENROUTER_API_KEY and restart"
      return
    end
    
    # npm-style spinner
    spinner = Thread.new do
      frames = ['|', '/', '-', '\\']
      i = 0
      loop do
        print "
#{frames[i % 4]} "
        $stdout.flush
        sleep 0.1
        i += 1
      end
    end
    
    result = OpenRouterChat.chat(message)
    spinner.kill
    print "
  
"
    
    if result.success?
      response = result.value
      
      # Speak response if voice enabled
      Voice.speak(response)
      
      # Check for tool calls in response
      if response.include?("```shell") || response.include?("```zsh") || response.include?("```ruby")
        handle_tool_response(response)
      elsif response.match?(/\/(?:view|edit|grep|create|diff|todo)\s/)
        handle_command_response(response)
      else
        puts response
      end
    else
      puts "Error: #{result.error}"
      puts "Hint: check API key or try again"
    end
  end
  
  # Auto-execute /commands from LLM response
  def handle_command_response(response)
    puts response
    
    # Extract and execute /commands line by line
    response.each_line do |line|
      if line.strip.match?(/^\/(?:view|edit|grep|create|diff|todo)\s/)
        cmd_line = line.strip
        puts C.d("[auto] #{cmd_line}")
        
        parts = cmd_line[1..].split(/\s+/, 2)
        command = parts[0].downcase
        args = parse_command_args(parts[1] || "")
        
        if @commands.key?(command)
          begin
            @commands[command].call(*args)
          rescue => e
            puts C.r("Error: #{e.message}")
          end
        end
      end
    end
  end
  
  # Parse command arguments respecting quotes
  def parse_command_args(arg_string)
    args = []
    current = ""
    in_quotes = false
    quote_char = nil
    
    arg_string.to_s.each_char do |c|
      if (c == '"' || c == "'") && !in_quotes
        in_quotes = true
        quote_char = c
      elsif c == quote_char && in_quotes
        in_quotes = false
        quote_char = nil
      elsif c == ' ' && !in_quotes
        args << current unless current.empty?
        current = ""
      else
        current += c
      end
    end
    args << current unless current.empty?
    args
  end
  
  def handle_tool_response(response)
    puts response
    
    files_modified = []
    
    # Auto-execute shell/zsh blocks
    response.scan(/```(?:shell|zsh|bash)
(.*?)```/m) do |match|
      command = match[0].strip
      next if command.empty?
      
      puts "
$ #{command}"
      output = `#{command} 2>&1`
      exit_code = $?.exitstatus
      puts output unless output.empty?
      
      # Track file modifications for git commit
      if command.include?(">") || command.include?("mv ")
        files_modified << command.split.last
      end
      
      # Error context: send failure back to LLM for fix
      if exit_code != 0
        OpenRouterChat.chat("Command failed (exit #{exit_code}):
```
#{output}
```
Fix it.")
      elsif output.strip.present?
        OpenRouterChat.chat("Executed. Output:
```
#{output}
```")
      end
    end
    
    # Auto-execute ruby blocks
    response.scan(/```ruby
(.*?)```/m) do |match|
      code = match[0].strip
      next if code.empty?
      next if code.include?("def ") # Skip method definitions (examples)
      
      puts "
$ ruby: #{code.lines.first.strip}..."
      begin
        result = eval(code)
        puts result.inspect if result
      rescue => e
        puts "error: #{e.message}"
        OpenRouterChat.chat("Ruby error: #{e.message}
Fix it.")
      end
    end
    
    # Git auto-commit after successful file modifications
    if files_modified.any?
      changed = `git diff --name-only 2>/dev/null`.strip
      if !changed.empty?
        msg = "Auto: #{files_modified.first(3).join(', ')}"
        system("git add -A && git commit -m '#{msg}' > /dev/null 2>&1")
        puts C.d("[committed: #{msg}]")
      end
    end
  end

  def cmd_scan(*args)
    file = args[0]
    unless file
      puts "Usage: /scan <file>"
      return
    end
    
    result = @scanner.scan(file)
    
    if result.failure?
      Logger.error(result.error)
      return
    end
    
    violations = result.value
    display_violations(file, violations)
  end

  def cmd_recursive(*args)
    results = @scanner.scan_recursive
    
    total_violations = results.values.flatten.size
    
    puts "#{results.size} files, #{total_violations} violations"
    
    results.each do |file, violations|
      display_violations(file, violations)
    end
    
    # Update context
    progress = calculate_progress(results)
    StateManager.update_context("recursive scan", [], progress)
    
    # Show dashboard
    Dashboard.display(results)
  end

  def cmd_fix(*args)
    file = args[0]
    unless file
      puts "Usage: /fix <file>"
      return
    end
    
    unless File.exist?(file)
      Logger.error("file not found: #{file}")
      return
    end
    
    cops = @config.dig("convergence", "auto_fix", "rubocop_cops")
    RuboCopFixer.fix(file, cops: cops)
    
    # Rescan
    result = @scanner.scan(file)
    violations = result.or_else([])
    display_violations(file, violations)
  end

  def cmd_converge(*args)
    file = args[0]
    unless file
      puts "Usage: /converge <file>"
      return
    end
    
    max_iter = @config.dig("convergence", "max_iterations") || 15
    
    puts "converge: #{file} (max #{max_iter})"
    
    iter = 0
    same_count = 0
    prev_violations = nil
    
    loop do
      iter += 1
      puts "
iteration #{iter}/#{max_iter}"
      
      # Auto-fix
      if @config.dig("convergence", "auto_fix", "enabled")
        RuboCopFixer.fix(file)
        CleanIntegration.clean(file)
      end
      
      # Scan
      violations = @scanner.scan(file).or_else([])
      display_violations(file, violations)
      
      # Check exit conditions
      if violations.empty?
        puts "✓ converged: 0 violations"
        break
      end
      
      if iter >= max_iter
        puts "⚠ max iterations reached"
        break
      end
      
      # Check if stuck
      if prev_violations && violations.map(&:to_s) == prev_violations.map(&:to_s)
        same_count += 1
        if same_count >= 3
          puts "⚠ stuck: same violations 3x"
          break
        end
      else
        same_count = 0
      end
      
      prev_violations = violations
      
      # Prompt for edit
      print "edit #{file}, press enter to continue (q to quit): "
      response = gets.strip
      break if response.downcase == 'q'
    end
  end

  def cmd_dogfood(*args)
    files = ["master.yml", "cli.rb"]
    
    puts "dogfood: #{files.join(' ')}"
    
    files.each do |file|
      next unless File.exist?(file)
      
      violations = @scanner.scan(file).or_else([])
      display_violations(file, violations)
    end
  end

  def cmd_status(*args)
    results = @scanner.scan_recursive
    Dashboard.display(results)
  end

  def cmd_install_hook(*args)
    CommitHooks.install
  end

  def cmd_uninstall_hook(*args)
    CommitHooks.uninstall
  end

  def cmd_journal(*args)
    count = args[0]&.to_i || 10
    
    entries = RefactoringJournal.read_recent(count)
    
    if entries.empty?
      puts "No journal entries"
    else
      puts "Last #{entries.size} refactorings:

"
      entries.each { |e| puts e }
    end
  end

  def cmd_patterns(*args)
    pattern_dir = @config.dig("tracking", "patterns", "library_dir") || ".convergence_patterns"
    
    unless Dir.exist?(pattern_dir)
      puts "No patterns learned yet"
      return
    end
    
    pattern_files = Dir.glob("#{pattern_dir}/*.yml")
    
    if pattern_files.empty?
      puts "No patterns learned yet"
      return
    end
    
    puts "Learned patterns:
"
    
    pattern_files.each do |file|
      patterns = YAML.load_file(file) rescue []
      next if patterns.empty?
      
      violation_type = File.basename(file, '.yml')
      rule = LearningEngine.generate_rule(violation_type, patterns)
      
      if rule
        puts "#{violation_type}:"
        puts "  samples: #{rule[:sample_count]}"
        puts "  confidence: #{(rule[:confidence] * 100).round}%"
        puts "  before: #{rule[:before]}"
        puts "  after: #{rule[:after]}"
        puts
      end
    end
  end

  def cmd_help(*args)
    puts <<~HELP
      Just type to chat with the AI.
      
      Commands (prefix with /):
        /load [file]     Load files into context (default: master.yml + cli.rb)
        /add <file>      Add single file to context
        /scan <file>     Scan single file
        /recursive       Scan all files
        /fix <file>      Auto-fix with RuboCop
        /converge <file> Iterative fix loop
        /dogfood         Scan master.yml and cli.rb
        /status          Show dashboard
        /model [name]    Switch model (e.g. deepseek)
        /add <file>      Add file to context
        /save [file]     Save session
        /restore [file]  Restore session
        /undo            Revert last file change
        /cost            Show token/cost usage
        /deps [install]  Show/install dependencies
        /reload          Reload master.yml
        /update          Git pull + restart
        
        Voice:
        /voice           Toggle voice on/off
        /voice random    Random persona + effect each message
        /voice fx <name> Set audio effect
        /voice status    Show voice settings
        /persona <name>  Switch persona (or 'random')
        /listen          Voice input mode
        
        Effects: clean, warm, vhs, vhs_heavy, vinyl, vinyl_crackle,
                 radio, shortwave, transmission, phone, cassette,
                 lo-fi, underwater, ghostly, broken
        
        /browse <url>    Fetch web page via Ferrum
        /search <query>  Search DuckDuckGo
        /clear           Clear chat history
        /help            Show this
        /quit            Exit
    HELP
  end
  
  def cmd_chat(*args)
    message = args.join(" ")
    chat_with_llm(message) unless message.empty?
  end
  
  def cmd_clear_chat(*args)
    OpenRouterChat.clear_conversation
    puts "Chat history cleared"
  end
  
  def cmd_model(*args)
    if args.empty?
      puts "Current: #{OpenRouterChat.current_model}"
      puts "Examples: anthropic/claude-sonnet-4, deepseek/deepseek-chat, openai/gpt-4o"
    else
      model = args[0]
      model = "anthropic/claude-sonnet-4" if model == "sonnet"
      model = "deepseek/deepseek-chat" if model == "deepseek"
      model = "openai/gpt-4o" if model == "gpt4"
      OpenRouterChat.set_model(model)
      puts "Model: #{model}"
    end
  end
  
  def cmd_reload(*args)
    @config = load_config
    OpenRouterChat.init(@config)
    puts "Config reloaded"
  end
  
  def cmd_update(*args)
    puts "Pulling latest..."
    Dir.chdir(File.dirname(__FILE__)) do
      result = `git reset --hard origin/main 2>&1`
      puts result unless result.empty?
      result = `git pull 2>&1`
      puts result
      
      if $?.success?
        puts "Restarting..."
        Voice.stop_server rescue nil
        # Save readline history before restart
        File.open(HISTORY_FILE, "w") do |f|
          Readline::HISTORY.each { |line| f.puts(line) }
        end rescue nil
        # Exec replaces current process with new one
        exec("ruby", __FILE__, *ARGV)
      else
        puts "Pull failed, not restarting"
      end
    end
  end
  
  def cmd_save(*args)
    path = args[0] || ".convergence_session.yml"
    OpenRouterChat.save_session(path)
    puts "Session saved: #{path}"
  end
  
  def cmd_restore(*args)
    path = args[0] || ".convergence_session.yml"
    if OpenRouterChat.restore_session(path)
      puts "Session restored: #{path}"
    else
      puts "Session not found: #{path}"
    end
  end
  
  def cmd_add(*args)
    if args.empty?
      puts "Usage: /add <file>"
      return
    end
    
    path = args[0]
    if OpenRouterChat.add_context_file(path)
      puts "Added: #{path}"
    else
      puts "Not found: #{path}"
    end
  end
  
  # Alias for /add - load files into context
  def cmd_load(*args)
    if args.empty?
      # Default: load master.yml and cli.rb
      %w[master.yml cli.rb].each do |f|
        path = File.expand_path(f, __dir__)
        if OpenRouterChat.add_context_file(path)
          puts "Loaded: #{f}"
        end
      end
    else
      cmd_add(*args)
    end
  end
  
  def cmd_undo(*args)
    result = `git checkout HEAD~1 -- . 2>&1`
    if $?.success?
      puts "Reverted last change"
    else
      puts "Undo failed: #{result}"
    end
  end
  
  def cmd_cost(*args)
    puts "Tokens: #{OpenRouterChat.total_tokens}"
    puts "Cost: $#{'%.4f' % OpenRouterChat.total_cost}"
    puts "Last: $#{'%.6f' % OpenRouterChat.last_cost}"
  end
  
  def cmd_deps(*args)
    puts C.b("Dependency Status:")
    puts ""
    
    # Gems
    puts "Gems:"
    DependencyManager::GEMS.each do |gem, info|
      available = begin
        require gem
        C.g("ok")
      rescue LoadError
        C.r("missing")
      end
      puts "  #{gem}: #{available} (#{info[:desc]})"
    end
    
    puts ""
    puts "Packages:"
    DependencyManager::PACKAGES.each do |name, pkg|
      available = system("which #{name} > /dev/null 2>&1") ? C.g("ok") : C.r("missing")
      puts "  #{name}: #{available}"
    end
    
    puts ""
    puts "Modules:"
    puts "  Ferrum: #{FERRUM_AVAILABLE ? C.g('ok') : C.r('no')}"
    puts "  Falcon: #{FALCON_AVAILABLE ? C.g('ok') : C.r('no')}"
    puts "  Voice: #{Voice.status}"
    puts "  Web: #{Web.status}"
    
    if args.include?("install")
      puts ""
      puts C.b("Installing missing dependencies...")
      DependencyManager.setup_all
    else
      puts ""
      puts C.d("Run /deps install to install missing")
    end
  end
  
  def cmd_voice(*args)
    if args.empty?
      if Voice.available?
        enabled = Voice.toggle
        puts "Voice #{enabled ? 'on' : 'off'} (#{Voice.model_name}, rate #{Voice.speech_rate})"
        puts "Persona: #{Voice.random_mode? ? 'random' : Voice.current_persona}" if enabled
        puts "Effect: #{Voice.current_effect}" if enabled
      else
        puts "Voice unavailable: install piper, whisper, sox"
        puts "  /voice install wheatley1  - Quirky Portal 2 voice"
        puts "  /voice install glados     - Deadpan sarcastic"
        puts "  /voice install kronk      - Lovable awkward"
      end
    elsif args[0] == "install"
      voice = args[1] || "wheatley1"
      Voice.install_voice(voice)
    elsif args[0] == "rate"
      rate = args[1]&.to_f || 1.0
      puts "Set PIPER_RATE=#{rate} in env for persistent change"
    elsif args[0] == "random"
      pick = Voice.set_persona("random")
      Voice.set_effect("random")
      Voice.enable
      OpenRouterChat.set_persona_prompt(Voice.persona_prompt) if Voice.persona_prompt
      puts "Random mode: persona + effect shuffle each message"
      puts "First up: #{pick} with #{Voice.current_effect} effect"
    elsif args[0] == "fx" || args[0] == "effect"
      if args[1].nil?
        puts "Current effect: #{Voice.current_effect}"
        puts "Available: #{Voice.available_effects.join(', ')}"
      elsif args[1] == "random"
        Voice.set_effect("random")
        puts "Effect: random (shuffles each message)"
      elsif Voice.set_effect(args[1])
        puts "Effect: #{args[1]}"
      else
        puts "Unknown effect: #{args[1]}"
        puts "Available: #{Voice.available_effects.join(', ')}"
      end
    elsif args[0] == "status"
      puts Voice.status
    else
      puts "Unknown: /voice #{args[0]}"
      puts "  /voice           - Toggle on/off"
      puts "  /voice random    - Random persona + effect each message"
      puts "  /voice fx <name> - Set audio effect (vhs, vinyl, radio...)"
      puts "  /voice status    - Show current settings"
    end
  end

  def cmd_persona(*args)
    if args.empty?
      puts "Current: #{Voice.random_mode? ? 'random' : Voice.current_persona}"
      puts "Available: #{Voice.available_personas.join(', ')}, random"
    elsif args[0] == "random"
      pick = Voice.set_persona("random")
      OpenRouterChat.set_persona_prompt(Voice.persona_prompt) if Voice.persona_prompt
      Voice.enable
      puts "Persona: random mode (first: #{pick})"
    else
      name = args[0].downcase
      if Voice.set_persona(name)
        # Also update the system prompt for chat
        if Voice.persona_prompt
          OpenRouterChat.set_persona_prompt(Voice.persona_prompt)
        end
        Voice.enable
        puts "Persona: #{name} (voice enabled)"
      else
        puts "Unknown persona: #{name}"
        puts "Available: #{Voice.available_personas.join(', ')}, random"
      end
    end
  end
  
  # ============================================
  # P0 COPILOT-STYLE COMMANDS (pure zsh patterns)
  # ============================================
  
  # /view <file> [start] [end] - View file with line numbers
  def cmd_view(*args)
    return puts "Usage: /view <file> [start_line] [end_line]" if args.empty?
    
    file = File.expand_path(args[0])
    unless File.exist?(file)
      puts "File not found: #{file}"
      return
    end
    
    lines = File.readlines(file, encoding: "UTF-8")
    start_line = (args[1]&.to_i || 1) - 1
    end_line = (args[2]&.to_i || lines.length) - 1
    
    start_line = [0, start_line].max
    end_line = [lines.length - 1, end_line].min
    
    width = (end_line + 1).to_s.length
    
    (start_line..end_line).each do |i|
      puts "#{(i + 1).to_s.rjust(width)}. #{lines[i]}"
    end
    
    puts C.d("#{file} (#{lines.length} lines)")
  end
  
  # /edit <file> <line> <old> <new> - Replace text at line
  def cmd_edit(*args)
    if args.length < 4
      puts "Usage: /edit <file> <line_num> <old_text> <new_text>"
      puts "  or:  /edit <file> to open in \$EDITOR"
      
      if args.length == 1 && File.exist?(args[0])
        editor = ENV["EDITOR"] || "vi"
        system("#{editor} #{args[0].shellescape}")
      end
      return
    end
    
    file = File.expand_path(args[0])
    line_num = args[1].to_i
    old_text = args[2]
    new_text = args[3]
    
    unless File.exist?(file)
      puts "File not found: #{file}"
      return
    end
    
    lines = File.readlines(file, encoding: "UTF-8")
    
    if line_num < 1 || line_num > lines.length
      puts "Line #{line_num} out of range (1-#{lines.length})"
      return
    end
    
    line = lines[line_num - 1]
    unless line.include?(old_text)
      puts "Text not found on line #{line_num}: #{old_text}"
      return
    end
    
    lines[line_num - 1] = line.sub(old_text, new_text)
    File.write(file, lines.join, encoding: "UTF-8")
    
    puts C.g("Edited line #{line_num}:")
    puts "  - #{line.strip}"
    puts "  + #{lines[line_num - 1].strip}"
  end
  
  # /grep <pattern> [path] - Search files for pattern (pure zsh)
  def cmd_grep(*args)
    return puts "Usage: /grep <pattern> [path]" if args.empty?
    
    pattern = args[0]
    path = args[1] || "."
    
    # Use zsh globbing: **/* for recursive
    # Pure zsh: no grep command, use Ruby's native search
    results = []
    
    Dir.glob(File.join(path, "**/*")).each do |file|
      next unless File.file?(file)
      next if file.include?(".git/")
      next if File.binary?(file) rescue true
      
      begin
        File.readlines(file, encoding: "UTF-8").each_with_index do |line, i|
          if line.include?(pattern) || line.match?(Regexp.new(pattern, Regexp::IGNORECASE))
            results << { file: file, line: i + 1, content: line.strip }
          end
        end
      rescue
        # Skip unreadable files
      end
    end
    
    if results.empty?
      puts "No matches for: #{pattern}"
    else
      results.first(50).each do |r|
        puts "#{C.d(r[:file])}:#{C.g(r[:line].to_s)} #{r[:content][0..100]}"
      end
      puts C.d("#{results.length} matches#{results.length > 50 ? ' (showing first 50)' : ''}")
    end
  end
  
  # /create <file> - Create new file
  def cmd_create(*args)
    return puts "Usage: /create <file>" if args.empty?
    
    file = File.expand_path(args[0])
    
    if File.exist?(file)
      puts "File already exists: #{file}"
      return
    end
    
    # Create parent directories if needed
    dir = File.dirname(file)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    
    # If content provided via heredoc style, use it
    if args.length > 1
      content = args[1..].join(" ")
      File.write(file, content + "\n", encoding: "UTF-8")
      puts C.g("Created: #{file} (#{content.length} bytes)")
    else
      # Open in editor for content
      File.write(file, "", encoding: "UTF-8")
      editor = ENV["EDITOR"] || "vi"
      system("#{editor} #{file.shellescape}")
      puts C.g("Created: #{file}")
    end
  end
  
  # /diff [file] - Show uncommitted changes
  def cmd_diff(*args)
    if args.empty?
      output = `git --no-pager diff --stat 2>/dev/null`
      if output.strip.empty?
        puts "No uncommitted changes"
      else
        puts output
      end
    else
      output = `git --no-pager diff #{args[0].shellescape} 2>/dev/null`
      puts output.empty? ? "No changes in #{args[0]}" : output
    end
  end
  
  # /todo - Simple task tracking
  @todos = []
  def cmd_todo(*args)
    @todos ||= []
    
    if args.empty?
      if @todos.empty?
        puts "No tasks. Add with: /todo add <task>"
      else
        @todos.each_with_index do |task, i|
          status = task[:done] ? C.g("[x]") : "[ ]"
          puts "#{i + 1}. #{status} #{task[:text]}"
        end
      end
    elsif args[0] == "add"
      text = args[1..].join(" ")
      @todos << { text: text, done: false }
      puts C.g("Added: #{text}")
    elsif args[0] == "done"
      idx = args[1].to_i - 1
      if idx >= 0 && idx < @todos.length
        @todos[idx][:done] = true
        puts C.g("Done: #{@todos[idx][:text]}")
      end
    elsif args[0] == "clear"
      @todos = []
      puts "Tasks cleared"
    end
  end
  
  # /checkpoint [name] - Save session state
  def cmd_checkpoint(*args)
    name = args[0] || Time.now.strftime("%Y%m%d_%H%M%S")
    checkpoint_dir = File.expand_path("~/.cli_checkpoints")
    FileUtils.mkdir_p(checkpoint_dir)
    
    checkpoint_file = File.join(checkpoint_dir, "#{name}.yml")
    
    state = {
      conversation: OpenRouterChat.export_conversation,
      context_files: @context_files_list || [],
      todos: @todos || [],
      persona: Voice.current_persona,
      timestamp: Time.now.iso8601
    }
    
    File.write(checkpoint_file, state.to_yaml)
    puts C.g("Checkpoint saved: #{name}")
    puts C.d("  #{checkpoint_file}")
  end
  
  # /restore [name] - Restore session state
  def cmd_restore_checkpoint(*args)
    checkpoint_dir = File.expand_path("~/.cli_checkpoints")
    
    if args.empty?
      # List available checkpoints
      if Dir.exist?(checkpoint_dir)
        files = Dir.glob(File.join(checkpoint_dir, "*.yml")).sort.reverse
        if files.empty?
          puts "No checkpoints found"
        else
          puts "Checkpoints:"
          files.first(10).each do |f|
            name = File.basename(f, ".yml")
            mtime = File.mtime(f).strftime("%Y-%m-%d %H:%M")
            puts "  #{name} (#{mtime})"
          end
        end
      else
        puts "No checkpoints found"
      end
      return
    end
    
    name = args[0]
    checkpoint_file = File.join(checkpoint_dir, "#{name}.yml")
    
    unless File.exist?(checkpoint_file)
      puts "Checkpoint not found: #{name}"
      return
    end
    
    state = YAML.load_file(checkpoint_file)
    
    OpenRouterChat.import_conversation(state[:conversation])
    @todos = state[:todos] || []
    Voice.set_persona(state[:persona]) if state[:persona]
    
    # Reload context files
    (state[:context_files] || []).each do |path|
      OpenRouterChat.add_context_file(path) if File.exist?(path)
    end
    
    puts C.g("Restored: #{name}")
    puts C.d("  #{state[:conversation]&.length || 0} messages, #{@todos.length} todos")
  end
  
  def cmd_listen(*args)
    unless Voice.stt_available?
      puts "Listen unavailable: install whisper and sox"
      return
    end
    
    Voice.enable unless Voice.enabled?
    
    text = Voice.listen(duration: args[0]&.to_i || 5)
    if text && !text.empty?
      puts "You said: #{text}"
      chat_with_llm(text)
    else
      puts "No speech detected"
    end
  end

  def cmd_browse(*args)
    unless Web.available?
      puts C.r("Ferrum not available. Install: gem install ferrum")
      puts C.d("Also requires Chrome/Chromium in PATH")
      return
    end
    
    url = args.join(" ")
    if url.empty?
      puts "Usage: /browse <url> | /browse click <n> | /browse back"
      puts C.d("Web: #{Web.status}")
      return
    end
    
    # Handle navigation commands
    case args[0]
    when "click"
      index = args[1].to_i
      puts C.d("Clicking link #{index}...")
      result = Web.click(index)
    when "back"
      result = Web.back
    when "screenshot"
      result = Web.screenshot
      if result[:path]
        puts "Screenshot: #{result[:path]}"
        return
      end
    when "type"
      index = args[1].to_i
      text = args[2..].join(" ")
      result = Web.type(index, text)
      puts result[:success] ? "Typed: #{text}" : C.r(result[:error])
      return
    when "submit"
      result = Web.submit
    else
      # Regular URL navigation
      url = args.join(" ")
      url = "https://#{url}" unless url.match?(%r{^https?://})
      puts C.d("Fetching #{url}...")
      result = Web.goto(url)
    end
    
    if result[:error]
      puts C.r("Error: #{result[:error]}")
    else
      puts C.b(result[:title])
      puts result[:content][0..1500]
      puts C.d("...truncated") if result[:content].to_s.length > 1500
      
      # Show clickable links
      if result[:links]&.any?
        puts ""
        puts C.d("Links (use /browse click <n>):")
        result[:links].first(10).each do |link|
          puts C.d("  [#{link[:id]}] #{link[:text]}")
        end
      end
      
      # Add structured info to conversation for LLM reasoning
      context = "Browsed: #{result[:url]}\nTitle: #{result[:title]}\n\n"
      context += "Content:\n#{result[:content][0..3000]}\n\n"
      if result[:links]&.any?
        context += "Clickable links:\n"
        result[:links].first(15).each { |l| context += "[#{l[:id]}] #{l[:text]} -> #{l[:href]}\n" }
      end
      
      OpenRouterChat.add_context("web_page", context)
      puts C.d("Added to LLM context")
    end
  end

  def cmd_search(*args)
    unless Web.available?
      puts C.r("Ferrum not available. Install: gem install ferrum")
      return
    end
    
    query = args.join(" ")
    if query.empty?
      puts "Usage: /search <query>"
      return
    end
    
    puts C.d("Searching: #{query}...")
    result = Web.search(query)
    
    if result[:error]
      puts C.r("Error: #{result[:error]}")
    else
      puts C.b("Results for: #{query}")
      result[:results].each_with_index do |r, i|
        puts "#{i + 1}. #{r[:title]}"
        puts C.d("   #{r[:url]}")
      end
    end
  end

  def cmd_exit(*args)
    puts "✓ convergence complete"
    @running = false
  end
  
  def cmd_export(*args)
    path = args[0] || "convergence_export.json"
    data = {
      version: "1.7",
      timestamp: Time.now.iso8601,
      conversation: OpenRouterChat.export_conversation,
      model: OpenRouterChat.current_model,
      cost: OpenRouterChat.total_cost
    }
    File.write(path, JSON.pretty_generate(data))
    puts "Exported to #{path}"
  end
  
  def cmd_import(*args)
    path = args[0] || "convergence_export.json"
    unless File.exist?(path)
      puts C.r("File not found: #{path}")
      return
    end
    
    data = JSON.parse(File.read(path))
    OpenRouterChat.import_conversation(data["conversation"])
    puts "Imported #{data["conversation"]&.size || 0} messages from #{path}"
  end
  
  def cmd_sync(*args)
    puts C.d("Syncing...")
    
    # Push local changes
    push_result = `git push 2>&1`
    if $?.success?
      puts C.g("Pushed to origin")
    else
      puts C.r("Push failed: #{push_result}")
      return
    end
    
    # Pull on VPS via SSH (if configured)
    vps = ENV["VPS_HOST"] || "dev@vps"
    vps_path = ENV["VPS_PATH"] || "~/pub"
    
    ssh_result = `ssh #{vps} "cd #{vps_path} && git pull" 2>&1`
    if $?.success?
      puts C.g("VPS synced")
    else
      puts C.y("VPS sync skipped: #{ssh_result.lines.first}")
    end
  end

  def display_violations(file, violations)
    return if violations.empty?
    
    # Group by law
    by_law = violations.group_by(&:law).transform_values(&:count)
    breakdown = by_law.map { |law, count| "#{law}:#{count}" }.join(' ')
    
    puts "#{file}: #{violations.size} (#{breakdown})"
    
    # Show violations if verbose
    if Logger.instance_variable_get(:@verbose)
      violations.group_by(&:law).each do |law, law_violations|
        puts "  #{law}:"
        law_violations.each do |v|
          puts "    #{v}"
          
          # Show inline suggestions
          suggestions = InlineSuggestions.generate(v)
          suggestions.each { |s| puts "    #{s}" }
          
          # Show recurrence warning
          recurrence = ViolationTracker.analyze_recurrence(file)
          key = "L#{v.line} #{v.rule}"
          if recurrence[key] && recurrence[key] >= 3
            puts "    ⚠ recurring #{recurrence[key]}x"
          end
        end
      end
    end
  end

  def calculate_progress(results)
    total = results.size
    converged = results.count { |_, v| v.empty? }
    remaining = total - converged
    
    all_violations = results.values.flatten
    veto_count = all_violations.count(&:veto?)
    
    blockers = []
    blockers << "#{veto_count} veto violations" if veto_count > 0
    
    next_steps = []
    if veto_count > 0
      next_steps << "Fix #{veto_count} veto violations immediately"
    elsif remaining > 0
      next_steps << "Focus on #{remaining} remaining files"
    else
      next_steps << "All files converged ✓"
    end
    
    {
      total: total,
      converged: converged,
      remaining: remaining,
      percent: total.zero? ? 0 : (converged * 100 / total),
      veto: veto_count,
      blockers: blockers,
      next_steps: next_steps
    }
  end
end

# Main execution with crash recovery
if __FILE__ == $0
  MAX_CRASHES = 3
  crash_count = 0
  crash_log = File.expand_path("~/.cli_crashes.log")
  
  loop do
    begin
      cli = CLI.new
      cli.run
      break  # Clean exit
    rescue Interrupt
      puts "\n[interrupted]"
      break
    rescue => e
      crash_count += 1
      
      # Log the crash
      File.open(crash_log, "a") do |f|
        f.puts "#{Time.now.iso8601} | #{e.class}: #{e.message}"
        f.puts "  #{e.backtrace&.first(5)&.join("\n  ")}"
        f.puts
      end
      
      if crash_count >= MAX_CRASHES
        puts "\n❌ Crashed #{crash_count}x - giving up"
        puts "   Error: #{e.class}: #{e.message}"
        puts "   Log: #{crash_log}"
        exit 1
      else
        puts "\n⚠ Crashed (#{crash_count}/#{MAX_CRASHES}): #{e.message}"
        puts "   Auto-restarting in 2s... (Ctrl+C to exit)"
        # Kill any lingering process on our port before restart
        `fuser -k #{WEB_PORT}/tcp 2>/dev/null` rescue nil
        sleep 2
      end
    end
  end
end