#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# Force UTF-8 encoding for OpenBSD compatibility
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# MASTER.YML v1.5.0
# Code governance agent with chat-first UX
# Inspired by: Claude Code, Aider, OpenCode

require "yaml"
require "json"
require "fileutils"
require "optparse"
require "digest"
require "net/http"
require "uri"

# ANSI colors (no gem dependency)
module C
  def self.g(s) "\e[32m#{s}\e[0m" end  # green
  def self.r(s) "\e[31m#{s}\e[0m" end  # red
  def self.y(s) "\e[33m#{s}\e[0m" end  # yellow
  def self.d(s) "\e[90m#{s}\e[0m" end  # dim
  def self.b(s) "\e[1m#{s}\e[0m" end   # bold
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
        #{progress[:blockers].empty? ? '- None' : progress[:blockers].map { |b| "- #{b}" }.join("\n")}
        
        ## Next Steps
        #{progress[:next_steps].map { |s| "- #{s}" }.join("\n")}
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
      
      "⚠ Recurring violations detected:\n" + recurring.map { |k, v| "  #{k}: #{v}x" }.join("\n")
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
      content.sub!(/^# CONVERGENCE:.*?\n(?:# LAST_SCAN:.*?\n)?(?:# PERSONAS:.*?\n)?/, '')
      
      # Build new header
      breakdown = violations.group_by(&:law).transform_values(&:count)
      breakdown_str = breakdown.map { |l, c| "#{l}:#{c}" }.join(' ')
      
      header = "# CONVERGENCE: #{violations.size} violations (#{breakdown_str})\n"
      header += "# LAST_SCAN: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n"
      header += "# PERSONAS: #{personas.join(' ')}\n" unless personas.empty?
      
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
      content.sub!(/^# CONVERGENCE:.*?\n(?:# LAST_SCAN:.*?\n)?(?:# PERSONAS:.*?\n)?/, '')
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
      entries = content.split(/^---\s*$/).reject(&:empty?)
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
        requires = content.scan(/^require(?:_relative)?\s+['"]([^'"]+)['"]/).flatten
        
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
        param_count = violation.details[/\d+/].to_i
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
      details[/\d+/] || "VALUE"
    end
  end
end

# OpenRouterChat - Chat with LLMs via OpenRouter API
module OpenRouterChat
  ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
  DEFAULT_MODEL = "anthropic/claude-sonnet-4"
  
  class << self
    def init(config)
      @config = config
      @api_key = ENV["OPENROUTER_API_KEY"]
      @model = config.dig("chat", "model") || DEFAULT_MODEL
      @conversation = []
      @system_prompt = build_system_prompt(config)
    end
    
    def available?
      !@api_key.nil? && !@api_key.empty?
    end
    
    def chat(message)
      return Result.failure("OPENROUTER_API_KEY not set") unless available?
      
      @conversation << { role: "user", content: message }
      
      response = send_request
      
      if response[:error]
        Result.failure(response[:error])
      else
        assistant_message = response[:content]
        @conversation << { role: "assistant", content: assistant_message }
        Result.success(assistant_message)
      end
    end
    
    def clear_conversation
      @conversation = []
      Logger.info("conversation cleared")
    end
    
    def conversation_length
      @conversation.size
    end
    
    private
    
    def build_system_prompt(config)
      laws = (config["laws"] || {}).map { |name, data| "#{name}: #{data['principle']}" }.join("\n")
      
      <<~PROMPT
        You are Master.yml, a code governance agent on OpenBSD.
        
        RULES:
        - ONE shell command per response, wrapped in ```shell```
        - NO citations, NO web references, NO explanations
        - Execute first, explain only if asked
        - Be terse: max 2 sentences outside code blocks
        
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
      request["X-Title"] = "Convergence CLI"
      
      messages = [{ role: "system", content: @system_prompt }] + @conversation
      
      request.body = JSON.generate({
        model: @model,
        messages: messages,
        max_tokens: 4096,
        temperature: 0.7
      })
      
      response = http.request(request)
      body = JSON.parse(response.body)
      
      if response.code.to_i == 200
        content = body.dig("choices", 0, "message", "content")
        usage = body["usage"] || {}
        Logger.debug("tokens: #{usage['total_tokens']}")
        { content: content }
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
module Voice
  PIPER_MODEL = "en_US-lessac-low"  # Lofi grainy voice
  WHISPER_MODEL = "base.en"
  
  class << self
    def init(config)
      @config = config
      @enabled = false
      @tts_available = system("which piper > /dev/null 2>&1")
      @stt_available = system("which whisper > /dev/null 2>&1") || 
                       system("which whisper-cpp > /dev/null 2>&1")
      @sox_available = system("which sox > /dev/null 2>&1") ||
                       system("which rec > /dev/null 2>&1")
    end
    
    def available?
      @tts_available || @stt_available
    end
    
    def tts_available?
      @tts_available
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
    
    # Text-to-speech via Piper
    def speak(text)
      return unless @enabled && @tts_available
      return if text.nil? || text.strip.empty?
      
      # Clean text for speech
      clean = text.gsub(/```.*?```/m, "code block omitted")
                  .gsub(/\[.*?\]\(.*?\)/, "")  # Remove markdown links
                  .gsub(/[#*_`]/, "")           # Remove markdown formatting
                  .strip
      
      return if clean.empty?
      
      # Stream through Piper with lofi effects
      Thread.new do
        IO.popen([
          "sh", "-c",
          "echo #{clean.shellescape} | piper --model #{PIPER_MODEL} --output_raw 2>/dev/null | " \
          "ffmpeg -f s16le -ar 22050 -ac 1 -i - -af 'highpass=f=200,lowpass=f=5000' -f wav - 2>/dev/null | " \
          "play -q - 2>/dev/null || aplay -q - 2>/dev/null"
        ]) { |p| p.read }
      end
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
      parts << "tts:#{@tts_available ? 'ok' : 'no'}"
      parts << "stt:#{stt_available? ? 'ok' : 'no'}"
      parts << (@enabled ? "on" : "off")
      parts.join(" ")
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
    if rule["yaml_only"] && !path.match?(/\.ya?ml$/)
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
      puts C.g("● Sonnet 4.5 ready")
      puts C.d("Type to chat, /help for commands")
    else
      puts C.y("○ No API key")
      print "Paste OPENROUTER_API_KEY (Enter to skip): "
      key = gets&.strip
      
      if key && !key.empty?
        ENV["OPENROUTER_API_KEY"] = key
        OpenRouterChat.init(@config)
        
        if OpenRouterChat.available?
          puts C.g("● Key accepted")
          
          print "Save to ~/.zshrc? [y/N]: "
          save = gets&.strip&.downcase
          if save == "y"
            File.open(File.expand_path("~/.zshrc"), "a") do |f|
              f.puts "\nexport OPENROUTER_API_KEY=\"#{key}\""
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
      "listen" => method(:cmd_listen),
      "install-hook" => method(:cmd_install_hook),
      "uninstall-hook" => method(:cmd_uninstall_hook),
      "journal" => method(:cmd_journal),
      "patterns" => method(:cmd_patterns),
      "help" => method(:cmd_help),
      "exit" => method(:cmd_exit),
      "quit" => method(:cmd_exit)
    }
  end

  def repl
    while @running
      turns = OpenRouterChat.conversation_length
      prompt = turns > 0 ? C.d("[#{turns}] ") + "❯ " : "❯ "
      print prompt
      
      input = gets
      break unless input
      
      input = input.strip.force_encoding("UTF-8")
      next if input.empty?
      
      # H3: User control - Ctrl+C handled, /clear to reset
      # H7: Flexibility - / prefix for commands, plain text for chat
      if input.start_with?("/")
        parts = input[1..].split(/\s+/)
        command = parts[0].downcase
        args = parts[1..]
        
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
        chat_with_llm(input)
      end
    end
  rescue Interrupt
    # H3: User control - clean exit on Ctrl+C
    puts "\n[interrupted]"
  end
  
  def chat_with_llm(message)
    unless OpenRouterChat.available?
      puts "Chat unavailable: set OPENROUTER_API_KEY and restart"
      return
    end
    
    print "..."
    $stdout.flush
    
    result = OpenRouterChat.chat(message)
    print "\r   \r"
    
    if result.success?
      response = result.value
      
      # Speak response if voice enabled
      Voice.speak(response)
      
      # Check for tool calls in response
      if response.include?("```shell") || response.include?("```zsh") || response.include?("```ruby")
        handle_tool_response(response)
      else
        puts response
      end
    else
      puts "Error: #{result.error}"
      puts "Hint: check API key or try again"
    end
  end
  
  def handle_tool_response(response)
    puts response
    
    # Auto-execute shell/zsh blocks
    response.scan(/```(?:shell|zsh|bash)\n(.*?)```/m) do |match|
      command = match[0].strip
      next if command.empty?
      
      puts "\n→ #{command}"
      output = `#{command} 2>&1`
      puts output unless output.empty?
      
      # Feed result back to LLM for continuous operation
      OpenRouterChat.chat("Executed. Output:\n```\n#{output}\n```") unless output.strip.empty?
    end
    
    # Auto-execute ruby blocks
    response.scan(/```ruby\n(.*?)```/m) do |match|
      code = match[0].strip
      next if code.empty?
      next if code.include?("def ") # Skip method definitions (examples)
      
      puts "\n→ ruby: #{code.lines.first.strip}..."
      begin
        result = eval(code)
        puts result.inspect if result
      rescue => e
        puts "error: #{e.message}"
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
      puts "\niteration #{iter}/#{max_iter}"
      
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
      puts "Last #{entries.size} refactorings:\n\n"
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
    
    puts "Learned patterns:\n"
    
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
        /scan <file>     Scan single file
        /recursive       Scan all files
        /fix <file>      Auto-fix with RuboCop
        /converge <file> Iterative fix loop
        /dogfood         Scan master.yml and cli.rb
        /status          Show dashboard
        /voice           Toggle voice on/off
        /listen          Voice input mode
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
  
  def cmd_voice(*args)
    if Voice.available?
      enabled = Voice.toggle
      puts "Voice #{enabled ? 'on' : 'off'} (#{Voice.status})"
    else
      puts "Voice unavailable: install piper, whisper, sox"
    end
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

  def cmd_exit(*args)
    puts "✓ convergence complete"
    @running = false
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

# Main execution
if __FILE__ == $0
  cli = CLI.new
  cli.run
end