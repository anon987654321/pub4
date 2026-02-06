#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "pathname"
require "tempfile"
require "time"

class Result
  attr_reader :value, :error

  def initialize(is_success, val, err)
    @success = is_success
    @value = val
    @error = err
  end

  def self.ok(val)
    new(true, val, nil)
  end

  def self.err(msg)
    new(false, nil, msg)
  end

  def ok?
    @success
  end
end

module Options
  @quiet = false

  class << self
    attr_accessor :quiet
  end
end

module Dmesg
  VERSION = "38.2"

  GLYPHS = {
    folder: "📁",
    clean: "✨",
    check: "✅",
    cross: "❌",
    warn: "⚠️",
    rocket: "🚀",
    book: "📖",
    magnify: "🔍",
    wrench: "🔧",
    fire: "🔥",
    sparkles: "✨",
    thinking: "🤔",
    bulb: "💡",
    chart: "📊",
    clock: "⏱️",
    save: "💾"
  }.freeze

  FALLBACK_GLYPHS = {
    folder: "[dir]",
    clean: "[clean]",
    check: "[ok]",
    cross: "[fail]",
    warn: "[warn]",
    rocket: "[>]",
    book: "[doc]",
    magnify: "[?]",
    wrench: "[fix]",
    fire: "[!]",
    sparkles: "[*]",
    thinking: "[~]",
    bulb: "[i]",
    chart: "[#]",
    clock: "[t]",
    save: "[s]"
  }.freeze

  def self.color_enabled?
    !ENV["NO_COLOR"] && $stdout.tty?
  end

  def self.icon(name)
    if color_enabled?
      GLYPHS[name] || "•"
    else
      FALLBACK_GLYPHS[name] || "[x]"
    end
  end

  def self.colorize(text, code)
    return text unless color_enabled?
    "\e[#{code}m#{text}\e[0m"
  end

  def self.red(text)
    colorize(text, 31)
  end

  def self.green(text)
    colorize(text, 32)
  end

  def self.yellow(text)
    colorize(text, 33)
  end

  def self.blue(text)
    colorize(text, 34)
  end

  def self.magenta(text)
    colorize(text, 35)
  end

  def self.cyan(text)
    colorize(text, 36)
  end

  def self.bold(text)
    colorize(text, 1)
  end

  def self.dim(text)
    colorize(text, 2)
  end
end

module UI
  class Spinner
    FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze

    def initialize(message)
      @message = message
      @running = false
      @frame_idx = 0
    end

    def start
      return if Options.quiet || !$stdout.tty?
      @running = true
      @thread = Thread.new do
        while @running
          print "\r#{FRAMES[@frame_idx]} #{@message}"
          @frame_idx = (@frame_idx + 1) % FRAMES.length
          sleep 0.1
        end
      end
    end

    def stop(final_msg = nil)
      return unless @thread
      @running = false
      @thread.join
      print "\r\e[K"
      puts final_msg if final_msg
    end
  end

  class ProgressBar
    def initialize(total, label: "Progress")
      @total = total
      @current = 0
      @label = label
      @start_time = Time.now
    end

    def increment(msg = nil)
      @current += 1
      render(msg)
    end

    def render(msg = nil)
      return if Options.quiet || !$stdout.tty?

      pct = (@current.to_f / @total * 100).round
      bar_width = 30
      filled = (bar_width * @current / @total).to_i
      bar = "█" * filled + "░" * (bar_width - filled)

      elapsed = Time.now - @start_time
      rate = @current / elapsed
      eta = rate > 0 ? (@total - @current) / rate : 0

      line = "\r#{@label}: [#{bar}] #{pct}% (#{@current}/#{@total}) ETA: #{eta.round}s"
      line += " - #{msg}" if msg
      print line
      puts if @current == @total
    end
  end
end

module Core
  class ScoreCalculator
    DEDUCTION_PER_VIOLATION = 5
    MINIMUM_SCORE = 0
    MAXIMUM_SCORE = 100

    def self.calculate(violations)
      deductions = violations.length * DEDUCTION_PER_VIOLATION
      [MAXIMUM_SCORE - deductions, MINIMUM_SCORE].max
    end

    def self.analyze(violations)
      severity_counts = Hash.new(0)
      fixable_count = 0

      violations.each do |v|
        severity_counts[v["severity"]] += 1
        fixable_count += 1 if v["auto_fixable"]
      end

      {
        total: violations.length,
        by_severity: severity_counts,
        auto_fixable: fixable_count,
        score: calculate(violations)
      }
    end
  end

  class TokenEstimator
    AVG_CHARS_PER_TOKEN = 4.0

    def self.estimate(text)
      (text.length / AVG_CHARS_PER_TOKEN).ceil
    end

    def self.warn_if_expensive(text, threshold)
      tokens = estimate(text)
      {
        tokens: tokens,
        warning: tokens > threshold,
        message: tokens > threshold ? "Estimated #{tokens} tokens exceeds threshold of #{threshold}" : nil
      }
    end
  end

  class CostEstimator
    PRICING = {
      "qwen/qwen2.5-coder" => { input: 0.1, output: 0.3 },
      "anthropic/claude-3.5-sonnet" => { input: 3.0, output: 15.0 },
      "anthropic/claude-opus-4" => { input: 15.0, output: 75.0 },
      "meta-llama/llama-3.1-8b-instruct" => { input: 0.05, output: 0.08 },
      "google/gemini-pro-1.5" => { input: 1.25, output: 5.0 },
      "anthropic/claude-3-haiku" => { input: 0.25, output: 1.25 }
    }.freeze

    def self.estimate(model, input_tokens, output_tokens)
      rates = PRICING[model] || { input: 1.0, output: 1.0 }
      input_cost = (input_tokens * rates[:input]) / 1_000_000.0
      output_cost = (output_tokens * rates[:output]) / 1_000_000.0
      input_cost + output_cost
    end

    def self.compare_models(input_tokens, output_tokens)
      PRICING.map do |model, _|
        {
          model: model,
          cost: estimate(model, input_tokens, output_tokens)
        }
      end.sort_by { |m| m[:cost] }
    end
  end

  class ConvergenceDetector
    STUCK_THRESHOLD = 3
    OSCILLATION_WINDOW = 4

    def self.detect_loop(history)
      return false if history.length < STUCK_THRESHOLD

      recent = history.last(STUCK_THRESHOLD)
      violation_counts = recent.map { |h| h[:violations].length }

      violation_counts.uniq.length == 1 && violation_counts.first > 0
    end

    def self.detect_oscillation(history)
      return false if history.length < OSCILLATION_WINDOW

      recent = history.last(OSCILLATION_WINDOW)
      principle_ids = recent.map do |h|
        h[:violations].map { |v| v["principle_id"] }.sort
      end

      principle_ids.uniq.length == 2 && principle_ids.length == OSCILLATION_WINDOW
    end

    def self.improving?(history)
      return false if history.length < 2

      counts = history.map { |h| h[:violations].length }
      counts.each_cons(2).all? { |a, b| b < a }
    end

    def self.analyze(history)
      {
        stuck: detect_loop(history),
        oscillating: detect_oscillation(history),
        improving: improving?(history),
        trend: calculate_trend(history)
      }
    end

    def self.calculate_trend(history)
      return :unknown if history.length < 3

      counts = history.last(5).map { |h| h[:violations].length }
      diffs = counts.each_cons(2).map { |a, b| b - a }
      avg_change = diffs.sum.to_f / diffs.length

      if avg_change < -0.5
        :improving
      elsif avg_change > 0.5
        :degrading
      else
        :stable
      end
    end
  end

  class LanguageDetector
    def self.detect_by_extension(filepath, supported_langs)
      ext = File.extname(filepath)
      supported_langs.each do |lang, config|
        return lang if config["extensions"]&.include?(ext)
      end
      "unknown"
    end

    def self.detect_by_content(content, supported_langs)
      best_match = "unknown"
      max_score = 0

      supported_langs.each do |lang, config|
        next unless config["indicators"]

        score = config["indicators"].count { |ind| content.include?(ind) }
        if score > max_score
          max_score = score
          best_match = lang
        end
      end

      best_match
    end

    def self.detect_with_fallback(filepath, content, supported_langs)
      lang = detect_by_extension(filepath, supported_langs)
      return lang unless lang == "unknown"

      detect_by_content(content, supported_langs)
    end
  end

  class LLMDetector
    def self.parse_violations(response_text)
      cleaned = response_text.strip
      cleaned = cleaned.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")

      JSON.parse(cleaned)
    rescue JSON::ParserError
      []
    end

    def self.build_principle_summary(principles)
      lines = ["# Code Principles\n"]

      principles.each do |key, principle|
        lines << "## #{principle['id']}. #{principle['name']}"
        lines << "Rule: #{principle['rule']}"
        lines << "Priority #{principle['priority']}"

        if principle['smells']
          smells = principle['smells'].is_a?(Hash) ? principle['smells'].keys : principle['smells']
          lines << "Smells: #{smells.join(', ')}"
        end

        lines << ""
      end

      lines.join("\n")
    end

    def self.call_llm(prompt, model = "anthropic/claude-3.5-sonnet")
      # Placeholder for actual LLM API call
      { response: "[]", tokens_in: 100, tokens_out: 50 }
    end
  end

  class PrincipleRegistry
    def self.find_by_id(principles, id)
      principles.values.find { |p| p["id"] == id }
    end

    def self.find_by_smell(principles, smell)
      principles.values.select do |p|
        smells = p["smells"]
        next false unless smells

        if smells.is_a?(Hash)
          smells.keys.include?(smell) || smells.values.any? { |v| v.is_a?(Hash) && v["patterns"]&.include?(smell) }
        else
          smells.include?(smell)
        end
      end
    end

    def self.auto_fixable(principles)
      principles.values.select { |p| p["auto_fixable"] == true }
    end

    def self.max_priority(principles)
      principles.values.map { |p| p["priority"] || 0 }.max || 0
    end

    def self.validate_no_cycles(principles)
      # Simple validation - check for duplicate IDs
      ids = principles.values.map { |p| p["id"] }
      duplicates = ids.select { |id| ids.count(id) > 1 }.uniq

      {
        valid: duplicates.empty?,
        errors: duplicates.map { |id| "Duplicate principle ID: #{id}" }
      }
    end

    def self.load_from_yaml(path)
      config = YAML.load_file(path)
      config["principles"] || {}
    rescue => e
      warn "Failed to load principles: #{e.message}"
      {}
    end
  end

  class FileCleaner
    TEXT_EXTENSIONS = %w[.rb .py .js .ts .java .c .cpp .h .hpp .go .rs .php .md .txt .yml .yaml .json .xml .html .css .scss .sh].freeze
    BINARY_EXTENSIONS = %w[.png .jpg .jpeg .gif .bmp .ico .pdf .zip .tar .gz .exe .dll .so .dylib .a .o].freeze

    def self.text_file?(filepath)
      ext = File.extname(filepath).downcase
      return false if BINARY_EXTENSIONS.include?(ext)
      TEXT_EXTENSIONS.include?(ext) || ext.empty?
    end

    def self.clean(filepath)
      return unless text_file?(filepath)
      return unless File.exist?(filepath)

      content = File.read(filepath)
      original = content.dup

      content = remove_trailing_whitespace(content)
      content = normalize_line_endings(content)
      content = collapse_blank_lines(content)

      File.write(filepath, content) if content != original
    end

    def self.remove_trailing_whitespace(text)
      text.gsub(/ +$/, "")
    end

    def self.normalize_line_endings(text)
      text.gsub(/\r\n/, "\n")
    end

    def self.collapse_blank_lines(text)
      text.gsub(/\n{3,}/, "\n\n")
    end

    def self.bulk_clean(directory)
      count = 0
      Dir.glob(File.join(directory, "**", "*")).each do |file|
        next unless File.file?(file)
        next unless text_file?(file)

        clean(file)
        count += 1
      end
      count
    end
  end
end

class UserPreferences
  DEFAULT_PREFS = {
    "model" => "anthropic/claude-3.5-sonnet",
    "consensus_threshold" => 0.7,
    "auto_fix" => false,
    "severity_filter" => "medium",
    "output_format" => "text",
    "remembered_choices" => {}
  }.freeze

  def initialize(prefs_file = ".convergence_prefs.json")
    @prefs_file = prefs_file
    @prefs = load_preferences
  end

  def load_preferences
    return DEFAULT_PREFS.dup unless File.exist?(@prefs_file)

    JSON.parse(File.read(@prefs_file))
  rescue JSON::ParserError
    DEFAULT_PREFS.dup
  end

  def save
    File.write(@prefs_file, JSON.pretty_generate(@prefs))
  end

  def get(key)
    @prefs[key]
  end

  def set(key, value)
    @prefs[key] = value
    save
  end

  def remember_choice(context, choice)
    @prefs["remembered_choices"] ||= {}
    @prefs["remembered_choices"][context] = choice
    save
  end

  def recall_choice(context)
    @prefs.dig("remembered_choices", context)
  end
end

class HistoricalTrends
  def initialize(history_file = ".convergence_history.jsonl")
    @history_file = history_file
  end

  def record(data)
    entry = data.merge(timestamp: Time.now.iso8601)
    File.open(@history_file, "a") do |f|
      f.puts(JSON.generate(entry))
    end
  end

  def load_recent(days = 30)
    return [] unless File.exist?(@history_file)

    cutoff = Time.now - (days * 24 * 60 * 60)
    entries = []

    File.readlines(@history_file).each do |line|
      entry = JSON.parse(line)
      entry_time = Time.parse(entry["timestamp"])
      entries << entry if entry_time > cutoff
    end

    entries
  rescue => e
    warn "Failed to load history: #{e.message}"
    []
  end

  def calculate_metrics(entries)
    return {} if entries.empty?

    violations_per_day = entries.group_by { |e| Time.parse(e["timestamp"]).to_date }
                                .transform_values { |v| v.sum { |e| e["violations"]&.length || 0 } }

    {
      total_runs: entries.length,
      avg_violations: entries.map { |e| e["violations"]&.length || 0 }.sum.to_f / entries.length,
      violations_per_day: violations_per_day,
      trend: analyze_trend(violations_per_day)
    }
  end

  def analyze_trend(daily_data)
    return :unknown if daily_data.length < 3

    values = daily_data.values.last(7)
    avg_change = values.each_cons(2).map { |a, b| b - a }.sum.to_f / (values.length - 1)

    if avg_change < -0.5
      :improving
    elsif avg_change > 0.5
      :degrading
    else
      :stable
    end
  end
end

class DomainVocabulary
  def initialize(vocab_file = ".dictionary.txt")
    @vocab_file = vocab_file
    @terms = load_vocabulary
  end

  def load_vocabulary
    return [] unless File.exist?(@vocab_file)

    File.readlines(@vocab_file).map(&:strip).reject(&:empty?)
  end

  def add_term(term)
    return if @terms.include?(term)

    @terms << term
    save
  end

  def save
    File.write(@vocab_file, @terms.sort.join("\n") + "\n")
  end

  def suggest_replacements(generic_term)
    @terms.select { |t| t.include?(generic_term) || generic_term.include?(t) }
  end

  def extract_from_codebase(directory)
    pattern = /(?:class|def|const|let|var)\s+([A-Z][a-zA-Z0-9_]*)/
    extracted = []

    Dir.glob(File.join(directory, "**", "*.{rb,js,py}")).each do |file|
      content = File.read(file)
      matches = content.scan(pattern).flatten
      extracted.concat(matches)
    end

    extracted.uniq.each { |term| add_term(term) }
    extracted.length
  end
end

class FrameworkDetector
  FRAMEWORK_SIGNATURES = {
    "rails" => {
      files: ["Gemfile", "config/routes.rb", "app/controllers/application_controller.rb"],
      patterns: ["Rails.application", "ActiveRecord::Base"]
    },
    "django" => {
      files: ["manage.py", "settings.py"],
      patterns: ["from django", "INSTALLED_APPS"]
    },
    "react" => {
      files: ["package.json"],
      patterns: ["import React", "from 'react'"]
    },
    "express" => {
      files: ["package.json"],
      patterns: ["express()", "app.listen"]
    }
  }.freeze

  def self.detect(directory)
    detected = []

    FRAMEWORK_SIGNATURES.each do |framework, signature|
      has_files = signature[:files].any? { |f| File.exist?(File.join(directory, f)) }
      next unless has_files

      has_patterns = false
      signature[:patterns].each do |pattern|
        if grep_codebase(directory, pattern)
          has_patterns = true
          break
        end
      end

      detected << framework if has_patterns
    end

    detected
  end

  def self.grep_codebase(directory, pattern)
    Dir.glob(File.join(directory, "**", "*.{rb,js,py}")).any? do |file|
      File.read(file).include?(pattern)
    end
  rescue
    false
  end

  def self.get_framework_rules(framework, config)
    config.dig("intelligence", "frameworks", framework) || {}
  end
end

class ModelSelector
  def initialize(config)
    @config = config
    @models = config.dig("meta", "models") || {}
  end

  def select_for_task(task_type, file_size = nil)
    model_config = @models.values.find do |m|
      m["use_for"]&.include?(task_type.to_s)
    end

    return model_config["id"] if model_config

    # Fallback logic
    if file_size && file_size < 1000
      @models.dig("fast", "id")
    else
      @models.dig("balanced", "id")
    end
  end

  def get_model_info(model_id)
    @models.values.find { |m| m["id"] == model_id }
  end

  def optimize_for_budget(max_cost, input_tokens, output_tokens)
    affordable = @models.values.select do |m|
      cost = Core::CostEstimator.estimate(m["id"], input_tokens, output_tokens)
      cost <= max_cost
    end

    affordable.min_by do |m|
      m["input_cost_per_mtok"] + m["output_cost_per_mtok"]
    end
  end
end

class ViolationClusterer
  def initialize(similarity_threshold = 0.7)
    @threshold = similarity_threshold
  end

  def cluster(violations)
    clusters = []

    violations.each do |violation|
      added_to_cluster = false

      clusters.each do |cluster|
        if similar?(violation, cluster.first)
          cluster << violation
          added_to_cluster = true
          break
        end
      end

      clusters << [violation] unless added_to_cluster
    end

    clusters
  end

  def similar?(v1, v2)
    principle_match = v1["principle_id"] == v2["principle_id"]
    file_match = v1["file"] == v2["file"]
    line_proximity = v1["line"] && v2["line"] && (v1["line"] - v2["line"]).abs < 10

    matches = [principle_match, file_match, line_proximity].count(true)
    (matches.to_f / 3) >= @threshold
  end

  def analyze_clusters(clusters)
    {
      total_clusters: clusters.length,
      largest_cluster: clusters.max_by(&:length)&.length || 0,
      avg_cluster_size: clusters.map(&:length).sum.to_f / clusters.length,
      patterns: identify_patterns(clusters)
    }
  end

  def identify_patterns(clusters)
    clusters.select { |c| c.length > 2 }.map do |cluster|
      {
        count: cluster.length,
        principle_id: cluster.first["principle_id"],
        file: cluster.first["file"],
        suggestion: "This pattern repeats #{cluster.length} times"
      }
    end
  end
end

class ViolationTriage
  ACTIONS = %w[fix skip suppress explain].freeze

  def initialize(violations)
    @violations = violations
    @decisions = {}
  end

  def interactive_triage
    return @decisions unless $stdout.tty?

    @violations.each_with_index do |violation, idx|
      puts "\n#{Dmesg.cyan("Violation #{idx + 1}/#{@violations.length}")}"
      puts "Principle: #{violation['principle_name']}"
      puts "File: #{violation['file']}:#{violation['line']}"
      puts "Message: #{violation['message']}"

      action = prompt_action
      @decisions[idx] = action
    end

    @decisions
  end

  def prompt_action
    puts "\nActions: [f]ix, [s]kip, [u]suppress, [e]xplain, [q]uit"
    print "> "

    case $stdin.gets&.strip&.downcase
    when "f" then "fix"
    when "s" then "skip"
    when "u" then "suppress"
    when "e" then "explain"
    when "q" then exit(0)
    else
      puts "Invalid choice, skipping..."
      "skip"
    end
  end

  def apply_decisions(auto_fixer)
    @decisions.each do |idx, action|
      violation = @violations[idx]

      case action
      when "fix"
        auto_fixer.apply_fix(violation)
      when "suppress"
        add_suppression(violation)
      when "explain"
        show_explanation(violation)
      end
    end
  end

  def add_suppression(violation)
    # Placeholder for suppression logic
    puts "Added suppression for #{violation['file']}:#{violation['line']}"
  end

  def show_explanation(violation)
    puts "\n#{Dmesg.blue('Explanation:')}"
    puts violation['explanation'] || "No detailed explanation available"
  end
end

class WatchMode
  def initialize(directory, pipeline)
    @directory = directory
    @pipeline = pipeline
    @file_mtimes = {}
  end

  def start
    puts "#{Dmesg.icon(:rocket)} Watch mode started. Press Ctrl+C to stop."
    scan_initial_files

    loop do
      changed_files = detect_changes
      if changed_files.any?
        puts "\n#{Dmesg.yellow("Detected changes in #{changed_files.length} file(s)")}"
        process_changes(changed_files)
      end

      sleep 2
    end
  rescue Interrupt
    puts "\n#{Dmesg.icon(:check)} Watch mode stopped."
  end

  def scan_initial_files
    Dir.glob(File.join(@directory, "**", "*.{rb,js,py}")).each do |file|
      @file_mtimes[file] = File.mtime(file)
    end
  end

  def detect_changes
    changed = []
    current_files = Dir.glob(File.join(@directory, "**", "*.{rb,js,py}"))

    current_files.each do |file|
      mtime = File.mtime(file)
      if !@file_mtimes[file] || @file_mtimes[file] < mtime
        changed << file
        @file_mtimes[file] = mtime
      end
    end

    changed
  end

  def process_changes(files)
    files.each do |file|
      result = @pipeline.analyze_file(file)
      display_results(file, result)
    end
  end

  def display_results(file, result)
    if result[:violations].empty?
      puts "  #{Dmesg.green('✓')} #{file} - Clean"
    else
      puts "  #{Dmesg.red('✗')} #{file} - #{result[:violations].length} violations"
    end
  end
end

class CommitMessageGenerator
  def initialize(config)
    @config = config
    @template = config.dig("autonomy", "workflow_shortcuts", "commit_message_generation", "template")
  end

  def generate(violations_fixed, files_changed)
    principles = violations_fixed.map { |v| v["principle_name"] }.uniq
    files = files_changed.map { |f| File.basename(f) }.take(3)

    message = "Fix: #{principles.join(', ')} in #{files.join(', ')}"
    message += " and #{files_changed.length - 3} more" if files_changed.length > 3
    message
  end

  def generate_detailed(before_score, after_score, violations)
    summary = generate(violations, violations.map { |v| v["file"] }.uniq)
    body = [
      "Score improvement: #{before_score} -> #{after_score}",
      "Violations fixed: #{violations.length}",
      "",
      "Details:"
    ]

    violations.group_by { |v| v["principle_name"] }.each do |principle, viols|
      body << "- #{principle}: #{viols.length} occurrences"
    end

    "#{summary}\n\n#{body.join("\n")}"
  end
end

class PRDescriptionGenerator
  def initialize(config)
    @config = config
  end

  def generate(analysis_results)
    sections = []

    sections << "## Summary"
    sections << summary_section(analysis_results)
    sections << ""
    sections << "## Metrics"
    sections << metrics_section(analysis_results)
    sections << ""
    sections << "## Changes"
    sections << changes_section(analysis_results)
    sections << ""
    sections << "## Checklist"
    sections << checklist_section

    sections.join("\n")
  end

  def summary_section(results)
    "This PR improves code quality by addressing #{results[:violations_fixed]} violations across #{results[:files_changed]} files."
  end

  def metrics_section(results)
    [
      "- **Before Score**: #{results[:score_before]}/100",
      "- **After Score**: #{results[:score_after]}/100",
      "- **Improvement**: +#{results[:score_after] - results[:score_before]} points",
      "- **Violations Fixed**: #{results[:violations_fixed]}"
    ].join("\n")
  end

  def changes_section(results)
    changes = results[:changes] || []
    changes.map { |c| "- #{c[:file]}: #{c[:description]}" }.join("\n")
  end

  def checklist_section
    [
      "- [ ] Tests pass",
      "- [ ] Documentation updated",
      "- [ ] Code reviewed",
      "- [ ] No new violations introduced"
    ].join("\n")
  end
end

class BlameIntegration
  def self.annotate_violations(violations)
    violations.map do |v|
      author_info = get_git_blame(v["file"], v["line"])
      v.merge("author" => author_info[:author], "commit" => author_info[:commit])
    end
  end

  def self.get_git_blame(file, line)
    return { author: "unknown", commit: "unknown" } unless File.exist?(file)

    blame_output = `git blame -L #{line},#{line} #{file} 2>/dev/null`.strip
    return { author: "unknown", commit: "unknown" } if blame_output.empty?

    parts = blame_output.split(/\s+/)
    {
      commit: parts[0],
      author: parts[1..2].join(" ").gsub(/[()]/, "")
    }
  rescue
    { author: "unknown", commit: "unknown" }
  end

  def self.group_by_author(violations)
    violations.group_by { |v| v["author"] || "unknown" }
  end
end

class SuppressionLearner
  def initialize(suppression_file = ".convergence_suppress.yml")
    @suppression_file = suppression_file
    @suppressions = load_suppressions
    @false_positives = []
  end

  def load_suppressions
    return {} unless File.exist?(@suppression_file)

    YAML.load_file(@suppression_file) || {}
  rescue
    {}
  end

  def save
    File.write(@suppression_file, YAML.dump(@suppressions))
  end

  def should_suppress?(violation)
    key = suppression_key(violation)
    @suppressions[key] == true
  end

  def add_suppression(violation, reason = "manual")
    key = suppression_key(violation)
    @suppressions[key] = { reason: reason, added_at: Time.now.iso8601 }
    save
  end

  def suggest_suppression(violation, occurrence_count)
    return false if occurrence_count < 3

    puts "\n#{Dmesg.yellow('Suggestion:')} This violation has occurred #{occurrence_count} times."
    puts "Would you like to suppress it? (y/n)"
    answer = $stdin.gets&.strip&.downcase

    if answer == "y"
      add_suppression(violation, "auto_suggested")
      true
    else
      false
    end
  end

  def suppression_key(violation)
    "#{violation['file']}:#{violation['line']}:#{violation['principle_id']}"
  end

  def learn_from_feedback(violation, is_false_positive)
    if is_false_positive
      @false_positives << violation
      add_suppression(violation, "false_positive")
    end
  end
end

class BulkOperations
  def initialize(config)
    @config = config
    @max_parallel = config.dig("autonomy", "bulk_operations", "max_parallel") || 4
  end

  def analyze_directory(directory, pipeline)
    files = find_analyzable_files(directory)
    puts "#{Dmesg.icon(:magnify)} Found #{files.length} files to analyze"

    results = []
    progress = UI::ProgressBar.new(files.length, label: "Analyzing")

    files.each do |file|
      result = pipeline.analyze_file(file)
      results << { file: file, result: result }
      progress.increment(File.basename(file))
    end

    aggregate_results(results)
  end

  def find_analyzable_files(directory)
    Dir.glob(File.join(directory, "**", "*.{rb,js,py,java,go}")).reject do |f|
      f.include?("node_modules") || f.include?("vendor") || f.include?(".git")
    end
  end

  def aggregate_results(results)
    total_violations = results.sum { |r| r[:result][:violations].length }
    files_with_violations = results.count { |r| r[:result][:violations].any? }

    {
      total_files: results.length,
      files_with_violations: files_with_violations,
      total_violations: total_violations,
      results: results
    }
  end

  def fix_all(results, auto_fixer)
    fixable = results.flat_map { |r| r[:result][:violations] }.select { |v| v["auto_fixable"] }

    puts "\n#{Dmesg.icon(:wrench)} Found #{fixable.length} auto-fixable violations"
    return if fixable.empty?

    progress = UI::ProgressBar.new(fixable.length, label: "Fixing")
    fixed_count = 0

    fixable.each do |violation|
      if auto_fixer.apply_fix(violation)
        fixed_count += 1
      end
      progress.increment
    end

    puts "\n#{Dmesg.green("Fixed #{fixed_count}/#{fixable.length} violations")}"
  end
end

class WhitelistHandler
  def initialize(whitelist_file = ".convergence_whitelist.txt")
    @whitelist_file = whitelist_file
    @patterns = load_whitelist
  end

  def load_whitelist
    return [] unless File.exist?(@whitelist_file)

    File.readlines(@whitelist_file).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
  end

  def whitelisted?(file_path)
    @patterns.any? do |pattern|
      File.fnmatch(pattern, file_path, File::FNM_PATHNAME)
    end
  end

  def add_pattern(pattern)
    @patterns << pattern unless @patterns.include?(pattern)
    save
  end

  def save
    File.write(@whitelist_file, @patterns.join("\n") + "\n")
  end
end

class DiffBasedAnalyzer
  def initialize
    @git_available = system("git --version > /dev/null 2>&1")
  end

  def analyze_uncommitted_changes
    return nil unless @git_available

    diff = `git diff --unified=0`.split("\n")
    changed_lines = parse_diff(diff)

    {
      files: changed_lines.keys,
      changed_lines: changed_lines
    }
  end

  def parse_diff(diff_lines)
    changed = {}
    current_file = nil

    diff_lines.each do |line|
      if line.start_with?("+++")
        current_file = line.split(" ").last.sub(%r{^b/}, "")
        changed[current_file] ||= []
      elsif line.match?(/^@@ -\d+,?\d* \+(\d+),?(\d*)/)
        match = line.match(/^@@ -\d+,?\d* \+(\d+),?(\d*)/)
        start_line = match[1].to_i
        line_count = match[2].to_i
        line_count = 1 if line_count.zero?

        (start_line...(start_line + line_count)).each do |ln|
          changed[current_file] << ln
        end
      end
    end

    changed
  end

  def filter_violations(violations, changed_lines)
    violations.select do |v|
      file_changes = changed_lines[v["file"]]
      file_changes && file_changes.include?(v["line"])
    end
  end
end

class Violation
  attr_reader :principle_id, :line, :message, :severity, :auto_fixable

  def initialize(data)
    @principle_id = data["principle_id"]
    @line = data["line"]
    @message = data["message"]
    @severity = data["severity"] || "medium"
    @auto_fixable = data["auto_fixable"] || false
    @file = data["file"]
    @suggestion = data["suggestion"]
  end

  def to_h
    {
      "principle_id" => @principle_id,
      "line" => @line,
      "message" => @message,
      "severity" => @severity,
      "auto_fixable" => @auto_fixable,
      "file" => @file,
      "suggestion" => @suggestion
    }
  end

  def critical?
    @severity == "critical"
  end

  def high?
    @severity == "high"
  end
end

class LineScanner
  def initialize(principles)
    @principles = principles
  end

  def scan_file(filepath)
    return [] unless File.exist?(filepath)

    content = File.read(filepath)
    violations = []

    content.lines.each_with_index do |line, idx|
      line_violations = scan_line(line, idx + 1, filepath)
      violations.concat(line_violations)
    end

    violations
  end

  def scan_line(line, line_number, filepath)
    violations = []

    @principles.each do |key, principle|
      next unless principle["smells"]

      smells = extract_smell_patterns(principle["smells"])
      smells.each do |smell|
        if line.include?(smell)
          violations << create_violation(principle, line_number, smell, filepath)
        end
      end
    end

    violations
  end

  def extract_smell_patterns(smells)
    patterns = []

    if smells.is_a?(Hash)
      smells.each_value do |smell_config|
        if smell_config.is_a?(Hash) && smell_config["patterns"]
          patterns.concat(smell_config["patterns"])
        end
      end
    elsif smells.is_a?(Array)
      patterns.concat(smells)
    end

    patterns
  end

  def create_violation(principle, line_number, smell, filepath)
    Violation.new(
      "principle_id" => principle["id"],
      "line" => line_number,
      "message" => "#{principle['name']}: Found '#{smell}'",
      "severity" => principle["severity"] || "medium",
      "auto_fixable" => principle["auto_fixable"] || false,
      "file" => filepath
    )
  end
end

class AutoFixer
  def initialize(config, principles)
    @config = config
    @principles = principles
  end

  def apply_fix(violation)
    return false unless violation["auto_fixable"]

    principle = @principles.values.find { |p| p["id"] == violation["principle_id"] }
    return false unless principle

    fix_method = "fix_#{principle['name'].downcase.gsub(' ', '_')}"
    if respond_to?(fix_method, true)
      send(fix_method, violation)
    else
      false
    end
  end

  private

  def fix_clarity(violation)
    return false unless violation["file"] && File.exist?(violation["file"])

    content = File.read(violation["file"])
    lines = content.lines

    return false unless lines[violation["line"] - 1]

    # Simple example: replace generic verbs
    line = lines[violation["line"] - 1]
    modified = line.gsub(/def process/, "def transform")
                  .gsub(/def handle/, "def respond_to")
                  .gsub(/def get/, "def fetch")

    if modified != line
      lines[violation["line"] - 1] = modified
      File.write(violation["file"], lines.join)
      true
    else
      false
    end
  end

  def fix_consistency(violation)
    # Placeholder for consistency fixes
    false
  end
end

class SemanticAnalyzer
  def initialize(config, vocab)
    @config = config
    @vocab = vocab
  end

  def analyze_naming(code)
    suggestions = []
    generic_terms = %w[data info thing object value item stuff]

    code.scan(/(?:def|class|const|let|var)\s+(\w+)/) do |match|
      name = match[0]
      generic_terms.each do |term|
        if name.downcase.include?(term)
          replacements = @vocab.suggest_replacements(term)
          suggestions << {
            original: name,
            issue: "Contains generic term '#{term}'",
            suggestions: replacements
          }
        end
      end
    end

    suggestions
  end

  def suggest_improvements(violation)
    principle_id = violation["principle_id"]
    case principle_id
    when 1
      suggest_clarity_improvements(violation)
    when 2
      suggest_simplicity_improvements(violation)
    else
      []
    end
  end

  def suggest_clarity_improvements(violation)
    @vocab.suggest_replacements(violation["message"].split.last)
  end

  def suggest_simplicity_improvements(violation)
    ["Extract method", "Reduce nesting", "Use guard clauses"]
  end
end

class UsageTracker
  def initialize(tracker_file = ".convergence_usage.jsonl")
    @tracker_file = tracker_file
  end

  def track(event_type, data = {})
    entry = {
      event: event_type,
      timestamp: Time.now.iso8601,
      data: data
    }

    File.open(@tracker_file, "a") do |f|
      f.puts(JSON.generate(entry))
    end
  end

  def get_statistics(days = 30)
    entries = load_recent_entries(days)

    {
      total_events: entries.length,
      by_type: entries.group_by { |e| e["event"] }.transform_values(&:count),
      total_cost: entries.sum { |e| e.dig("data", "cost") || 0 },
      total_tokens: entries.sum { |e| e.dig("data", "tokens") || 0 }
    }
  end

  def load_recent_entries(days)
    return [] unless File.exist?(@tracker_file)

    cutoff = Time.now - (days * 24 * 60 * 60)
    entries = []

    File.readlines(@tracker_file).each do |line|
      entry = JSON.parse(line)
      timestamp = Time.parse(entry["timestamp"])
      entries << entry if timestamp > cutoff
    end

    entries
  rescue
    []
  end
end

class BugHuntingAnalyzer
  def initialize(config)
    @config = config
  end

  def hunt_bugs(code, language)
    bugs = []
    bugs.concat(check_sql_injection(code)) if language == "ruby"
    bugs.concat(check_xss_vulnerabilities(code)) if ["javascript", "ruby"].include?(language)
    bugs.concat(check_hardcoded_secrets(code))
    bugs
  end

  def check_sql_injection(code)
    findings = []
    code.lines.each_with_index do |line, idx|
      if line.match?(/(SELECT|INSERT|UPDATE|DELETE).*#\{/)
        findings << {
          line: idx + 1,
          type: "sql_injection",
          severity: "critical",
          message: "Possible SQL injection via string interpolation"
        }
      end
    end
    findings
  end

  def check_xss_vulnerabilities(code)
    findings = []
    code.lines.each_with_index do |line, idx|
      if line.match?(/innerHTML\s*=/) || line.match?(/raw\(/)
        findings << {
          line: idx + 1,
          type: "xss",
          severity: "high",
          message: "Potential XSS vulnerability"
        }
      end
    end
    findings
  end

  def check_hardcoded_secrets(code)
    findings = []
    secret_patterns = [
      /api_key\s*=\s*["'][^"']+["']/i,
      /password\s*=\s*["'][^"']+["']/i,
      /secret\s*=\s*["'][^"']+["']/i,
      /token\s*=\s*["'][^"']+["']/i
    ]

    code.lines.each_with_index do |line, idx|
      secret_patterns.each do |pattern|
        if line.match?(pattern)
          findings << {
            line: idx + 1,
            type: "hardcoded_secret",
            severity: "critical",
            message: "Hardcoded credential detected"
          }
        end
      end
    end
    findings
  end
end

class Formatter
  def initialize(format_type = "text")
    @format = format_type
  end

  def format_results(results)
    case @format
    when "json"
      format_json(results)
    when "markdown"
      format_markdown(results)
    else
      format_text(results)
    end
  end

  def format_json(results)
    JSON.pretty_generate(results)
  end

  def format_markdown(results)
    lines = []
    lines << "# Code Analysis Report"
    lines << ""
    lines << "## Summary"
    lines << "- **Score**: #{results[:score]}/100"
    lines << "- **Total Violations**: #{results[:violations].length}"
    lines << "- **Auto-fixable**: #{results[:auto_fixable]}"
    lines << ""

    if results[:violations].any?
      lines << "## Violations"
      results[:violations].group_by { |v| v["severity"] }.each do |severity, viols|
        lines << ""
        lines << "### #{severity.capitalize} (#{viols.length})"
        viols.each do |v|
          lines << "- [ ] **Line #{v['line']}**: #{v['message']}"
        end
      end
    end

    lines.join("\n")
  end

  def format_text(results)
    lines = []
    lines << "#{Dmesg.bold('Analysis Results')}"
    lines << "Score: #{colorize_score(results[:score])}/100"
    lines << "Violations: #{results[:violations].length}"
    lines << ""

    if results[:violations].any?
      results[:violations].each do |v|
        severity_icon = severity_icon(v["severity"])
        lines << "#{severity_icon} Line #{v['line']}: #{v['message']}"
      end
    else
      lines << "#{Dmesg.green('✓')} No violations found!"
    end

    lines.join("\n")
  end

  def colorize_score(score)
    if score >= 90
      Dmesg.green(score.to_s)
    elsif score >= 70
      Dmesg.yellow(score.to_s)
    else
      Dmesg.red(score.to_s)
    end
  end

  def severity_icon(severity)
    case severity
    when "critical" then Dmesg.red("⛔")
    when "high" then Dmesg.red("❗")
    when "medium" then Dmesg.yellow("⚠️")
    when "low" then Dmesg.blue("ℹ️")
    else "•"
    end
  end
end

class Pipeline
  def initialize(config_path = "master.yml")
    @config = load_config(config_path)
    @principles = @config["principles"] || {}
    @model_selector = ModelSelector.new(@config)
    @history = HistoricalTrends.new
    @vocab = DomainVocabulary.new
    @tracker = UsageTracker.new
  end

  def load_config(path)
    YAML.load_file(path)
  rescue => e
    warn "Failed to load config: #{e.message}"
    { "principles" => {} }
  end

  def analyze_file(filepath)
    return Result.err("File not found") unless File.exist?(filepath)

    spinner = UI::Spinner.new("Analyzing #{File.basename(filepath)}")
    spinner.start

    scanner = LineScanner.new(@principles)
    violations = scanner.scan_file(filepath)

    # Enhance with semantic analysis
    if @config.dig("intelligence", "semantic_understanding", "enabled")
      semantic = SemanticAnalyzer.new(@config, @vocab)
      content = File.read(filepath)
      naming_issues = semantic.analyze_naming(content)
      # Add to violations if needed
    end

    # Bug hunting
    if @config.dig("principles", "security")
      bug_hunter = BugHuntingAnalyzer.new(@config)
      language = detect_language(filepath)
      bugs = bug_hunter.hunt_bugs(File.read(filepath), language)
      violations.concat(bugs.map { |b| Violation.new(b.merge("principle_id" => 7, "file" => filepath)) })
    end

    score = Core::ScoreCalculator.calculate(violations.map(&:to_h))
    auto_fixable = violations.count(&:auto_fixable)

    result = {
      file: filepath,
      violations: violations.map(&:to_h),
      score: score,
      auto_fixable: auto_fixable
    }

    @history.record(result.merge(timestamp: Time.now.iso8601))
    @tracker.track("file_analyzed", { file: filepath, violations: violations.length })

    spinner.stop

    Result.ok(result)
  end

  def detect_language(filepath)
    supported = {
      "ruby" => { "extensions" => [".rb"] },
      "python" => { "extensions" => [".py"] },
      "javascript" => { "extensions" => [".js"] }
    }
    Core::LanguageDetector.detect_by_extension(filepath, supported)
  end

  def analyze_project(directory)
    bulk_ops = BulkOperations.new(@config)
    bulk_ops.analyze_directory(directory, self)
  end
end

class CLI
  def self.run(args)
    config_path = "master.yml"
    options = parse_args(args)

    unless File.exist?(config_path)
      puts "#{Dmesg.red('Error:')} #{config_path} not found"
      exit 1
    end

    pipeline = Pipeline.new(config_path)

    case options[:mode]
    when :watch
      watch_mode(pipeline, options[:directory] || ".")
    when :interactive
      interactive_mode(pipeline, options[:files])
    when :bulk
      bulk_analyze(pipeline, options[:directory] || ".")
    when :pr_draft
      generate_pr_draft(pipeline, options)
    when :fix_project
      fix_project(pipeline, options[:directory] || ".")
    else
      analyze_files(pipeline, options[:files], options)
    end
  end

  def self.parse_args(args)
    options = { mode: :normal, files: [], format: "text" }

    args.each_with_index do |arg, idx|
      case arg
      when "--watch"
        options[:mode] = :watch
      when "--interactive"
        options[:mode] = :interactive
      when "--trust"
        options[:trust] = true
      when "--pr-draft"
        options[:mode] = :pr_draft
      when "--fix-project"
        options[:mode] = :fix_project
      when /--format=(.*)/
        options[:format] = $1
      else
        options[:files] << arg unless arg.start_with?("--")
      end
    end

    options
  end

  def self.watch_mode(pipeline, directory)
    watch = WatchMode.new(directory, pipeline)
    watch.start
  end

  def self.interactive_mode(pipeline, files)
    files.each do |file|
      result = pipeline.analyze_file(file)
      next unless result.ok?

      violations = result.value[:violations].map { |v| Violation.new(v) }
      next if violations.empty?

      triage = ViolationTriage.new(violations)
      triage.interactive_triage
    end
  end

  def self.bulk_analyze(pipeline, directory)
    results = pipeline.analyze_project(directory)
    formatter = Formatter.new("text")
    puts formatter.format_results(results)
  end

  def self.generate_pr_draft(pipeline, options)
    results = pipeline.analyze_project(options[:directory] || ".")
    generator = PRDescriptionGenerator.new(pipeline.instance_variable_get(:@config))
    description = generator.generate(results)
    puts description
  end

  def self.fix_project(pipeline, directory)
    bulk_ops = BulkOperations.new(pipeline.instance_variable_get(:@config))
    results = bulk_ops.analyze_directory(directory, pipeline)

    config = pipeline.instance_variable_get(:@config)
    principles = pipeline.instance_variable_get(:@principles)
    auto_fixer = AutoFixer.new(config, principles)

    bulk_ops.fix_all(results[:results], auto_fixer)
  end

  def self.analyze_files(pipeline, files, options)
    formatter = Formatter.new(options[:format])

    files.each do |file|
      result = pipeline.analyze_file(file)

      if result.ok?
        output = formatter.format_results(result.value)
        puts output
        puts "" if files.length > 1
      else
        puts "#{Dmesg.red('Error:')} #{result.error}"
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  CLI.run(ARGV)
end
