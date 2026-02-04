#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: UTF-8

# master.yml LLM OS - LLM-powered code quality analysis
#
# @author master.yml LLM OS
# @version 49.5
# @see https://github.com/constitutional-ai/cli
#
# This file implements the CLI for master.yml LLM OS, a tool that analyzes
# code against 32 coding principles using LLM reasoning. It works in symbiosis
# with master.yml which defines the principles, phases, and configuration.
#
# Architecture: Functional Core, Imperative Shell
# - Core module: Pure functions (no side effects)
# - Shell classes: IO operations and state management
#
# @example Basic usage
#   ruby cli.rb file.rb           # Analyze single file
#   ruby cli.rb src/              # Analyze directory
#   ruby cli.rb --quick .         # Fast scan with 5 core principles
#   ruby cli.rb --watch .         # Watch mode
#
# @example CI/CD usage
#   ruby cli.rb --json --quiet .  # JSON output, exit code only

# Force UTF-8 on all platforms
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "yaml"
require "json"
require "fileutils"
require "time"
require "set"
require "timeout"
require "socket"
require "webrick"

begin
  require "concurrent"
  CONCURRENT_AVAILABLE = true
rescue LoadError
  CONCURRENT_AVAILABLE = false
end

# Auto-install missing gems and configure gem paths
#
# Handles cross-platform gem installation including:
# - OpenBSD with pkg_add dependencies
# - Termux on Android
# - User-install when system gems not writable
#
# @example
#   Bootstrap.run  # Install missing gems and re-exec
module Bootstrap
  # @return [Hash<String, String>] Gem name to package name mapping
  GEMS = {
    "ruby_llm" => "ruby_llm",
    "tty-spinner" => "tty-spinner",
    "tty-prompt" => "tty-prompt",
    "tty-table" => "tty-table",
    "tty-progressbar" => "tty-progressbar",
    "concurrent-ruby" => "concurrent-ruby",
    "falcon" => "falcon"
  }.freeze

  # @return [Hash<String, Array<String>>] OpenBSD packages needed for gems
  OPENBSD_DEPS = {
    "ruby_llm" => [],
    "falcon" => []
  }.freeze

  # Install missing gems and re-execute the script
  # @return [void]
  def self.run
    missing = GEMS.select { |gem_name, _| !gem_installed?(gem_name) }
    return if missing.empty?

    puts "Installing missing gems: #{missing.keys.join(', ')}..."

    install_openbsd_deps(missing.keys) if platform == :openbsd

    missing.each { |_, pkg_name| install_gem(pkg_name) }

    puts "Gems installed. Reloading..."
    exec("ruby", $PROGRAM_NAME, *ARGV)
  end

  # Check if a gem is installed
  # @param name [String] Gem name
  # @return [Boolean]
  def self.gem_installed?(name)
    Gem::Specification.find_by_name(name)
    true
  rescue Gem::MissingSpecError
    false
  end

  # Install a gem, using --user-install if system dir not writable
  # @param name [String] Package name
  # @return [Boolean] Success status
  def self.install_gem(name)
    user_flag = writable_gem_dir? ? "" : "--user-install"
    system("gem install #{name} --no-document #{user_flag}") ||
      warn("Failed to install #{name}")
  end

  # Check if system gem directory is writable
  # @return [Boolean]
  def self.writable_gem_dir?
    File.writable?(Gem.default_dir)
  rescue StandardError
    false
  end

  # Ensure user gem bin directory is in PATH
  # @return [void]
  def self.ensure_gem_path
    return if writable_gem_dir?

    user_bin = File.join(Gem.user_dir, "bin")

    unless ENV["PATH"].to_s.include?(user_bin)
      ENV["PATH"] = "#{user_bin}:#{ENV['PATH']}"
    end

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

  # Install OpenBSD package dependencies for gems
  # @param gem_names [Array<String>] List of gem names
  # @return [void]
  def self.install_openbsd_deps(gem_names)
    deps = gem_names.flat_map { |g| OPENBSD_DEPS[g] || [] }.uniq
    return if deps.empty?

    puts "Installing OpenBSD packages: #{deps.join(' ')}..."
    system("doas pkg_add -I #{deps.join(' ')}")
  end

  # Detect current platform
  # @return [Symbol] One of :openbsd, :termux, :linux, :macos, :windows, :unknown
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

# Optional gems (now should be available after bootstrap)
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

  # Tab completion for commands
  COMMANDS = %w[ls cd pwd cat tree scan fix sprawl clean plan complete session cost trace status help quit exit].freeze
  Readline.completion_proc = proc do |input|
    COMMANDS.grep(/^#{Regexp.escape(input)}/)
  end
rescue LoadError
  READLINE_AVAILABLE = false
end

# Global CLI options (mutable state)
#
# @example
#   Options.quiet = true
#   Options.profile = "quick"
module Options
  @quiet = false
  @json = false
  @git_changed = false
  @watch = false
  @no_cache = false
  @parallel = true
  @profile = nil
  @force = false
  @fix = false
  @dry_run = false

  class << self
    # @!attribute [rw] quiet
    #   @return [Boolean] Minimal output mode
    # @!attribute [rw] json
    #   @return [Boolean] JSON output for CI/CD
    # @!attribute [rw] git_changed
    #   @return [Boolean] Only analyze git-modified files
    # @!attribute [rw] watch
    #   @return [Boolean] Watch mode enabled
    # @!attribute [rw] no_cache
    #   @return [Boolean] Skip cache, always query LLM
    # @!attribute [rw] parallel
    #   @return [Boolean] Enable parallel smell detection
    # @!attribute [rw] profile
    #   @return [String, nil] Active principle profile name
    # @!attribute [rw] force
    #   @return [Boolean] Force dangerous operations
    # @!attribute [rw] fix
    #   @return [Boolean] Enable in-place fixing of violations
    # @!attribute [rw] dry_run
    #   @return [Boolean] Show what would be fixed without changing files
    attr_accessor :quiet, :json, :git_changed, :watch, :no_cache, :parallel, :profile, :force, :fix, :dry_run
  end
end

# =============================================================================
# FUNCTIONAL CORE
# All business logic as pure functions (no side effects, no IO)
# =============================================================================

module Core
  # Constants
  FILE_SCAN_LIMIT = 50
  LARGE_SCAN_LIMIT = 100
  CODE_EXTENSIONS = "*.{rb,py,js,ts}"
  CONFIG_EXTENSIONS = "*.{yml,yaml,json}"
  ALL_EXTENSIONS = "*.{rb,py,js,ts,yml,yaml,json,sh}"

  # Safe UTF-8 file reading - always handles bad encoding
  def self.read_file(path)
    File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  rescue
    ""
  end

  # Read file with binary mode for cleaning
  def self.read_file_binary(path)
    File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace, mode: "rb")
  rescue
    ""
  end

  # Glob files with standard exclusions
  def self.glob_files(root_dir, pattern = CODE_EXTENSIONS, limit: FILE_SCAN_LIMIT)
    Dir.glob(File.join(root_dir, "**", pattern))
       .reject { |f| f.include?("node_modules") || f.include?("vendor") || f.include?(".git") }
       .first(limit)
  end

  # Safe file writing with backup option
  def self.write_file(path, content, backup: false)
    if backup && File.exist?(path)
      FileUtils.cp(path, "#{path}.bak.#{Time.now.to_i}")
    end
    File.write(path, content)
  end

  # Modular skill system for extensible analysis pipelines
  #
  # Skills are loaded from ~/.constitutional/skills/ or ./skills/
  # Each skill has a SKILL.yml manifest and an executable (.rb, .py, .sh)
  #
  # @example SKILL.yml
  #   name: "My Skill"
  #   version: "1.0"
  #   priority: 50
  #   stages: [pre-scan, detection]
  module SkillLoader
    # @return [Array<String>] Directories to search for skills
    SKILLS_DIRS = [
      File.join(Dir.home, ".constitutional", "skills"),
      File.expand_path("skills", __dir__)
    ].freeze

    # @return [Array<String>] Valid pipeline stages
    STAGES = %w[pre-scan detection refactor validate post-process gardening].freeze

    # Discover all available skills from skill directories
    # @return [Array<Hash>] List of skill configurations sorted by priority
    def self.discover
      skills = []

      SKILLS_DIRS.each do |dir|
        next unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*")).each do |skill_path|
          next unless File.directory?(skill_path)

          skill_file = File.join(skill_path, "SKILL.yml")
          next unless File.exist?(skill_file)

          skill = load_skill(skill_file, skill_path)
          skills << skill if skill
        end
      end

      skills.sort_by { |s| s[:priority] || 50 }
    end

    # Load a single skill from its SKILL.yml file
    # @param skill_file [String] Path to SKILL.yml
    # @param skill_path [String] Directory containing the skill
    # @return [Hash, nil] Skill configuration or nil on error
    def self.load_skill(skill_file, skill_path)
      config = YAML.safe_load(File.read(skill_file), permitted_classes: [Symbol])

      {
        name: config["name"],
        description: config["description"],
        version: config["version"],
        priority: config["priority"] || 50,
        stages: config["stages"] || [],
        provides: config["provides"] || [],
        requires: config["requires"] || [],
        config: config["config"] || {},
        path: skill_path,
        executable: find_executable(skill_path)
      }
    rescue StandardError => e
      Log.warn("Failed to load skill from #{skill_file}: #{e.message}")
      nil
    end

    # Find the executable file for a skill
    # @param skill_path [String] Skill directory
    # @return [String, nil] Path to executable or nil
    def self.find_executable(skill_path)
      %w[.rb .py .sh].each do |ext|
        candidates = Dir.glob(File.join(skill_path, "*#{ext}"))
        return candidates.first if candidates.any?
      end
      nil
    end

    # Execute all skills for a given pipeline stage
    # @param stage [String] Pipeline stage name
    # @param context [Hash] Execution context
    # @param skills [Array<Hash>] Available skills
    # @return [Hash] Updated context
    def self.execute_stage(stage, context, skills)
      stage_skills = skills.select { |s| s[:stages].include?(stage) }

      stage_skills.each do |skill|
        next unless skill[:executable]

        Log.info("Running skill: #{skill[:name]} (#{stage})") unless Options.quiet
        execute_skill(skill, context)
      end

      context
    end

    # Execute a single skill
    # @param skill [Hash] Skill configuration
    # @param context [Hash] Execution context
    # @return [void]
    def self.execute_skill(skill, context)
      return unless skill[:executable]

      case File.extname(skill[:executable])
      when ".rb"
        skill_module = Module.new do
          @skill_config = skill
          @context = context

          def self.skill_config = @skill_config
          def self.context = @context
        end

        skill_module.module_eval(File.read(skill[:executable]), skill[:executable], 1)
        skill_module.execute(context) if skill_module.respond_to?(:execute)
      else
        Log.debug("Unsupported skill type: #{skill[:executable]}")
      end
    rescue StandardError => e
      Log.warn("Skill #{skill[:name]} failed: #{e.message}")
    end
  end

  # Registry for principle lookup, filtering, and validation
  #
  # Principles are the core rules that code is analyzed against.
  # Each principle has an id, name, priority, smells, and fix strategies.
  module PrincipleRegistry
    # Load principles from constitution
    # @param constitution [Hash] Raw YAML constitution
    # @return [Hash] Principles hash
    def self.load(constitution)
      constitution["principles"] || {}
    end

    # Find a principle by its numeric ID
    # @param principles [Hash] All principles
    # @param id [Integer] Principle ID
    # @return [Hash, nil] Principle or nil
    def self.find_by_id(principles, id)
      principles.find { |_key, p| p["id"] == id }&.last
    end

    # Find all principles that detect a given smell
    # @param principles [Hash] All principles
    # @param smell [String] Smell name
    # @return [Array<Hash>] Matching principles
    def self.find_by_smell(principles, smell)
      principles.select do |_key, principle|
        smells = principle["smells"] || []
        smells.include?(smell)
      end.values
    end

    # Get all auto-fixable principles
    # @param principles [Hash] All principles
    # @return [Array<Hash>] Auto-fixable principles
    def self.auto_fixable(principles)
      principles.select { |_key, p| p["auto_fixable"] }.values
    end

    # Get maximum priority across all principles
    # @param principles [Hash] All principles
    # @return [Integer] Maximum priority value
    def self.max_priority(principles)
      principles.values.map { |p| p["priority"] || 0 }.max || 0
    end

    # Filter principles by profile
    # @param principles [Hash] All principles
    # @param profile_config [Hash] Profile configuration with 'allow' list
    # @param groups [Hash] Group mappings (e.g., "group:axioms" => [1,2,3])
    # @return [Hash] Filtered principles matching the profile
    def self.filter_by_profile(principles, profile_config, groups)
      return principles if profile_config.nil? || profile_config["allow"]&.include?("*")

      allowed_ids = Set.new
      allow_list = profile_config["allow"] || []

      allow_list.each do |item|
        if item.start_with?("group:")
          group_ids = groups[item] || []
          allowed_ids.merge(group_ids)
        elsif item.is_a?(Integer)
          allowed_ids.add(item)
        end
      end

      principles.select { |_key, p| allowed_ids.include?(p["id"]) }
    end

    # Validate that principles have no circular references
    # @param principles [Hash] All principles
    # @return [Hash] {valid: Boolean, reason: String?}
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

    # Check for circular references in principle conflicts
    # @param principle [Hash] Current principle
    # @param all_principles [Hash] All principles
    # @param visited [Set] Already visited principle IDs
    # @return [Boolean] True if cycle detected
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

  # LLM-based code smell detection
  #
  # Uses progressive disclosure:
  #   Level 1: Compact summary for detection (~50 tokens/principle)
  #   Level 2: Full details for refactoring (~150 tokens/principle)
  #
  # @see build_compact_summary for Level 1
  # @see build_full_details for Level 2
  module LLMDetector
    # Build detection prompt for LLM analysis
    # @param code [String] Source code to analyze
    # @param file_path [String] Path to the file
    # @param principles [Hash] Active principles
    # @param prompt_template [String] Template with {principles} placeholder
    # @return [Hash] {prompt: String, file_path: String}
    def self.detect_violations(code, file_path, principles, prompt_template)
      # Use compact summary for initial detection (60% token savings)
      principle_summary = build_compact_summary(principles)

      prompt = prompt_template.gsub("{principles}", principle_summary)
      prompt += "\n\nCode to analyze:\n```ruby\n#{code}\n```"

      {
        prompt: prompt,
        file_path: file_path
      }
    end

    # Level 1: Compact summary (~50 tokens per principle vs ~150 full)
    # Used for initial detection - just enough for LLM to identify violations
    # @param principles [Hash] All principles
    # @return [String] Compact summary text
    def self.build_compact_summary(principles)
      lines = []

      principles.each do |key, principle|
        id = principle["id"]
        name = principle["name"]
        priority = principle["priority"] || 5
        smells = (principle["smells"] || []).first(5).join(", ")

        lines << "#{id}. #{name} (P#{priority}): #{smells}"
      end

      lines.join("\n")
    end

    # Level 2: Full details - loaded only when violation found
    # Used for refactoring context
    # @param principle [Hash] Single principle
    # @return [String] Full principle details
    def self.build_full_details(principle)
      return "" unless principle

      parts = []
      parts << "Principle: #{principle['name']}"
      parts << "Rule: #{principle['rule']}" if principle["rule"]
      parts << "Why: #{principle['why']}" if principle["why"]
      parts << "Evidence: #{principle['evidence']}" if principle["evidence"]
      parts << "Strategies: #{principle['llm_strategies']&.join(', ')}" if principle["llm_strategies"]

      parts.join("\n")
    end

    # Legacy full summary (for backward compatibility)
    # @param principles [Hash] All principles
    # @return [String] Compact summary (calls build_compact_summary)
    def self.build_principle_summary(principles)
      build_compact_summary(principles)
    end

    # Parse LLM JSON response into violations array
    # @param json_response [String] Raw JSON from LLM
    # @return [Array<Hash>] Parsed violations or empty array on error
    def self.parse_violations(json_response)
      cleaned = json_response.strip
      cleaned = cleaned.gsub(/^```json\n/, "").gsub(/\n```$/, "")
      cleaned = cleaned.gsub(/^```\n/, "").gsub(/\n```$/, "")

      JSON.parse(cleaned)
    rescue JSON::ParserError => error
      []
    end
  end

  # Score calculation based on violations
  #
  # Formula: score = 100 - (violations * 5 * severity_weight)
  # Clamped to [0, 100]
  module ScoreCalculator
    POINTS_PER_VIOLATION = 5
    MAX_SCORE = 100
    MIN_SCORE = 0

    # Calculate score from violation count
    # @param violations [Array<Hash>] Detected violations
    # @return [Integer] Score 0-100
    def self.calculate(violations)
      raw = MAX_SCORE - (violations.size * POINTS_PER_VIOLATION)
      raw < MIN_SCORE ? MIN_SCORE : raw
    end

    # Detailed analysis with severity breakdown
    # @param violations [Array<Hash>] Detected violations
    # @return [Hash] {total:, by_severity:, vetos:, auto_fixable:, score:}
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

  # Token estimation for LLM cost prediction
  #
  # Uses ~4 chars/token for ASCII, ~1 char/token for Unicode
  module TokenEstimator
    # Estimate token count for text
    # @param text [String] Input text
    # @return [Integer] Estimated token count
    def self.estimate(text)
      ascii_chars = text.scan(/[[:ascii:]]/).size
      non_ascii_chars = text.size - ascii_chars

      ((ascii_chars / 4.0) + (non_ascii_chars * 1.0)).ceil
    end

    # Check if text exceeds token threshold
    # @param text [String] Input text
    # @param threshold [Integer] Token threshold
    # @return [Hash] {warning: Boolean, tokens: Integer}
    def self.warn_if_expensive(text, threshold)
      estimated = estimate(text)

      if estimated > threshold
        {warning: true, tokens: estimated}
      else
        {warning: false, tokens: estimated}
      end
    end
  end

  # LLM cost estimation by model tier
  #
  # Rates are per 1M tokens (input/output)
  module CostEstimator
    # Cost rates per 1M tokens by tier
    # Feb 2026 pricing (per 1M tokens)
    RATES = {
      deepseek_v3: { input: 0.14, output: 0.28 },   # DeepSeek V3.2 (cheapest!)
      grok_code: { input: 0.20, output: 1.50 },     # Grok Code Fast 1
      glm: { input: 0.30, output: 0.60 },           # GLM-4.7
      gemini_flash: { input: 0.10, output: 0.40 },  # Gemini 3 Flash Preview
      kimi: { input: 0.50, output: 1.50 },          # Kimi K2.5
      medium: { input: 3.0, output: 15.0 },         # Claude Sonnet 4.5
      strong: { input: 15.0, output: 75.0 },        # Claude Opus 4.5
      grok: { input: 5.0, output: 15.0 },           # Grok 2
      default: { input: 1.0, output: 3.0 }
    }.freeze

    # Estimate cost for an LLM call
    # @param model [String] Model name
    # @param prompt_tokens [Integer] Input tokens
    # @param completion_tokens [Integer] Output tokens
    # @return [Float] Estimated cost in USD
    def self.estimate(model, prompt_tokens, completion_tokens)
      rate = rate_for(model)
      (prompt_tokens * rate[:input] / 1_000_000) + (completion_tokens * rate[:output] / 1_000_000)
    end

    # Get rate for model by pattern matching
    # @param model [String] Model name
    # @return [Hash] {input:, output:} rates per 1M tokens
    def self.rate_for(model)
      case model
      when /grok-code-fast/i then RATES[:grok_code]
      when /deepseek-v3|deepseek\/deepseek-v/i then RATES[:deepseek_v3]
      when /glm/i then RATES[:glm]
      when /kimi/i then RATES[:kimi]
      when /gemini.*flash|gemini-3/i then RATES[:gemini_flash]
      when /claude-sonnet|claude-3\.5/i then RATES[:medium]
      when /claude-opus/i then RATES[:strong]
      when /grok/i then RATES[:grok]
      else RATES[:default]
      end
    end
  end

  # Cross-session cost tracking with JSONL persistence
  #
  # Records all LLM calls to .constitutional_costs.jsonl for:
  # - Daily spending reports
  # - Model breakdown analysis
  # - Budget enforcement
  #
  # @see CostEstimator for cost calculation
  module CostTracker
    COST_FILE = ".constitutional_costs.jsonl"

    # Record an LLM call
    # @param model [String] Model name
    # @param tokens [Integer] Total tokens used
    # @param cost [Float] Cost in USD
    # @param file_path [String, nil] File being analyzed
    def self.record(model, tokens, cost, file_path = nil)
      entry = {
        timestamp: Time.now.iso8601,
        date: Time.now.strftime("%Y-%m-%d"),
        model: model,
        tokens: tokens,
        cost: cost,
        file: file_path
      }

      File.open(COST_FILE, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError => e
      Log.debug("Cost tracking write failed: #{e.message}")
    end

    # Get daily cost totals
    # @param days [Integer] Number of days to look back
    # @return [Hash] {date => {tokens:, cost:, calls:}}
    def self.daily_totals(days = 7)
      entries = load_entries
      cutoff = (Date.today - days).to_s

      by_date = Hash.new { |h, k| h[k] = { tokens: 0, cost: 0.0, calls: 0 } }

      entries.each do |entry|
        date = entry["date"]
        next if date < cutoff

        by_date[date][:tokens] += entry["tokens"] || 0
        by_date[date][:cost] += entry["cost"] || 0
        by_date[date][:calls] += 1
      end

      by_date.sort.to_h
    end

    # Get cost breakdown by model
    # @param days [Integer] Number of days to look back
    # @return [Hash] {model => {tokens:, cost:, calls:}}
    def self.model_breakdown(days = 7)
      entries = load_entries
      cutoff = (Date.today - days).to_s

      by_model = Hash.new { |h, k| h[k] = { tokens: 0, cost: 0.0, calls: 0 } }

      entries.each do |entry|
        next if entry["date"] < cutoff

        model = entry["model"] || "unknown"
        by_model[model][:tokens] += entry["tokens"] || 0
        by_model[model][:cost] += entry["cost"] || 0
        by_model[model][:calls] += 1
      end

      by_model.sort_by { |_, v| -v[:cost] }.to_h
    end

    # Get total spending
    # @param days [Integer, nil] Days to look back (nil = all time)
    # @return [Float] Total cost in USD
    def self.total_spending(days = nil)
      entries = load_entries

      if days
        cutoff = (Date.today - days).to_s
        entries = entries.select { |e| e["date"] >= cutoff }
      end

      {
        tokens: entries.sum { |e| e["tokens"] || 0 },
        cost: entries.sum { |e| e["cost"] || 0 },
        calls: entries.size
      }
    end

    def self.load_entries
      return [] unless File.exist?(COST_FILE)

      File.readlines(COST_FILE).map do |line|
        JSON.parse(line.strip) rescue nil
      end.compact
    rescue StandardError
      []
    end

    def self.clear_old(keep_days = 30)
      entries = load_entries
      cutoff = (Date.today - keep_days).to_s

      kept = entries.select { |e| e["date"] >= cutoff }

      File.open(COST_FILE, "w") do |f|
        kept.each { |e| f.puts(JSON.generate(e)) }
      end

      entries.size - kept.size
    end
  end

  module Cache
    CACHE_DIR = File.join(Dir.home, ".cache", "constitutional")
    CACHE_TTL_SECONDS = 24 * 60 * 60

    def self.init
      FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
    end

    # Semantic key: strip whitespace/comments for cache key
    def self.key_for(file_path, content)
      require "digest"
      # Normalize: remove blank lines, trailing whitespace, standardize line endings
      normalized = content.gsub(/\r\n/, "\n").gsub(/[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip
      ext = File.extname(file_path)
      Digest::SHA256.hexdigest("#{ext}:#{normalized}")[0, 16]
    end

    def self.get(file_path, content)
      init
      key = key_for(file_path, content)
      cache_file = File.join(CACHE_DIR, "#{key}.json")

      if File.exist?(cache_file)
        data = JSON.parse(File.read(cache_file))
        if Time.now.to_i - data["timestamp"] <= CACHE_TTL_SECONDS
          puts "  #{Dmesg.dim}[trace] cache.hit key=#{key}#{Dmesg.reset}" if ENV["TRACE"]
          return data["violations"]
        end
      end

      puts "  #{Dmesg.dim}[trace] cache.miss key=#{key}#{Dmesg.reset}" if ENV["TRACE"]
      nil
    rescue StandardError
      nil
    end

    def self.set(file_path, content, violations)
      init
      key = key_for(file_path, content)
      cache_file = File.join(CACHE_DIR, "#{key}.json")

      puts "  #{Dmesg.dim}[trace] cache.set key=#{key} violations=#{violations.size}#{Dmesg.reset}" if ENV["TRACE"]

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

  # Event hook system for extensibility
  module Hooks
    EVENTS = %i[
      before_scan after_scan
      before_fix after_fix
      violation_found fix_applied fix_rejected
      iteration_start iteration_end
      cost_threshold file_start file_end
      convergence_stuck gardener_run
    ].freeze

    @handlers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    def self.register(event, name: nil, &block)
      raise ArgumentError, "Unknown event: #{event}" unless EVENTS.include?(event)

      @mutex.synchronize do
        @handlers[event] << { block: block, name: name }
      end
    end

    def self.trigger(event, context = {})
      return unless EVENTS.include?(event)

      handlers = @mutex.synchronize { @handlers[event].dup }

      handlers.each do |handler|
        begin
          handler[:block].call(context)
        rescue StandardError => e
          Log.debug("Hook #{handler[:name] || event} failed: #{e.message}")
        end
      end
    end

    def self.clear(event = nil)
      @mutex.synchronize do
        if event
          @handlers[event] = []
        else
          @handlers.clear
        end
      end
    end

    def self.registered
      @mutex.synchronize do
        @handlers.transform_values(&:size)
      end
    end

    # Load hooks from constitution config
    def self.load_from_config(hooks_config)
      return unless hooks_config.is_a?(Hash)

      hooks_config.each do |event_name, actions|
        event = event_name.to_s.sub(/^on_/, "").to_sym
        next unless EVENTS.include?(event)

        actions.each do |action_config|
          register_action(event, action_config)
        end
      end
    end

    def self.register_action(event, config)
      case config["action"]
      when "log"
        register(event, name: "log_#{event}") do |ctx|
          log_entry = { event: event, timestamp: Time.now.iso8601 }.merge(ctx)
          path = config["path"] || ".constitutional_events.jsonl"
          File.open(path, "a") { |f| f.puts(JSON.generate(log_entry)) }
        end
      when "warn"
        register(event, name: "warn_#{event}") do |ctx|
          Log.warn(config["message"] || "Hook: #{event}")
        end
      when "pause"
        register(event, name: "pause_#{event}") do |ctx|
          puts config["message"] || "Paused at #{event}. Press Enter to continue..."
          $stdin.gets
        end
      end
    end
  end

  module ModelCooldown
    @cooldowns = {}
    @mutex = Mutex.new

    DEFAULT_COOLDOWN = 300  # 5 minutes

    def self.in_cooldown?(model)
      @mutex.synchronize do
        return false unless @cooldowns[model]
        if Time.now < @cooldowns[model]
          true
        else
          @cooldowns.delete(model)
          false
        end
      end
    end

    def self.set_cooldown(model, seconds = DEFAULT_COOLDOWN)
      @mutex.synchronize do
        @cooldowns[model] = Time.now + seconds
      end
    end

    def self.time_remaining(model)
      @mutex.synchronize do
        return 0 unless @cooldowns[model]
        remaining = @cooldowns[model] - Time.now
        remaining > 0 ? remaining.ceil : 0
      end
    end

    def self.next_available(models)
      models.find { |m| !in_cooldown?(m) } || models.first
    end

    def self.clear
      @mutex.synchronize { @cooldowns.clear }
    end

    def self.status
      @mutex.synchronize do
        @cooldowns.transform_values { |t| (t - Time.now).ceil }
      end
    end
  end

  module LanguageDetector
    # Extensions that should auto-detect without asking
    AUTO_DETECT = %w[.rb .py .js .ts .jsx .tsx .sh .bash .zsh .yml .yaml .md].freeze

    def self.detect_with_fallback(file_path, code, supported_languages)
      ext = File.extname(file_path).downcase

      # Auto-detect for common extensions
      if AUTO_DETECT.include?(ext)
        lang = detect_by_extension(file_path, supported_languages)
        return lang if lang != "unknown"
      end

      # Check shebang first
      if code.start_with?("#!")
        shebang_lang = detect_by_shebang(code, supported_languages)
        return shebang_lang if shebang_lang != "unknown"
      end

      ext_language = detect_by_extension(file_path, supported_languages)
      return ext_language if ext_language != "unknown"

      detect_by_content(code, supported_languages)
    end

    def self.detect_by_shebang(code, supported_languages)
      first_line = code.lines.first&.strip || ""
      return "unknown" unless first_line.start_with?("#!")

      case first_line
      when /ruby/ then "ruby"
      when /python/ then "python"
      when /node|nodejs/ then "javascript"
      when /zsh/ then "zsh"
      when /bash|sh/ then "shell"
      else "unknown"
      end
    end

    def self.detect_by_extension(file_path, supported_languages)
      ext = File.extname(file_path).downcase

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

    # Detect if shell script has embedded Ruby/Python heredocs
    def self.detect_embedded(code, primary_lang)
      return [] unless %w[shell zsh].include?(primary_lang)

      embedded = []
      # Ruby heredocs: <<-'RUBY' or <<~RUBY or cat <<EOF with ruby code
      embedded << "ruby" if code.match?(/<<[-~]?['"]?(RUBY|ruby|RB)['"]?/) ||
                            code.match?(/ruby\s*<</)
      embedded << "python" if code.match?(/<<[-~]?['"]?(PYTHON|python|PY)['"]?/)
      embedded
    end
  end

  # Project-level analysis for codebase awareness and sprawl reduction
  # Detects fragmented logic, temp files, and consolidation opportunities
  # Implements tree.sh and clean.sh patterns in pure Ruby
  module ProjectAnalyzer
    # Tree scan (equivalent to sh/tree.sh) - pure Ruby glob
    # Returns sorted list: directories first (with /), then files
    def self.tree(root_dir)
      root = root_dir.chomp("/")
      entries = []

      # Directories first
      Dir.glob(File.join(root, "**", "*")).each do |path|
        next if path.include?("/.") || File.basename(path).start_with?(".")
        next if skip_dir?(path)
        entries << "#{path}/" if File.directory?(path)
      end

      # Then files
      Dir.glob(File.join(root, "**", "*")).each do |path|
        next if path.include?("/.") || File.basename(path).start_with?(".")
        next if skip_dir?(path)
        entries << path if File.file?(path)
      end

      entries.sort
    end

    def self.skip_dir?(path)
      %w[node_modules vendor .git __pycache__ .bundle tmp cache].any? { |d| path.include?("/#{d}/") || path.end_with?("/#{d}") }
    end

    # Clean files (equivalent to sh/clean.sh) - before editing
    # Removes: CRLF, trailing whitespace, consecutive blank lines
    def self.clean(root_dir, dry_run: false)
      cleaned = []
      tree(root_dir).each do |path|
        next if path.end_with?("/") # skip directories
        next unless text_file?(path)

        result = clean_file(path, dry_run: dry_run)
        cleaned << result if result[:changed]
      end
      cleaned
    end

    def self.text_file?(path)
      # Check by extension
      text_exts = %w[.rb .py .js .ts .sh .zsh .yml .yaml .json .md .txt .html .css .erb .haml .slim .rake .gemspec .conf]
      return true if text_exts.include?(File.extname(path).downcase)

      # Check first bytes for binary
      begin
        bytes = File.binread(path, 512)
        return false if bytes.include?("\x00") # binary file
        true
      rescue
        false
      end
    end

    def self.clean_file(path, dry_run: false)
      original = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace, mode: "rb")
      cleaned = original.dup

      # Remove CRLF → LF
      cleaned.gsub!("\r\n", "\n")
      cleaned.gsub!("\r", "")

      # Trim trailing whitespace from each line
      lines = cleaned.split("\n", -1)
      lines = lines.map { |line| line.rstrip }

      # Reduce consecutive blank lines to single
      result = []
      prev_blank = false
      lines.each do |line|
        if line.empty?
          unless prev_blank
            result << line
            prev_blank = true
          end
        else
          result << line
          prev_blank = false
        end
      end

      # Ensure single trailing newline
      cleaned = result.join("\n").rstrip + "\n"

      changed = cleaned != original

      if changed && !dry_run
        File.write(path, cleaned)
        Log.info("Cleaned: #{path}")
      end

      { path: path, changed: changed, original_size: original.bytesize, cleaned_size: cleaned.bytesize }
    end

    # Pre-scan phase: tree only (no cleaning without explicit permission)
    def self.prescan(root_dir, dry_run: true)
      Log.info("Pre-scanning: #{root_dir}")

      files = tree(root_dir)
      Log.info("Found #{files.count { |f| !f.end_with?('/') }} files in #{files.count { |f| f.end_with?('/') }} directories")

      # Never auto-clean - bodyguard asks first
      { files: files, cleaned_count: 0 }
    end

    # Analyze entire project structure for sprawl and fragmentation
    def self.analyze(root_dir, config = {})
      files = collect_files(root_dir)
      {
        root: root_dir,
        file_count: files.size,
        sprawl: detect_sprawl(files, config),
        duplicates: find_duplicates(files),
        fragmentation: detect_fragmentation(files, config),
        consolidation_opportunities: suggest_consolidations(files, config)
      }
    end

    def self.collect_files(root_dir)
      patterns = %w[**/*.rb **/*.py **/*.js **/*.ts **/*.sh **/*.yml **/*.yaml]
      files = []
      patterns.each do |pattern|
        Dir.glob(File.join(root_dir, pattern)).each do |f|
          next if f.include?("node_modules") || f.include?("vendor") || f.include?(".git")
          line_count = begin
            File.read(f, encoding: "UTF-8", invalid: :replace, undef: :replace).lines.size
          rescue
            0
          end
          files << { path: f, size: File.size(f), lines: line_count }
        end
      end
      files
    end

    # Detect file sprawl: too many small files, temp files, scattered logic
    def self.detect_sprawl(files, config)
      sprawl = []

      # Temp files that should be cleaned up
      temp_patterns = config.dig("sprawl", "temp_patterns") || %w[.tmp .bak .swp ~$ .orig .cache]
      temp_files = files.select { |f| temp_patterns.any? { |p| f[:path].include?(p) } }
      sprawl << { type: :temp_files, files: temp_files.map { |f| f[:path] }, count: temp_files.size } if temp_files.any?

      # Very small files (< 20 lines) that might consolidate
      tiny_threshold = config.dig("sprawl", "tiny_threshold") || 20
      tiny_files = files.select { |f| f[:lines] > 0 && f[:lines] < tiny_threshold }
      if tiny_files.size > 5
        sprawl << { type: :tiny_files, files: tiny_files.map { |f| f[:path] }, count: tiny_files.size,
                    message: "#{tiny_files.size} tiny files (<#{tiny_threshold} lines) - consider consolidating" }
      end

      # Too many files in one directory (horizontal sprawl)
      dir_counts = files.group_by { |f| File.dirname(f[:path]) }
      crowded_dirs = dir_counts.select { |_, v| v.size > 15 }
      crowded_dirs.each do |dir, dir_files|
        sprawl << { type: :crowded_dir, path: dir, count: dir_files.size,
                    message: "#{dir_files.size} files in #{dir} - consider subdirectories" }
      end

      # Deep nesting (vertical sprawl)
      deep_files = files.select { |f| f[:path].split(File::SEPARATOR).size > 8 }
      if deep_files.any?
        sprawl << { type: :deep_nesting, files: deep_files.map { |f| f[:path] }, count: deep_files.size,
                    message: "#{deep_files.size} deeply nested files (>8 levels)" }
      end

      sprawl
    end

    # Find duplicate or near-duplicate code
    def self.find_duplicates(files)
      duplicates = []

      # Hash first 500 chars of each file to find exact duplicates
      hashes = {}
      files.each do |f|
        next if f[:size] < 100
        content = File.read(f[:path], encoding: "UTF-8", invalid: :replace, undef: :replace)[0, 500] rescue next
        hash = content.hash
        if hashes[hash]
          duplicates << { original: hashes[hash], duplicate: f[:path] }
        else
          hashes[hash] = f[:path]
        end
      end

      duplicates
    end

    # Detect fragmented logic across files
    def self.detect_fragmentation(files, config)
      fragmentation = []

      # Group by semantic purpose (helpers, utils, lib, services, etc.)
      semantic_groups = {}
      files.each do |f|
        basename = File.basename(f[:path], ".*")
        # Detect common patterns
        group = case basename
                when /helper|util|common|shared/ then :utilities
                when /service|client|api/ then :services
                when /model|entity|record/ then :models
                when /controller|handler|action/ then :controllers
                when /view|template|partial/ then :views
                when /test|spec|_test$/ then :tests
                when /config|setting/ then :config
                else :other
                end
        (semantic_groups[group] ||= []) << f[:path]
      end

      # Flag scattered utilities (same semantic type in different directories)
      semantic_groups.each do |group, group_files|
        next if group == :other || group_files.size < 2
        dirs = group_files.map { |f| File.dirname(f) }.uniq
        if dirs.size > 2
          fragmentation << {
            type: :scattered_semantic_group,
            group: group,
            directories: dirs,
            files: group_files,
            message: "#{group} logic scattered across #{dirs.size} directories"
          }
        end
      end

      fragmentation
    end

    # Suggest consolidation opportunities
    def self.suggest_consolidations(files, config)
      suggestions = []

      # Multiple helper files → single helpers.rb
      helper_files = files.select { |f| f[:path] =~ /helper/ }
      if helper_files.size > 3
        suggestions << {
          action: :merge,
          files: helper_files.map { |f| f[:path] },
          target: "lib/helpers.rb",
          reason: "Consolidate #{helper_files.size} helper files"
        }
      end

      # Multiple config files → single config dir
      config_files = files.select { |f| f[:path] =~ /config|settings/ && f[:path] !~ /^config\// }
      if config_files.size > 2
        suggestions << {
          action: :move,
          files: config_files.map { |f| f[:path] },
          target: "config/",
          reason: "Move #{config_files.size} config files to config/"
        }
      end

      suggestions
    end

    # Apply consolidation (with user confirmation)
    def self.apply_consolidation(suggestion, dry_run: false)
      case suggestion[:action]
      when :merge
        return { status: :dry_run, message: "Would merge #{suggestion[:files].size} files into #{suggestion[:target]}" } if dry_run
        merge_files(suggestion[:files], suggestion[:target])
      when :move
        return { status: :dry_run, message: "Would move #{suggestion[:files].size} files to #{suggestion[:target]}" } if dry_run
        move_files(suggestion[:files], suggestion[:target])
      when :delete
        return { status: :dry_run, message: "Would delete #{suggestion[:files].size} files" } if dry_run
        delete_files(suggestion[:files])
      end
    end

    def self.merge_files(sources, target)
      combined = sources.map do |f|
        "# From: #{f}\n" + File.read(f, encoding: "UTF-8", invalid: :replace, undef: :replace)
      end.join("\n\n")

      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, combined)
      sources.each { |f| FileUtils.mv(f, "#{f}.merged.bak") }
      { status: :merged, target: target, sources: sources }
    end

    def self.move_files(sources, target_dir)
      FileUtils.mkdir_p(target_dir)
      sources.each { |f| FileUtils.mv(f, File.join(target_dir, File.basename(f))) }
      { status: :moved, target: target_dir, count: sources.size }
    end

    def self.delete_files(files)
      files.each { |f| FileUtils.rm(f) }
      { status: :deleted, count: files.size }
    end
  end

  # Structural analysis for any codebase (merge, decouple, hierarchy)
  # Uses questions from master.yml structural_analysis section
  module StructuralAnalyzer
    def self.analyze(root_dir, constitution)
      questions = constitution.data["structural_analysis"] || {}
      issues = []

      # Analyze YAML/config files
      config_files = Dir.glob(File.join(root_dir, "**", "*.{yml,yaml,json}"))
      config_files.each do |f|
        issues.concat(analyze_config(f, questions["config_hierarchy"] || []))
        issues.concat(check_merge_opportunities(f, questions["merge_opportunities"] || []))
      end

      # Analyze code files
      code_files = Dir.glob(File.join(root_dir, "**", "*.{rb,py,js,ts}"))
      code_files.each do |f|
        issues.concat(analyze_code_structure(f, questions["code_hierarchy"] || []))
      end

      # Project-wide checks
      issues.concat(check_semantic_clarity(root_dir, questions["semantic_clarity"] || []))
      issues.concat(check_decouple_opportunities(root_dir, questions["decouple_opportunities"] || []))

      issues
    end

    def self.analyze_config(file_path, questions)
      issues = []
      return issues unless File.exist?(file_path)

      begin
        content = YAML.safe_load(File.read(file_path, encoding: "UTF-8")) rescue {}
        return issues unless content.is_a?(Hash)

        keys = content.keys

        # Check: too many top-level keys
        if keys.size > 15
          issues << { file: file_path, type: :sprawl, message: "#{keys.size} top-level keys - consider grouping" }
        end

        # Check: mixed scalar and complex types at top level
        scalars = keys.select { |k| !content[k].is_a?(Hash) && !content[k].is_a?(Array) }
        complex = keys.select { |k| content[k].is_a?(Hash) || content[k].is_a?(Array) }
        if scalars.any? && complex.any? && scalars.size > 2
          issues << { file: file_path, type: :hierarchy, message: "Mixed scalars (#{scalars[0..2].join(', ')}) with complex sections" }
        end

        # Check: duplicate-looking keys
        keys.combination(2).each do |a, b|
          if similar_keys?(a, b)
            issues << { file: file_path, type: :merge, message: "Possibly overlapping: #{a} and #{b}" }
          end
        end
      rescue => e
        # Skip unparseable files
      end

      issues
    end

    def self.similar_keys?(a, b)
      a_words = a.to_s.split(/[_-]/)
      b_words = b.to_s.split(/[_-]/)
      (a_words & b_words).size >= 1 && a != b
    end

    def self.analyze_code_structure(file_path, questions)
      issues = []
      return issues unless File.exist?(file_path)

      content = File.read(file_path, encoding: "UTF-8") rescue ""
      lines = content.lines

      # Top-level modules/classes sprawl
      top_level = content.scan(/^(module|class)\s+(\w+)/).map(&:last)
      if top_level.size > 10
        issues << { file: file_path, type: :sprawl, smell: :god_file, message: "#{top_level.size} top-level modules/classes" }
      end

      # Scattered utilities
      util_patterns = %w[Log Logger Util Utils Helper Helpers]
      scattered = top_level.select { |t| util_patterns.any? { |p| t.include?(p) } }
      if scattered.size > 1
        issues << { file: file_path, type: :fragmentation, smell: :scattered_functionality, message: "Scattered utilities: #{scattered.join(', ')}" }
      end

      # Long methods (> 20 lines)
      method_lengths = detect_method_lengths(content)
      method_lengths.each do |name, length|
        if length > 20
          issues << { file: file_path, type: :bloater, smell: :long_method, message: "#{name}: #{length} lines" }
        end
      end

      # Long parameter lists (> 4 params)
      content.scan(/def\s+(\w+)\(([^)]+)\)/).each do |name, params|
        param_count = params.split(",").size
        if param_count > 4
          issues << { file: file_path, type: :bloater, smell: :long_parameter_list, message: "#{name}: #{param_count} params" }
        end
      end

      # Message chains (a.b.c.d pattern)
      content.scan(/\w+(?:\.\w+){3,}/).each do |chain|
        issues << { file: file_path, type: :coupler, smell: :message_chains, message: chain[0..50] }
      end

      issues
    end

    def self.detect_method_lengths(content)
      methods = {}
      current_method = nil
      depth = 0
      start_line = 0

      content.lines.each_with_index do |line, idx|
        if line =~ /^\s*def\s+(\w+)/
          current_method = $1
          start_line = idx
          depth = 1
        elsif current_method
          depth += 1 if line =~ /\b(do|if|unless|case|while|until|for|begin|class|module|def)\b/
          depth -= 1 if line =~ /\bend\b/
          if depth <= 0
            methods[current_method] = idx - start_line
            current_method = nil
          end
        end
      end
      methods
    end

    def self.check_merge_opportunities(file_path, questions)
      []
    end

    def self.check_semantic_clarity(root_dir, questions)
      issues = []

      Dir.glob(File.join(root_dir, "**/")).each do |dir|
        files = Dir.glob(File.join(dir, "*")).select { |f| File.file?(f) }
        if files.size > 20
          issues << { file: dir, type: :sprawl, smell: :crowded_dir, message: "#{files.size} files in directory" }
        end
      end

      issues
    end

    def self.check_decouple_opportunities(root_dir, questions)
      issues = []

      # Hardcoded paths
      Dir.glob(File.join(root_dir, "**", "*.{rb,py,yml,yaml}")).first(50).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
        if content.match?(/[A-Z]:\\|\/home\/\w+|\/Users\/\w+/)
          issues << { file: f, type: :decouple, smell: :hardcoded_path, message: "Hardcoded path - use env var" }
        end
      end

      issues
    end

    # Detect dead code (unused methods, unreferenced classes)
    def self.detect_dead_code(root_dir)
      issues = []
      definitions = {}
      references = Hash.new(0)

      Dir.glob(File.join(root_dir, "**", "*.rb")).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""

        # Collect definitions
        content.scan(/def\s+(\w+)/).each { |m| definitions[m[0]] = f }
        content.scan(/class\s+(\w+)/).each { |m| definitions[m[0]] = f }
        content.scan(/module\s+(\w+)/).each { |m| definitions[m[0]] = f }

        # Collect references
        content.scan(/\b([A-Z]\w+)\b/).each { |m| references[m[0]] += 1 }
        content.scan(/\.(\w+)/).each { |m| references[m[0]] += 1 }
      end

      # Find unreferenced (potential dead code)
      definitions.each do |name, file|
        next if %w[initialize new call].include?(name)
        if references[name] <= 1
          issues << { file: file, type: :dispensable, smell: :dead_code, message: "#{name} may be unused" }
        end
      end

      issues.first(20)  # Limit noise
    end

    # Detect cyclic dependencies between files
    def self.detect_cyclic_dependencies(root_dir)
      issues = []
      deps = {}

      Dir.glob(File.join(root_dir, "**", "*.rb")).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
        basename = File.basename(f, ".rb")
        deps[basename] = []

        content.scan(/require[_relative]*\s+['"]([^'"]+)['"]/).each do |req|
          deps[basename] << File.basename(req[0], ".rb")
        end
      end

      # Simple cycle detection (A requires B, B requires A)
      deps.each do |file, requires|
        requires.each do |req|
          if deps[req]&.include?(file)
            issues << { file: file, type: :architecture, smell: :cyclic_dependency, message: "#{file} ↔ #{req}" }
          end
        end
      end

      issues.uniq { |i| [i[:file], i[:message]].sort.join }
    end

    def self.report(issues)
      return if issues.empty?

      grouped = issues.group_by { |i| i[:type] }
      grouped.each do |type, items|
        Log.warn("#{type.to_s.upcase}: #{items.size} issues")
        items.first(5).each { |i| Log.info("  #{i[:file]}: #{i[:message]}") }
      end
    end

    # Cross-reference analysis: find naming/type inconsistencies
    def self.cross_reference(root_dir)
      issues = []
      terms = Hash.new { |h, k| h[k] = [] }
      types = Hash.new { |h, k| h[k] = [] }

      Dir.glob(File.join(root_dir, "**", "*.{rb,py,js,ts,yml,yaml}")).first(100).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""

        # Collect variable/method names and their apparent types
        content.scan(/(\w+)\s*=\s*(\[|{|"|'|\d|true|false|nil|null)/).each do |name, type_hint|
          type = case type_hint
                 when "[" then :array
                 when "{" then :hash
                 when '"', "'" then :string
                 when /\d/ then :number
                 when "true", "false" then :boolean
                 else :nil
                 end
          types[name] << { file: f, type: type }
        end

        # Collect similar terms (potential naming inconsistency)
        content.scan(/\b(user|account|member|config|settings|options|data|info|params|args)\b/i).each do |term|
          terms[term[0].downcase] << f
        end
      end

      # Find same name with different types
      types.each do |name, occurrences|
        type_set = occurrences.map { |o| o[:type] }.uniq
        if type_set.size > 1
          issues << { type: :cross_ref, smell: :type_inconsistency,
                      message: "#{name} has types: #{type_set.join(', ')}" }
        end
      end

      # Find synonym usage (naming inconsistency)
      synonyms = [%w[user account member], %w[config settings options], %w[data info]]
      synonyms.each do |group|
        found = group.select { |t| terms[t].any? }
        if found.size > 1
          issues << { type: :cross_ref, smell: :naming_inconsistency,
                      message: "Mixed terms: #{found.join(', ')}" }
        end
      end

      issues
    end

    # Simulated execution: check edge case handling
    def self.simulate_edge_cases(root_dir)
      issues = []

      Dir.glob(File.join(root_dir, "**", "*.rb")).first(50).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""

        # Check nil handling
        if content.match?(/\.(\w+)/) && !content.match?(/&\.|\.nil\?|rescue|if .+\.nil/)
          method_calls = content.scan(/(\w+)\.(\w+)/).size
          nil_checks = content.scan(/&\.|\.nil\?|unless.*nil|if.*nil/).size
          if method_calls > 10 && nil_checks < method_calls / 5
            issues << { file: f, type: :simulation, smell: :missing_nil_checks,
                        message: "#{method_calls} method calls, only #{nil_checks} nil checks" }
          end
        end

        # Check empty collection handling
        if content.match?(/\.each|\.map|\.select/) && !content.match?(/\.empty\?|\.any\?|\.size\s*[>=<]/)
          issues << { file: f, type: :simulation, smell: :no_empty_check,
                      message: "Iterates without checking empty" }
        end

        # Check file operations without rescue
        if content.match?(/File\.(read|write|open|delete)/) && !content.match?(/rescue|begin.*File/)
          issues << { file: f, type: :simulation, smell: :unhandled_io,
                      message: "File operations without error handling" }
        end

        # Check for string interpolation in user input (injection risk)
        if content.match?(/`.*#\{|system.*#\{|exec.*#\{|%x.*#\{/)
          issues << { file: f, type: :simulation, smell: :injection_risk,
                      message: "String interpolation in shell command" }
        end
      end

      issues
    end

    # Micro-refinement detection
    def self.detect_micro_refinements(root_dir)
      issues = []

      Core.glob_files(root_dir, Core::CODE_EXTENSIONS).each do |f|
        content = Core.read_file(f)
        next if content.empty?
        lines = content.lines

        # Long methods (>25 lines)
        method_lines = 0
        method_start = nil
        lines.each_with_index do |line, i|
          if line.match?(/^\s*(def |function |async function |const \w+ = )/)
            method_start = i + 1
            method_lines = 0
          elsif line.match?(/^\s*end\s*$/) || (method_start && line.match?(/^}\s*$/))
            if method_lines > 25
              issues << { file: f, type: :refinement, check: :long_method,
                          message: "Method at line #{method_start}: #{method_lines} lines" }
            end
            method_start = nil
          elsif method_start
            method_lines += 1
          end
        end

        # Magic numbers
        content.scan(/[^a-zA-Z_](\d{2,})[^a-zA-Z_\d]/).each do |match|
          num = match[0].to_i
          next if [10, 60, 100, 1000, 1024].include?(num) # common acceptable values
          issues << { file: f, type: :refinement, check: :magic_number,
                      message: "Magic number: #{num}" } if issues.count { |i| i[:check] == :magic_number } < 5
        end

        # Bare rescue
        if content.match?(/rescue\s*($|#)/) || content.match?(/rescue\s+=>/)
          issues << { file: f, type: :refinement, check: :bare_rescue,
                      message: "Bare rescue without exception type" }
        end

        # Hardcoded paths
        content.scan(%r{["'](/(?:usr|etc|home|var|tmp)/[^"']+)["']}).each do |match|
          issues << { file: f, type: :refinement, check: :hardcoded_path,
                      message: "Hardcoded path: #{match[0][0..40]}" } if issues.count { |i| i[:check] == :hardcoded_path } < 3
        end

        # Duplicate code patterns (simple: same 3+ line block)
        line_hashes = {}
        lines.each_cons(3).with_index do |block, i|
          hash = block.map(&:strip).join.hash
          if line_hashes[hash]
            issues << { file: f, type: :refinement, check: :duplicate_pattern,
                        message: "Lines #{line_hashes[hash]+1} and #{i+1} are similar" }
            break # only report first duplicate
          end
          line_hashes[hash] = i
        end

        # Inconsistent naming (mixed camelCase and snake_case)
        camel = content.scan(/\b[a-z]+[A-Z][a-zA-Z]+\b/).uniq
        snake = content.scan(/\b[a-z]+_[a-z]+\b/).uniq
        if camel.size > 3 && snake.size > 3
          issues << { file: f, type: :refinement, check: :inconsistent_naming,
                      message: "Mixed naming: #{camel.size} camelCase, #{snake.size} snake_case" }
        end
      end

      issues.first(30)
    end

    # Cross-file DRY violation detection
    def self.detect_cross_file_dry(root_dir)
      issues = []
      files = Core.glob_files(root_dir, Core::CODE_EXTENSIONS, limit: Core::LARGE_SCAN_LIMIT)

      # Collect patterns across all files
      call_patterns = Hash.new { |h, k| h[k] = [] }
      block_hashes = Hash.new { |h, k| h[k] = [] }
      constants_used = Hash.new { |h, k| h[k] = [] }

      files.each do |f|
        content = Core.read_file(f)
        next if content.empty?
        lines = content.lines

        # Track function call patterns (method calls with specific args)
        content.scan(/(File\.(?:read|write|open)\([^)]{20,}\))/).each do |match|
          call_patterns[match[0].gsub(/["'][^"']+["']/, '...')] << f
        end
        content.scan(/(Dir\.glob\([^)]+\))/).each do |match|
          call_patterns[match[0].gsub(/["'][^"']+["']/, '...')] << f
        end

        # Track 5-line blocks
        lines.each_cons(5).with_index do |block, i|
          normalized = block.map { |l| l.strip.gsub(/\s+/, ' ') }.join("\n")
          next if normalized.length < 50
          block_hashes[normalized.hash] << { file: f, line: i + 1 }
        end

        # Track magic numbers
        content.scan(/\b(\d{2,4})\b/).each do |match|
          num = match[0]
          next if %w[10 100 1000 1024 2048 4096].include?(num)
          constants_used[num] << f
        end
      end

      # Report duplicate call patterns
      call_patterns.each do |pattern, occurrences|
        if occurrences.uniq.size >= 3
          issues << { type: :cross_file_dry, check: :duplicate_function_calls,
                      message: "#{pattern[0..50]}... in #{occurrences.uniq.size} files",
                      files: occurrences.uniq.first(3) }
        end
      end

      # Report duplicate blocks
      block_hashes.each do |hash, occurrences|
        if occurrences.size >= 2 && occurrences.map { |o| o[:file] }.uniq.size >= 2
          issues << { type: :cross_file_dry, check: :copy_paste_blocks,
                      message: "5-line block duplicated",
                      files: occurrences.map { |o| "#{o[:file]}:#{o[:line]}" }.first(3) }
        end
      end

      # Report magic numbers spread across files
      constants_used.each do |num, occurrences|
        if occurrences.uniq.size >= 3
          issues << { type: :cross_file_dry, check: :magic_number_spread,
                      message: "Magic number #{num} in #{occurrences.uniq.size} files",
                      files: occurrences.uniq.first(3) }
        end
      end

      issues.first(20)
    end

    # Full analysis including cross-file DRY
    def self.full_analysis(root_dir, constitution)
      all_issues = []
      all_issues.concat(analyze(root_dir, constitution))
      all_issues.concat(detect_dead_code(root_dir))
      all_issues.concat(detect_cyclic_dependencies(root_dir))
      all_issues.concat(cross_reference(root_dir))
      all_issues.concat(simulate_edge_cases(root_dir))
      all_issues.concat(detect_micro_refinements(root_dir))
      all_issues.concat(detect_cross_file_dry(root_dir))
      all_issues
    end
  end

  # OpenBSD config file extraction and man page lookup
  # Reads config mappings from master.yml openbsd section
  module OpenBSDConfig
    CACHE_DIR = File.join(Dir.home, ".constitutional", "man_cache")

    # Extract all embedded configs from a shell script
    def self.extract_configs(code, config_map)
      configs = []
      return configs unless config_map

      # Match: cat > /path/to/file <<EOF ... EOF
      code.scan(/cat\s*>\s*([^\s<]+)\s*<<[-~]?['"]?(\w+)['"]?\n(.*?)\n\2/m) do |path, marker, content|
        config_name = File.basename(path)
        if config_map[config_name]
          cfg = config_map[config_name]
          configs << {
            path: path,
            name: config_name,
            content: content,
            daemon: cfg["daemon"],
            man_page: cfg["man"]
          }
        end
      end

      # Match: cat >> /path/to/file <<EOF (append)
      code.scan(/cat\s*>>\s*([^\s<]+)\s*<<[-~]?['"]?(\w+)['"]?\n(.*?)\n\2/m) do |path, marker, content|
        config_name = File.basename(path)
        if config_map[config_name]
          cfg = config_map[config_name]
          configs << {
            path: path,
            name: config_name,
            content: content,
            daemon: cfg["daemon"],
            man_page: cfg["man"],
            append: true
          }
        end
      end

      configs
    end

    # Fetch man page from man.openbsd.org
    def self.fetch_man_page(man_page, base_url, cache_ttl = 86400)
      FileUtils.mkdir_p(CACHE_DIR)
      cache_file = File.join(CACHE_DIR, "#{man_page}.txt")

      # Return cached if fresh
      if File.exist?(cache_file)
        age = Time.now - File.mtime(cache_file)
        return File.read(cache_file) if age < cache_ttl
      end

      url = "#{base_url}/#{man_page}"

      begin
        require "net/http"
        require "uri"

        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          # Strip HTML, keep text
          content = response.body
            .gsub(/<script[^>]*>.*?<\/script>/mi, "")
            .gsub(/<style[^>]*>.*?<\/style>/mi, "")
            .gsub(/<[^>]+>/, " ")
            .gsub(/&nbsp;/, " ")
            .gsub(/&lt;/, "<")
            .gsub(/&gt;/, ">")
            .gsub(/&amp;/, "&")
            .gsub(/\s+/, " ")
            .strip

          File.write(cache_file, content)
          content
        else
          nil
        end
      rescue StandardError => e
        Log.warn("Failed to fetch #{url}: #{e.message}") if defined?(Log)
        nil
      end
    end

    # Validate config against rules from master.yml
    def self.validate_config(config_name, content, config_rules)
      return { valid: true, warnings: [] } unless config_rules

      rules = config_rules[config_name]
      return { valid: true, warnings: [] } unless rules

      warnings = []

      # Check required patterns
      (rules["required_patterns"] || []).each do |pattern|
        unless content.include?(pattern)
          warnings << "Missing required: '#{pattern}'"
        end
      end

      # Check warning patterns
      (rules["warnings"] || []).each do |w|
        if w["pattern"]
          if w["absent_message"] && !content.include?(w["pattern"])
            warnings << w["absent_message"]
          elsif w["message"] && content.include?(w["pattern"])
            warnings << w["message"]
          end
        end
      end

      # Check forbidden patterns
      (rules["forbidden_patterns"] || []).each do |pattern|
        if content.include?(pattern)
          warnings << "Forbidden pattern found: '#{pattern}'"
        end
      end

      { valid: warnings.empty?, warnings: warnings }
    end

    # Fix a config in-place within the source shell script
    # Returns the modified source code with the heredoc content replaced
    def self.fix_config_in_source(source_code, config_path, old_content, new_content)
      # Escape special regex characters in the content
      escaped_old = Regexp.escape(old_content)

      # Match the heredoc pattern with this specific content
      # cat > /path/to/file <<EOF\n...\nEOF
      pattern = /(cat\s*>+\s*#{Regexp.escape(config_path)}\s*<<[-~]?['"]?(\w+)['"]?\n)#{escaped_old}(\n\2)/m

      if source_code.match?(pattern)
        source_code.gsub(pattern, "\\1#{new_content}\\3")
      else
        source_code  # Return unchanged if pattern not found
      end
    end

    # Apply all fixes to source file
    def self.apply_fixes_to_source(file_path, fixes)
      return if fixes.empty?

      source = File.read(file_path, encoding: "UTF-8")
      modified = source.dup

      fixes.each do |fix|
        modified = fix_config_in_source(
          modified,
          fix[:path],
          fix[:old_content],
          fix[:new_content]
        )
      end

      if modified != source
        File.write(file_path, modified)
        true
      else
        false
      end
    end

    # Get config summary for LLM context (in memory, not extracted to disk)
    def self.config_context(configs, base_url, cache_ttl)
      context = []

      configs.each do |cfg|
        man_content = fetch_man_page(cfg[:man_page], base_url, cache_ttl)
        summary = man_content ? man_content[0..2000] : "Man page unavailable"

        context << {
          config: cfg[:name],
          daemon: cfg[:daemon],
          path: cfg[:path],
          man_url: "#{base_url}/#{cfg[:man_page]}",
          man_summary: summary,
          content_preview: cfg[:content][0..500],
          full_content: cfg[:content]  # Keep full content in memory for fixes
        }
      end

      context
    end

    # Generate fix using LLM with man page context
    def self.generate_fix(config, warnings, man_summary, llm)
      return nil unless llm&.enabled?

      prompt = <<~PROMPT
        You are an OpenBSD system administrator expert.

        Config file: #{config[:name]} (for #{config[:daemon]} daemon)
        Man page: #{config[:man_url]}

        Current config content:
        ```
        #{config[:content]}
        ```

        Issues found:
        #{warnings.map { |w| "- #{w}" }.join("\n")}

        Man page reference (excerpt):
        #{man_summary[0..1500]}

        Fix the config to resolve the issues. Return ONLY the fixed config content, no explanation.
        Keep the same format and structure, just fix the issues.
      PROMPT

      begin
        response = llm.ask_tier("code", [{ role: "user", content: prompt }])
        response.to_s.strip.gsub(/^```\w*\n?/, "").gsub(/\n?```$/, "")
      rescue StandardError => e
        Log.warn("LLM fix generation failed: #{e.message}") if defined?(Log)
        nil
      end
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

  # Pure Ruby equivalent of tree.sh - list dirs then files
  module TreeWalk
    def self.print_tree(dir = ".")
      dir = dir.chomp("/")
      entries = []

      # Directories first (with trailing slash)
      Dir.glob(File.join(dir, "**", "*")).each do |path|
        next if File.basename(path).start_with?(".")

        if File.directory?(path)
          entries << "#{path}/"
        end
      end

      # Files second
      Dir.glob(File.join(dir, "**", "*")).each do |path|
        next if File.basename(path).start_with?(".")
        next unless File.file?(path)

        entries << path
      end

      entries
    end

    def self.display(dir = ".")
      print_tree(dir).each { |e| puts e }
    end
  end

  # Pure Ruby equivalent of clean.sh - normalize text files
  # Delegates to ProjectAnalyzer.clean_file for DRY
  module FileCleaner
    def self.clean(file_path)
      return false unless File.file?(file_path)
      result = ProjectAnalyzer.clean_file(file_path, dry_run: false)
      result[:changed]
    end

    def self.text_file?(path)
      ProjectAnalyzer.text_file?(path)
    end

    def self.clean_dir(dir)
      ProjectAnalyzer.clean(dir, dry_run: false).size
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# REPLICATE MODULE: Generative AI Model Orchestration
# ═══════════════════════════════════════════════════════════════════════════════
module Replicate
  API_BASE = "https://api.replicate.com/v1"
  MODEL_DB = File.join(Dir.home, ".constitutional", "replicate_models.db")

  # Default models by category (from replicate.com/explore 2026)
  MODELS = {
    # Image generation
    img: "google/nano-banana-pro",           # 11.7M runs, state of art
    img_fast: "black-forest-labs/flux-2-klein-4b", # sub-second
    img_edit: "bytedance/seedream-4.5",      # 2.6M runs
    img_openai: "openai/gpt-image-1.5",      # best prompt adherence
    
    # Video generation  
    vid: "google/veo-3.1-fast",              # 354K runs, audio included
    vid_pro: "kwaivgi/kling-v2.6",           # 92K runs, cinematic
    vid_physics: "pixverse/pixverse-v5.6",   # realistic physics
    
    # Audio/Music
    music: "elevenlabs/music",               # song from prompt
    tts: "qwen/qwen3-tts",                   # 15.9K runs, clone/design
    
    # LLM
    llm: "google/gemini-3-flash",            # 99K runs, fast
    llm_agent: "moonshotai/kimi-k2.5"        # vision + multi-agent
  }.freeze

  # Prompt templates (from nano-banana guide + repligen.rb patterns)
  TEMPLATES = {
    # Image - portrait
    portrait: "photorealistic portrait, 85mm f/1.8, shallow depth of field, " \
              "golden hour lighting from 45 degrees, natural skin texture, " \
              "shot on ARRI Alexa Mini LF, Kodak Vision3 500T color science",
    
    # Image - product
    product: "high-end commercial photography, studio lighting with softbox, " \
             "clean white background, shallow depth of field, professional product shot",
    
    # Image - cinematic
    cinematic: "cinematic 2.39:1 anamorphic, teal and orange color grading, " \
               "dramatic rim lighting, shot on Atlas Orion 40mm Anamorphic, " \
               "horizontal lens flares, film grain texture",
    
    # Image - anime
    anime: "anime style illustration, Studio Ghibli aesthetic, cel shading, " \
           "vibrant colors, detailed background, soft lighting",
    
    # Video - motion (separate Camera: and Subject:)
    vid_motion: "Camera: [CAMERA_MOVE]. Subject: [SUBJECT_ACTION]. " \
                "Golden hour lighting, shallow depth of field, 35mm film aesthetic.",
    
    # Video - cinematic
    vid_cinematic: "Camera: Slow dolly-in, smooth fluid motion. " \
                   "Subject: Subtle natural movement, slight breathing. " \
                   "Cinematic lighting, film grain, professional grade.",
    
    # Audio - music
    music_prompt: "Studio-grade production, clear mix, professional mastering. " \
                  "Style: [GENRE]. Mood: [MOOD]. Duration: [LENGTH].",
    
    # TTS - voice design
    tts_voice: "Natural speaking voice, clear enunciation, [EMOTION] tone. " \
               "Pace: [SPEED]. Accent: [ACCENT]."
  }.freeze

  # Quick style suffixes
  STYLES = {
    photo: ", photorealistic, 8K, ultra-detailed",
    film: ", 35mm film grain, Kodak Portra 400, nostalgic",
    neon: ", neon lighting, cyberpunk, vibrant colors",
    minimal: ", minimalist, clean, negative space",
    vintage: ", vintage aesthetic, film grain, muted colors",
    hdr: ", HDR, high dynamic range, vivid colors"
  }.freeze

  # Model categories for wild chain
  WILD_CHAIN = {
    image_gen: %w[
      google/nano-banana-pro
      black-forest-labs/flux-2-klein-4b
      bytedance/seedream-4.5
      openai/gpt-image-1.5
    ],
    video_gen: %w[
      google/veo-3.1-fast
      kwaivgi/kling-v2.6
      pixverse/pixverse-v5.6
    ],
    enhance: %w[
      nightmareai/real-esrgan
      tencentarc/gfpgan
      lucataco/clarity-upscaler
    ],
    style: %w[
      adirik/depth-anything-v2
      lucataco/remove-bg
    ],
    audio: %w[
      elevenlabs/music
      qwen/qwen3-tts
    ]
  }.freeze

  class Client
    def initialize
      @token = ENV["REPLICATE_API_TOKEN"]
      @enabled = !@token.nil? && !@token.empty?
    end

    def enabled?
      @enabled
    end

    def api(method, path, body = nil)
      return nil unless @enabled

      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      req["Authorization"] = "Token #{@token}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json if body

      http.request(req)
    rescue StandardError => e
      Log.error("Replicate API error: #{e.message}")
      nil
    end

    def wait_for(id, name, timeout: 300)
      start = Time.now
      loop do
        sleep 3
        res = api(:get, "/predictions/#{id}")
        return nil unless res

        data = JSON.parse(res.body)
        case data["status"]
        when "succeeded"
          return data["output"].is_a?(Array) ? data["output"][0] : data["output"]
        when "failed"
          Log.error("#{name} failed: #{data['error']}")
          return nil
        end

        return nil if Time.now - start > timeout
      end
    end

    def run_model(model, input)
      res = api(:post, "/models/#{model}/predictions", { input: input })
      return nil unless res

      data = JSON.parse(res.body)
      wait_for(data["id"], model)
    end

    def generate_image(prompt, model: "black-forest-labs/flux-pro")
      Log.info("Generating image: #{prompt[0..50]}...")
      run_model(model, {
        prompt: prompt,
        aspect_ratio: "16:9",
        output_format: "webp"
      })
    end

    def generate_video(image_url, prompt, model: "minimax/video-01")
      Log.info("Generating video...")
      run_model(model, {
        prompt: prompt,
        first_frame_image: image_url,
        prompt_optimizer: true
      })
    end

    def wild_chain(prompt, steps: 5, seed: nil)
      seed ||= rand(1_000_000)
      srand(seed)

      Log.info("Wild chain: #{steps} steps, seed #{seed}")

      pipeline = build_pipeline(steps)
      result = nil
      artifacts = []

      pipeline.each_with_index do |step, i|
        Log.info("[#{i+1}/#{steps}] #{step[:category]} → #{step[:model]}")

        case step[:category]
        when :image_gen
          result = generate_image(prompt, model: step[:model])
        when :video_gen
          result = generate_video(result, prompt, model: step[:model]) if result
        when :enhance, :style
          result = run_model(step[:model], { image: result }) if result
        when :audio
          result = run_model(step[:model], { prompt: prompt[0..200] })
        end

        artifacts << { step: i, model: step[:model], result: result } if result
      end

      { seed: seed, artifacts: artifacts }
    end

    private

    def build_pipeline(steps)
      pipeline = [{ category: :image_gen, model: WILD_CHAIN[:image_gen].sample }]

      (steps - 1).times do
        cat = [:video_gen, :enhance, :style, :audio].sample
        model = WILD_CHAIN[cat]&.sample
        pipeline << { category: cat, model: model } if model
      end

      pipeline
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# SHELL MODULE: Natural Language System Administration
# ═══════════════════════════════════════════════════════════════════════════════
module Shell
  DANGEROUS_COMMANDS = %w[rm rf rmdir mkfs dd format fdisk newfs disklabel].freeze
  PRIVILEGE_COMMANDS = %w[doas sudo su].freeze

  SYSTEM_PROMPT = <<~PROMPT
    You are a protective bodyguard and system administrator assistant.

    Personality:
    - Overly protective of systems and data
    - Warn before any destructive or risky action
    - Create backups before modifications
    - Suggest safer alternatives when possible
    - Brief, direct, no fluff

    Language:
    - Respond in the user's language (English or Norwegian)
    - Follow Strunk & White: omit needless words, active voice, be clear
    - Conversational but professional
    - Norwegian: use bokmål, short sentences, avoid anglicisms

    When the user asks for a command:
    1. Briefly explain what you'll do
    2. Return the exact command in a ```zsh code block (never bash)
    3. If it needs root, prefix with `doas`
    4. If dangerous, add WARNING and ask for confirmation
    5. Always prefer zsh builtins over external commands

    Environment: OpenBSD, zsh, Ruby. You have access to shell commands,
    pkg_add, rcctl, ifconfig, pf, etc.

    Catchphrases: "Backing up first." "That looks risky. Confirm?" "Clean."
  PROMPT

  class Assistant
    def initialize(constitution)
      @constitution = constitution
      @history = []
      @tiered = TieredLLM.new(constitution)
    end

    def chat(user_input)
      @history << { role: "user", content: user_input }

      messages = [{ role: "system", content: SYSTEM_PROMPT }] + @history.last(10)

      response = @tiered.ask_tier("medium", messages)
      assistant_reply = response.to_s

      @history << { role: "assistant", content: assistant_reply }

      # Extract and offer to execute commands
      commands = extract_commands(assistant_reply)

      { reply: assistant_reply, commands: commands }
    end

    def execute(cmd, use_doas: false)
      full_cmd = use_doas ? "doas #{cmd}" : cmd

      # Safety check
      if dangerous?(cmd)
        return { error: "Dangerous command blocked. Use --force to override." }
      end

      Log.info("Executing: #{full_cmd}")

      output = `#{full_cmd} 2>&1`
      status = $?.exitstatus

      {
        command: full_cmd,
        output: output,
        exit_code: status,
        success: status == 0
      }
    end

    private

    def extract_commands(text)
      # Extract shell commands from ```sh blocks
      text.scan(/```(?:sh|bash|shell)?\n(.+?)```/m).flatten
    end

    def dangerous?(cmd)
      DANGEROUS_COMMANDS.any? { |d| cmd.include?(d) } && !Options.force
    end
  end

  class REPL
    def initialize(constitution)
      @assistant = Assistant.new(constitution)
      @running = true
    end

    def run
      puts "Shell Assistant (type 'exit' to quit, 'run' to execute last command)"
      puts

      while @running
        print "shell> "
        input = gets&.chomp
        break if input.nil?

        case input.downcase
        when "exit", "quit", "q"
          @running = false
        when "run", "!"
          execute_last_command
        when /^run\s+(.+)/
          @assistant.execute($1)
        when /^doas\s+(.+)/
          result = @assistant.execute($1, use_doas: true)
          puts result[:output]
        when ""
          next
        else
          result = @assistant.chat(input)
          puts
          puts result[:reply]
          puts

          if result[:commands].any?
            @last_commands = result[:commands]
            puts "Type 'run' to execute, or 'run <command>' for specific"
          end
        end
      end
    end

    private

    def execute_last_command
      return puts "No command to run" unless @last_commands&.any?

      @last_commands.each do |cmd|
        print "Execute '#{cmd}'? (y/n/doas) "
        confirm = gets&.chomp&.downcase

        case confirm
        when "y", "yes"
          result = @assistant.execute(cmd)
          puts result[:output]
        when "doas", "d"
          result = @assistant.execute(cmd, use_doas: true)
          puts result[:output]
        else
          puts "Skipped"
        end
      end
    end
  end
end

# IMPERATIVE SHELL

# Minimal cursor control (stolen from tty-cursor)
module Cursor
  CSI = "\e["

  def self.hide = CSI + "?25l"
  def self.show = CSI + "?25h"
  def self.up(n = 1) = CSI + "#{n}A"
  def self.down(n = 1) = CSI + "#{n}B"
  def self.forward(n = 1) = CSI + "#{n}C"
  def self.back(n = 1) = CSI + "#{n}D"
  def self.col(n = 1) = CSI + "#{n}G"
  def self.clear_line = CSI + "2K" + col(1)
  def self.clear_down = CSI + "J"
  def self.save = "\e7"
  def self.restore = "\e8"

  def self.invisible
    print hide
    yield
  ensure
    print show
  end
end

module Dmesg
  VERSION = "49.68"

  def self.boot
    return if Options.quiet
    # Single line boot - Unix minimal
    puts "#{VERSION} #{principle_count}p #{llm_status} #{File.basename(Dir.pwd)}/"
  end

  def self.build_number
    `git rev-list --count HEAD 2>/dev/null`.strip.then { |c| c.empty? ? "1" : c }
  rescue
    "1"
  end

  def self.tier_list
    content = File.read(File.expand_path("master.yml", __dir__), encoding: "UTF-8", invalid: :replace, undef: :replace)
    yaml = YAML.safe_load(content, permitted_classes: [Symbol])
    tiers = yaml.dig("llm", "tiers")&.keys || []
    tiers.join(" | ")
  rescue
    "fast | medium | strong"
  end

  def self.principle_count
    content = File.read(File.expand_path("master.yml", __dir__), encoding: "UTF-8", invalid: :replace, undef: :replace)
    yaml = YAML.safe_load(content, permitted_classes: [Symbol])
    yaml["principles"]&.size || 32
  rescue
    32
  end

  def self.llm_status
    if llm_ready?
      "ready, fallbacks enabled"
    else
      "offline (set OPENROUTER_API_KEY)"
    end
  end

  def self.status_line
    parts = []
    parts << (llm_ready? ? "llm:#{green}ok#{reset}" : "llm:#{yellow}off#{reset}")
    parts << "ruby:#{RUBY_VERSION}"
    parts.join(" | ")
  end

  def self.llm_ready?
    LLM_AVAILABLE && ENV["OPENROUTER_API_KEY"]
  end

  # Respect NO_COLOR (https://no-color.org/) and TERM=dumb
  def self.color_enabled?
    return false if ENV["NO_COLOR"]
    return false if ENV["TERM"] == "dumb"
    tty?
  end

  def self.bold = color_enabled? ? "\e[1m" : ""
  def self.dim = color_enabled? ? "\e[2m" : ""
  def self.green = color_enabled? ? "\e[32m" : ""
  def self.yellow = color_enabled? ? "\e[33m" : ""
  def self.red = color_enabled? ? "\e[31m" : ""
  def self.cyan = color_enabled? ? "\e[36m" : ""
  def self.magenta = color_enabled? ? "\e[35m" : ""
  def self.reset = color_enabled? ? "\e[0m" : ""
  def self.tty? = $stdout.respond_to?(:tty?) && $stdout.tty?

  # Safe emoji output - fallback to ASCII on dumb terminals
  EMOJI = {
    folder: ["[dir]", "\u{1F4C1}"],
    clean: ["[clean]", "\u{1F9F9}"],
    garden: ["[garden]", "\u{1F331}"],
    tree: ["[tree]", "\u{1F333}"],
    up: ["^", "\u{1F4C8}"],
    chart: ["~", "\u{1F4CA}"],
    list: ["-", "\u{1F4CB}"],
    shell: ["$", "\u{1F41A}"],
    chat: [">", "\u{1F4AC}"]
  }.freeze

  def self.icon(name)
    return EMOJI[name]&.first || name.to_s if ENV["NO_COLOR"] || ENV["TERM"] == "dumb"
    EMOJI[name]&.last || name.to_s
  end
end

module Log
  VERBOSE = ENV["VERBOSE"]

  def self.dmesg(subsystem, action, result = "", metrics = {})
    parts = ["#{Dmesg.dim}#{subsystem}#{Dmesg.reset} #{action}"]
    parts << result unless result.empty?
    parts << format_metrics(metrics) unless metrics.empty?
    puts parts.join(" ")
  end

  def self.format_metrics(metrics)
    "#{Dmesg.dim}#{metrics.map { |k, v| "#{k}=#{v}" }.join(" ")}#{Dmesg.reset}"
  end

  def self.log(level, message)
    prefix = case level
    when :ok then "#{Dmesg.green}ok#{Dmesg.reset}"
    when :error then "#{Dmesg.red}err#{Dmesg.reset}"
    when :warn then "#{Dmesg.yellow}warn#{Dmesg.reset}"
    else "#{Dmesg.dim}#{level}#{Dmesg.reset}"
    end
    puts "#{prefix} #{message}"
  end

  def self.phase(msg) = log(:phase, msg)
  def self.veto(msg) = log(:error, msg)
  def self.error(msg) = log(:error, msg)
  def self.warn(msg) = log(:warn, msg)
  def self.info(msg) = VERBOSE ? log(:info, msg) : nil
  def self.ok(msg) = log(:ok, msg)
  def self.debug(msg) = VERBOSE ? log(:debug, msg) : nil
end

class Spinner
  def initialize(message)
    @message = message
    @spinner = SPINNER_AVAILABLE ? TTY::Spinner.new(":spinner #{message}", format: :dots) : nil
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

# StatusLine - persistent status at bottom of terminal
class StatusLine
  SPINNER = %w[* . o O @ * ].freeze

  def initialize
    @intent = ""
    @progress = nil
    @enabled = Dmesg.tty?
    @spin_idx = 0
    @spinning = false
  end

  def set(intent)
    @intent = intent
    render if @enabled
  end

  def spin_start
    @spinning = true
    print Cursor.hide
    @spin_thread = Thread.new do
      while @spinning
        @spin_idx = (@spin_idx + 1) % SPINNER.size
        print Cursor.clear_line + "#{SPINNER[@spin_idx]} #{@intent}"
        $stdout.flush
        sleep 0.15
      end
    end
  end

  def spin_stop
    @spinning = false
    @spin_thread&.join
    print Cursor.clear_line + Cursor.show
    $stdout.flush
  end

  def progress(current, total, item = "")
    @progress = { current: current, total: total, item: item }
    render if @enabled
  end

  def clear
    return unless @enabled
    print Cursor.clear_line
    @intent = ""
    @progress = nil
  end

  def render
    return unless @enabled
    parts = []
    parts << "#{Dmesg.dim}#{@intent}#{Dmesg.reset}" unless @intent.empty?
    if @progress
      pct = (@progress[:current].to_f / @progress[:total] * 100).round
      parts << "#{@progress[:current]}/#{@progress[:total]} #{pct}%"
      parts << @progress[:item] unless @progress[:item].empty?
    end
    print "\r\e[K#{parts.join(' ')}"
  end
end

# Session - checkpoint save/load for conversation state
class Session
  SESSIONS_DIR = File.expand_path(".sessions", __dir__)

  def initialize(name = nil)
    @name = name || "session_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    @history = []
    @context = {}
    @plan = nil
    FileUtils.mkdir_p(SESSIONS_DIR)
  end

  attr_accessor :history, :context, :plan
  attr_reader :name

  def save
    data = {
      name: @name,
      saved_at: Time.now.iso8601,
      history: @history,
      context: @context,
      plan: @plan
    }
    File.write(path, YAML.dump(data))
    path
  end

  def self.load(name)
    path = File.join(SESSIONS_DIR, "#{name}.yml")
    return nil unless File.exist?(path)
    data = YAML.safe_load(File.read(path), permitted_classes: [Time, Symbol])
    s = new(data["name"])
    s.history = data["history"] || []
    s.context = data["context"] || {}
    s.plan = data["plan"]
    s
  end

  def self.list
    Dir.glob(File.join(SESSIONS_DIR, "*.yml")).map do |f|
      File.basename(f, ".yml")
    end.sort.reverse
  end

  def checkpoint(label = nil)
    @context[:checkpoint] = label || Time.now.iso8601
    save
  end

  private

  def path
    File.join(SESSIONS_DIR, "#{@name}.yml")
  end
end

# Plan - structured task planning before implementation
class Plan
  attr_accessor :goal, :tasks, :notes, :status

  def initialize(goal)
    @goal = goal
    @tasks = []
    @notes = []
    @status = :planning
  end

  def add_task(desc, subtasks = [])
    @tasks << { desc: desc, done: false, subtasks: subtasks.map { |s| { desc: s, done: false } } }
  end

  def complete_task(index)
    return unless @tasks[index]
    @tasks[index][:done] = true
  end

  def complete_subtask(task_idx, sub_idx)
    return unless @tasks[task_idx]&.dig(:subtasks, sub_idx)
    @tasks[task_idx][:subtasks][sub_idx][:done] = true
  end

  def progress
    return 0 if @tasks.empty?
    done = @tasks.count { |t| t[:done] }
    (done.to_f / @tasks.size * 100).round
  end

  def to_s
    lines = ["Goal: #{@goal}", "Progress: #{progress}%", ""]
    @tasks.each_with_index do |t, i|
      mark = t[:done] ? "x" : " "
      lines << "  (#{mark}) #{i + 1}. #{t[:desc]}"
      t[:subtasks]&.each_with_index do |s, j|
        smark = s[:done] ? "x" : " "
        lines << "      (#{smark}) #{i + 1}.#{j + 1}. #{s[:desc]}"
      end
    end
    lines << "" << "Notes:" << @notes.map { |n| "  - #{n}" }.join("\n") if @notes.any?
    lines.join("\n")
  end

  def to_h
    { goal: @goal, tasks: @tasks, notes: @notes, status: @status }
  end

  def self.from_h(h)
    p = new(h[:goal] || h["goal"])
    p.tasks = h[:tasks] || h["tasks"] || []
    p.notes = h[:notes] || h["notes"] || []
    p.status = (h[:status] || h["status"] || :planning).to_sym
    p
  end
end

# WebServer - serves cli.html and handles /poll, /chat endpoints
class WebServer
  DEFAULT_PORT = 8080

  def initialize(cli, port: nil)
    @cli = cli
    @port = port || find_available_port
    @response_queue = Queue.new
    @current_persona = "ronin"
    @server = nil
  end

  attr_reader :port

  def start
    # Kill any old ruby/webrick processes on common ports
    kill_old_servers

    html_path = File.join(File.dirname(__FILE__), "cli.html")

    @server = WEBrick::HTTPServer.new(
      Port: @port,
      BindAddress: "0.0.0.0",
      Logger: WEBrick::Log.new(File.exist?("/dev/null") ? "/dev/null" : "NUL"),
      AccessLog: []
    )

    # Serve cli.html at root
    @server.mount_proc "/" do |req, res|
      if File.exist?(html_path)
        res.content_type = "text/html"
        res.body = File.read(html_path)
      else
        res.status = 404
        res.body = "cli.html not found"
      end
    end

    # Poll endpoint for TTS responses
    @server.mount_proc "/poll" do |req, res|
      res.content_type = "application/json"

      begin
        # Non-blocking check for response
        if @response_queue.empty?
          res.body = JSON.generate({ text: nil, persona: @current_persona })
        else
          text = @response_queue.pop(true) rescue nil
          res.body = JSON.generate({ text: text, persona: @current_persona })
        end
      rescue => e
        res.body = JSON.generate({ text: nil, error: e.message })
      end
    end

    # Chat endpoint for incoming messages
    @server.mount_proc "/chat" do |req, res|
      res.content_type = "application/json"

      begin
        body = JSON.parse(req.body)
        message = body["message"]

        if message && !message.empty?
          # Process in background thread
          Thread.new do
            response = process_chat(message)
            @response_queue.push(response) if response
          end

          res.body = JSON.generate({ status: "processing" })
        else
          res.body = JSON.generate({ status: "error", message: "No message provided" })
        end
      rescue => e
        res.body = JSON.generate({ status: "error", message: e.message })
      end
    end

    # Persona endpoint
    @server.mount_proc "/persona" do |req, res|
      res.content_type = "application/json"

      if req.request_method == "POST"
        body = JSON.parse(req.body) rescue {}
        @current_persona = body["persona"] if body["persona"]
      end

      res.body = JSON.generate({ persona: @current_persona })
    end

    # Start server in background thread
    @thread = Thread.new { @server.start }

    # Trap signals for clean shutdown
    trap("INT") { stop }
    trap("TERM") { stop }

    url
  end

  def stop
    @server&.shutdown
    @thread&.kill
  end

  def url
    host = ENV["HOST"] || ENV["HOSTNAME"] || "brgen.no"
    "http://#{host}:#{@port}"
  end

  def push_response(text)
    @response_queue.push(text)
  end

  private

  def find_available_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  rescue
    DEFAULT_PORT
  end

  def kill_old_servers
    # Kill any old cli.rb processes (except self)
    if RUBY_PLATFORM =~ /openbsd|linux|darwin/
      # Find all ruby processes running cli.rb
      pids = `pgrep -f "ruby.*cli.rb" 2>/dev/null`.strip.split("\n")
      pids.each do |pid|
        pid = pid.strip.to_i
        if pid > 0 && pid != Process.pid
          Process.kill("TERM", pid) rescue nil
          sleep 0.1
        end
      end
    end
  rescue
    # Silently ignore errors
  end

  def process_chat(message)
    return nil unless @cli

    # Use CLI's chat mechanism
    @cli.instance_variable_set(:@chat_history, @cli.instance_variable_get(:@chat_history) || [])
    @cli.instance_variable_get(:@chat_history) << { role: "user", content: message }

    tiered = @cli.instance_variable_get(:@tiered)
    return "LLM not available" unless tiered&.enabled?

    # Get persona-specific prompt
    persona_prompt = get_persona_prompt(@current_persona)

    response = tiered.ask_tier("medium", message, system_prompt: persona_prompt)

    if response
      @cli.instance_variable_get(:@chat_history) << { role: "assistant", content: response }
      response
    else
      "I understand. What would you like me to do?"
    end
  end

  def get_persona_prompt(persona)
    prompts = {
      "ronin" => "You follow the way of the samurai (Hagakure). Speak only when necessary. Few words. Decisive action. Complete loyalty to the task. No hesitation."
    }
    prompts[persona] || prompts["ronin"]
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
  attr_reader :raw, :principles, :phases, :defaults, :llm_config, :style, :safety, :conflicts, :language_detection, :profiles, :principle_groups, :active_profile, :hooks_config

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
          content = File.read(full, encoding: "UTF-8", invalid: :replace, undef: :replace)
          yaml = YAML.safe_load(content, permitted_classes: [Symbol])
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
    @profiles = yaml["profiles"] || {}
    @principle_groups = yaml["principle_groups"] || {}
    @hooks_config = yaml["hooks"] || {}
    @active_profile = nil

    validate_principles
    load_hooks
  end

  def set_profile(profile_name)
    return unless profile_name

    if profile_name == "full" || @profiles[profile_name]
      @active_profile = profile_name
      Log.info("Using profile: #{profile_name}") unless Options.quiet
    else
      Log.warn("Unknown profile '#{profile_name}', using full")
      @active_profile = "full"
    end
  end

  def active_principles
    return @principles unless @active_profile && @active_profile != "full"

    profile_config = @profiles[@active_profile]
    Core::PrincipleRegistry.filter_by_profile(@principles, profile_config, @principle_groups)
  end

  private

  def validate_principles
    result = Core::PrincipleRegistry.validate_no_cycles(@principles)

    unless result[:valid]
      Log.warn("Constitution warning: #{result[:reason]}")
    end
  end

  def load_hooks
    Core::Hooks.load_from_config(@hooks_config)
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

    # Handle empty or nil content
    return {valid: true} if content.nil? || content.empty?

    if content.count("\x00") > 0
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
  RETRY_INTERVAL = 0.5

  def self.acquire(file_path, config)
    return nil unless config["file_locking"]

    lock_file = prepare_lock_path(file_path, config["lock_dir"])
    deadline = Time.now + config["lock_timeout"]

    loop do
      return lock_file if try_create_lock(lock_file)
      return nil if Time.now > deadline

      remove_stale_lock(lock_file, config["stale_lock_age"])
      sleep RETRY_INTERVAL
    end
  end

  def self.prepare_lock_path(file_path, lock_dir)
    FileUtils.mkdir_p(lock_dir)
    File.join(lock_dir, "#{File.basename(file_path)}.lock")
  end

  def self.try_create_lock(lock_file)
    File.open(lock_file, File::CREAT | File::EXCL | File::WRONLY) do |f|
      f.write("#{Process.pid}\n#{Time.now}\n")
    end
    true
  rescue Errno::EEXIST
    false
  end

  def self.remove_stale_lock(lock_file, stale_age)
    return unless File.exist?(lock_file)
    return unless Time.now - File.mtime(lock_file) > stale_age

    File.delete(lock_file)
  rescue Errno::ENOENT
    # Already removed
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

# Tiered LLM Pipeline: fast → medium → strong (60-80% cost savings)
class TieredLLM
  attr_reader :stats

  def initialize(constitution)
    @constitution = constitution
    @tiers = constitution.llm_config["tiers"] || {}
    @sequence = constitution.llm_config["default_tier_sequence"] || ["fast", "medium", "strong"]
    @caching = constitution.llm_config["prompt_caching"] || {}
    @stats = { calls: 0, tokens: 0, cost: 0.0, cached_tokens: 0 }
    @enabled = LLM_AVAILABLE && ENV["OPENROUTER_API_KEY"]

    setup if @enabled
  end

  def enabled?
    @enabled
  end

  def ask_tier(tier_name, prompt, system_prompt: nil)
    return nil unless @enabled

    tier = @tiers[tier_name.to_s]
    return nil unless tier

    messages = build_messages(prompt, system_prompt, tier_name)

    call_model(
      model: tier["model"],
      messages: messages,
      max_tokens: tier["max_tokens"] || 2048,
      temperature: tier["temperature"] || 0.3
    )
  end

  # Run tiered pipeline: fast detection → medium explanation → strong validation
  def pipeline(code, file_path, phases: [:detect, :explain, :validate])
    results = {}

    phases.each_with_index do |phase, idx|
      tier_name = @sequence[idx] || @sequence.last

      prompt = case phase
      when :detect
        "Detect violations in this code (JSON array only):\n\n#{code}"
      when :explain
        "Explain these violations:\n#{results[:detect]}\n\nCode:\n#{code}"
      when :validate
        "Validate fixes and provide final judgment:\n#{results[:explain]}"
      else
        "Analyze:\n#{code}"
      end

      results[phase] = ask_tier(tier_name, prompt)
    end

    results
  end

  # Streaming version of ask_tier
  def ask_tier_stream(tier_name, prompt, system_prompt: nil, &block)
    puts "[DEBUG ask_tier_stream] tier=#{tier_name} enabled=#{@enabled ? 'true' : 'false'}" if ENV["DEBUG"]
    return nil unless @enabled

    tier = @tiers[tier_name.to_s]
    puts "[DEBUG ask_tier_stream] tier config: #{tier.inspect}" if ENV["DEBUG"]
    return nil unless tier

    messages = build_messages(prompt, system_prompt, tier_name)

    call_model(
      model: tier["model"],
      messages: messages,
      max_tokens: tier["max_tokens"] || 2048,
      temperature: tier["temperature"] || 0.3,
      stream: true,
      &block
    )
  end

  private

  def setup
    RubyLLM.configure do |config|
      config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
    end
  end

  def build_messages(prompt, system_prompt, tier_name)
    messages = []

    # System prompt with caching if enabled
    if system_prompt
      sys_msg = { role: "system", content: system_prompt }

      if @caching["enabled"] && tier_name != "fast"
        sys_msg[:provider_options] = {
          openrouter: {
            cache_control: { type: "ephemeral", ttl: @caching["default_ttl"] || "1h" }
          }
        }
      end

      messages << sys_msg
    end

    messages << { role: "user", content: prompt }
    messages
  end

  def call_model(model:, messages:, max_tokens:, temperature:, stream: false, &block)
    @stats[:calls] += 1

    puts "[DEBUG call_model] model=#{model} stream=#{stream}" if ENV["DEBUG"]

    chat = RubyLLM.chat(model: model, provider: :openrouter)

    user_msg = messages.find { |m| m[:role] == "user" }
    system_msg = messages.find { |m| m[:role] == "system" }

    full_prompt = ""
    full_prompt += "#{system_msg[:content]}\n\n" if system_msg
    full_prompt += user_msg[:content] if user_msg

    puts "[DEBUG call_model] prompt_len=#{full_prompt.length} calling chat.ask..." if ENV["DEBUG"]

    if stream && block_given?
      # Streaming mode - yield chunks as they arrive
      full_response = ""
      chunk_count = 0
      response = chat.ask(full_prompt) do |chunk|
        chunk_count += 1
        if chunk.content
          full_response += chunk.content
          yield chunk.content
        end
      end
      puts "[DEBUG call_model] stream done, chunks=#{chunk_count} response_len=#{full_response.length}" if ENV["DEBUG"]
      track_usage(response, model)
      full_response
    else
      response = chat.ask(full_prompt)
      puts "[DEBUG call_model] non-stream done, response=#{response.class}" if ENV["DEBUG"]
      track_usage(response, model)
      response.content
    end
  rescue StandardError => e
    puts "[DEBUG call_model] ERROR: #{e.class}: #{e.message}" if ENV["DEBUG"]
    Log.warn("TieredLLM error: #{e.message}")
    nil
  end

  def track_usage(response, model)
    prompt = response.input_tokens || 0
    completion = response.output_tokens || 0

    @stats[:tokens] += prompt + completion
    @stats[:cost] += estimate_cost(model, prompt, completion)

    # Track cached tokens if available
    if response.respond_to?(:cached_tokens)
      @stats[:cached_tokens] += response.cached_tokens || 0
    end
  end

  def estimate_cost(model, prompt, completion)
    Core::CostEstimator.estimate(model, prompt, completion)
  end
end

# Parallel cheap smell detectors (10-40x cost reduction on detection)
class ParallelDetector
  HISTORY_FILE = ".constitutional_history.json"
  MAX_HISTORY_ENTRIES = 1000
  MAX_CODE_PREVIEW = 2000

  def initialize(constitution, tiered_llm)
    @constitution = constitution
    @tiered = tiered_llm
    @smells = extract_smells
  end

  def scan(code, file_path)
    return [] unless @tiered.enabled?
    return sequential_scan(code, file_path) unless CONCURRENT_AVAILABLE

    require "concurrent"

    futures = @smells.map do |smell|
      Concurrent::Future.execute do
        detect_single_smell(code, smell)
      end
    end

    results = futures.map { |f| f.value(10) }.compact.flatten

    # Filter to real hits
    results.select { |r| r["found"] }
  rescue StandardError => e
    Log.warn("Parallel scan failed: #{e.message}")
    sequential_scan(code, file_path)
  end

  def record_history(file_path, result)
    history = load_history

    history << {
      "file" => file_path,
      "timestamp" => Time.now.iso8601,
      "iterations" => result[:iterations] || 1,
      "final_score" => result[:score] || 0,
      "issues_count" => result[:violations]&.size || 0,
      "novel_smells_count" => result[:novel_smells] || 0,
      "parallel_hits" => result[:parallel_hits] || 0
    }

    history = history.last(MAX_HISTORY_ENTRIES)

    File.write(HISTORY_FILE, JSON.pretty_generate(history))
  rescue StandardError => e
    Log.debug("History write failed: #{e.message}")
  end

  def collect_painful_cases
    history = load_history

    history.select do |entry|
      entry["iterations"].to_i > 5 ||
        entry["final_score"].to_i < 85 ||
        entry["novel_smells_count"].to_i > 0 ||
        entry["parallel_hits"].to_i > 6
    end.map do |e|
      { file: e["file"], issues: e["issues_count"], iterations: e["iterations"] }
    end
  end

  private

  def extract_smells
    @constitution.active_principles.flat_map do |_, p|
      (p["smells"] || []).map { |s| { name: s, principle: p["name"], priority: p["priority"] } }
    end.uniq { |s| s[:name] }
  end

  def sequential_scan(code, file_path)
    @smells.first(10).map { |smell| detect_single_smell(code, smell) }.compact.flatten
  end

  def detect_single_smell(code, smell)
    prompt = "Check if this code has '#{smell[:name]}' smell. Return JSON: {\"found\": bool, \"line\": int, \"explanation\": str}\n\n#{code[0, MAX_CODE_PREVIEW]}"

    result = @tiered.ask_tier("fast", prompt)
    return nil unless result

    parsed = JSON.parse(result) rescue nil
    return nil unless parsed

    if parsed["found"]
      parsed["smell"] = smell[:name]
      parsed["principle"] = smell[:principle]
      parsed["priority"] = smell[:priority]
    end

    parsed
  rescue StandardError
    nil
  end

  def load_history
    return [] unless File.exist?(HISTORY_FILE)
    JSON.parse(File.read(HISTORY_FILE)) rescue []
  end
end

# Gardener: self-improving constitution
class Gardener
  def initialize(constitution, tiered_llm)
    @constitution = constitution
    @tiered = tiered_llm
    @detector = ParallelDetector.new(constitution, tiered_llm)
  end

  def run_quick
    learned = @constitution.llm_config["learned_smells"] || []
    return "No learned smells yet" if learned.empty?

    prompt = <<~PROMPT
      Review these learned code smells and suggest which should be promoted to full principles:

      #{learned.to_yaml}

      Return JSON: {"promote": ["smell_id1"], "remove": ["smell_id2"], "merge": [["id1", "id2"]]}
    PROMPT

    @tiered.ask_tier("strong", prompt)
  end

  def run_full
    painful = @detector.collect_painful_cases

    if painful.empty?
      return "No painful cases recorded yet. Run more files first."
    end

    prompt = <<~PROMPT
      These files caused problems during code quality enforcement:

      #{painful.first(20).to_yaml}

      Based on these patterns, suggest:
      1. New principles or smells to add
      2. Existing principles that need clarification
      3. Priority adjustments

      Return structured YAML that can merge into master.yml
    PROMPT

    @tiered.ask_tier("strong", prompt)
  end
end

# Reflection Critic: validates fixes before applying
class ReflectionCritic
  def initialize(tiered_llm)
    @tiered = tiered_llm
  end

  def critique(original_code, proposed_fix, violations_fixed)
    return { approved: true, confidence: 1.0 } unless @tiered.enabled?

    prompt = <<~PROMPT
      You are a strict code quality critic. Review this proposed fix:

      ORIGINAL CODE:
      #{original_code[0, 1000]}

      PROPOSED FIX:
      #{proposed_fix[0, 1000]}

      VIOLATIONS BEING FIXED:
      #{violations_fixed.map { |v| "- #{v['smell']}: #{v['explanation']}" }.join("\n")}

      EVALUATE:
      1. Does the fix introduce NEW higher-priority violations?
      2. Does it preserve clarity, simplicity, and explicitness?
      3. Is it a safe, minimal change?
      4. Could it break existing behavior?

      Return ONLY JSON:
      {
        "approved": true/false,
        "confidence": 0.0-1.0,
        "issues": ["issue 1", "issue 2"],
        "suggestions": ["suggestion 1"]
      }
    PROMPT

    result = @tiered.ask_tier("medium", prompt)
    return { "approved" => true, "confidence" => 0.5 } unless result

    parsed = JSON.parse(result)
    # Ensure consistent string keys
    {
      "approved" => parsed["approved"] != false,
      "confidence" => parsed["confidence"] || 0.5,
      "issues" => parsed["issues"] || [],
      "suggestions" => parsed["suggestions"] || []
    }
  rescue JSON::ParserError, TypeError
    { "approved" => true, "confidence" => 0.5 }
  end
end

# Pattern Memory: remembers past fixes and violations
class PatternMemory
  MEMORY_FILE = ".constitutional_memory.json"
  MAX_PATTERNS = 500

  def initialize
    @patterns = load_patterns
  end

  def remember(file_path, violation, fix_applied, success)
    @patterns << {
      "timestamp" => Time.now.iso8601,
      "file" => File.basename(file_path),
      "smell" => violation["smell"],
      "principle_id" => violation["principle_id"],
      "fix_worked" => success,
      "context" => (violation["explanation"] || "")[0, 100]
    }

    @patterns = @patterns.last(MAX_PATTERNS)
    save_patterns
  end

  def similar_past_fixes(smell, limit: 5)
    @patterns
      .select { |p| p["smell"] == smell && p["fix_worked"] }
      .last(limit)
  end

  def success_rate(smell)
    relevant = @patterns.select { |p| p["smell"] == smell }
    return 0.0 if relevant.empty?

    successful = relevant.count { |p| p["fix_worked"] }
    successful.to_f / relevant.size
  end

  private

  def load_patterns
    return [] unless File.exist?(MEMORY_FILE)
    JSON.parse(File.read(MEMORY_FILE)) rescue []
  end

  def save_patterns
    File.write(MEMORY_FILE, JSON.pretty_generate(@patterns))
  rescue StandardError
    nil
  end
end

class LLMClient
  attr_reader :total_cost, :total_tokens, :call_count, :tiered

  def initialize(constitution)
    @constitution = constitution
    @enabled = LLM_AVAILABLE && ENV["OPENROUTER_API_KEY"]
    @total_cost = 0.0
    @total_tokens = 0
    @call_count = 0
    @session_cost = 0.0
    @tiered = nil
    @current_file = nil

    setup if @enabled
  end

  def enabled?
    @enabled
  end

  def set_current_file(path)
    @current_file = path
  end

  # Chat with message history (for conversational mode)
  def chat(messages, tier: "medium")
    return nil unless @enabled
    @tiered&.ask_tier(tier, messages.last[:content], system_prompt: messages.first[:content])
  end

  # Simple query (backwards compatible)
  def query(prompt, tier: "fast")
    return nil unless @enabled
    @tiered&.ask_tier(tier, prompt)
  end

  # Book-based code quality checks
  # Sources: Clean Code, Refactoring, POODR, Pragmatic Programmer, Unix Philosophy
  DETECTION_SYSTEM_PROMPT = <<~PROMPT.strip
    You are a code quality analyzer trained on these authoritative sources:

    CLEAN CODE (Robert C. Martin):
    - Functions should do one thing, do it well, do it only
    - Functions should be small (< 20 lines ideal)
    - No side effects - function does what name says, nothing more
    - Command/Query separation - either do something OR answer something
    - DRY - Don't Repeat Yourself
    - Boy Scout Rule - leave code cleaner than you found it

    REFACTORING (Martin Fowler):
    - Bloaters: long method, god class, primitive obsession, long param list
    - Couplers: feature envy, inappropriate intimacy, message chains
    - Dispensables: dead code, lazy class, speculative generality
    - Change preventers: divergent change, shotgun surgery

    POODR (Sandi Metz):
    - Single Responsibility: class has one reason to change
    - Depend on abstractions, not concretions
    - Prefer composition over inheritance
    - Duck typing over type checking
    - Sandi Metz rules: 100 lines/class, 5 lines/method, 4 params max, 1 object passed to controller

    PRAGMATIC PROGRAMMER (Hunt & Thomas):
    - Don't live with broken windows
    - Be a catalyst for change
    - Make it easy to reuse
    - Eliminate effects between unrelated things (orthogonality)
    - No duplicate knowledge (DRY)

    UNIX PHILOSOPHY (OpenBSD):
    - Do one thing well
    - Expect output to become input
    - Fail early, fail loudly
    - Worse is better - simple beats perfect
    - Security by default

    TASK:
    1. Scan code against these principles
    2. Return ONLY valid JSON array of violations
    3. Each: {"principle_id": N, "line": N, "severity": "high|medium|low", "smell": "name", "explanation": "why", "source": "clean_code|fowler|poodr|pragmatic|unix", "auto_fixable": bool}
    4. Return [] if no violations
    5. NO markdown, ONLY JSON
  PROMPT

  LARGE_FILE_TOKEN_THRESHOLD = 10_000

  def detect_violations(code, file_path)
    return [] unless detection_enabled?
    return detect_chunked(code, file_path) if should_chunk?(code)

    check_cost_limit("file")
    run_detection(code, file_path)
  rescue StandardError => e
    Log.warn("LLM detection failed: #{e.message}")
    []
  end

  def detection_enabled?
    return false unless @enabled

    config = @constitution.llm_config["detection"]
    config && config["enabled"]
  end

  def run_detection(code, file_path)
    config = @constitution.llm_config["detection"]
    prompt = Core::LLMDetector.detect_violations(
      code, file_path, @constitution.active_principles, config["prompt"]
    )[:prompt]

    # Show which file we're analyzing
    short_path = file_path.sub(Dir.pwd + "/", "").sub(Dir.pwd + "\\", "")
    print "#{Dmesg.dim}scan#{Dmesg.reset} #{short_path} "
    $stdout.flush

    response = call_llm_with_fallback(
      model: fast_model,
      fallback_models: config["fallback_models"],
      messages: build_cached_messages(system: DETECTION_SYSTEM_PROMPT, user: prompt),
      max_tokens: fast_max_tokens
    )

    puts "#{Dmesg.green}ok#{Dmesg.reset}"
    Core::LLMDetector.parse_violations(response.dig("choices", 0, "message", "content"))
  end

  def fast_model
    config = @constitution.llm_config["detection"]
    tiers = @constitution.llm_config["tiers"]
    # Prefer detection.model, then fall back to fast tier
    config&.dig("model") || tiers&.dig("fast", "model")
  end

  def fast_max_tokens
    @constitution.llm_config.dig("tiers", "fast", "max_tokens") || 2048
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

    # Initialize tiered LLM for critic and gardener
    @tiered = TieredLLM.new(@constitution)
  end

  def call_llm_with_fallback(model:, fallback_models:, messages:, max_tokens:)
    models = [model] + (fallback_models || [])

    # Filter out models in cooldown, but keep at least one
    available = models.reject { |m| Core::ModelCooldown.in_cooldown?(m) }
    available = [models.first] if available.empty?

    if available.size < models.size
      skipped = models - available
      Log.debug("Skipping cooled-down models: #{skipped.join(', ')}") if ENV["VERBOSE"]
    end

    available.each_with_index do |current_model, index|
      begin
        return call_llm(
          model: current_model,
          messages: messages,
          max_tokens: max_tokens
        )
      rescue StandardError => error
        # Set cooldown on rate limit errors
        if error.message =~ /rate.?limit|429|too.?many.?requests/i
          cooldown_config = @constitution.llm_config.dig("failover", "cooldown_seconds") || 300
          Core::ModelCooldown.set_cooldown(current_model, cooldown_config)
          Log.warn("Rate limited: #{current_model} (cooldown #{cooldown_config}s)") unless Options.quiet
        end

        if index < available.size - 1
          Log.warn("Model #{current_model} failed, trying fallback...") unless Options.quiet
        else
          raise error
        end
      end
    end
  end

  def call_llm(model:, messages:, max_tokens:)
    @call_count += 1
    start_time = Time.now

    if ENV["TRACE"]
      puts "  #{Dmesg.dim}[trace] llm.call model=#{model.split('/').last} max_tokens=#{max_tokens}#{Dmesg.reset}"
    end

    chat = RubyLLM.chat(model: model, provider: :openrouter)

    # Build conversation from messages
    user_msg = messages.find { |m| m[:role] == "user" }
    system_msg = messages.find { |m| m[:role] == "system" }

    prompt = ""
    prompt += "#{system_msg[:content]}\n\n" if system_msg
    prompt += user_msg[:content] if user_msg

    response = chat.ask(prompt)
    elapsed = Time.now - start_time

    if ENV["TRACE"]
      puts "  #{Dmesg.dim}[trace] llm.done in=#{response.input_tokens} out=#{response.output_tokens} time=#{format("%.1fs", elapsed)}#{Dmesg.reset}"
    end

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

    # Persist to cross-session tracking
    Core::CostTracker.record(model, total, cost, @current_file)

    unless Options.quiet
      Log.dmesg("llm", model.split("/").last, "completed", {
        tokens: total,
        cost: format("$%.4f", cost)
      })
    end
  end

  def estimate_cost(model, prompt, completion)
    Core::CostEstimator.estimate(model, prompt, completion)
  end

  def check_cost_limit(scope)
    # Skip all limits in sandbox mode
    return if ENV["SANDBOX"] || Options.force

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

  def build_cached_messages(system:, user:)
    messages = []

    caching = @constitution.llm_config["prompt_caching"]

    sys_msg = { role: "system", content: system }

    # Add cache control for Claude models if caching enabled
    if caching && caching["enabled"]
      sys_msg[:provider_options] = {
        openrouter: {
          cache_control: { type: "ephemeral", ttl: caching["default_ttl"] || "1h" }
        }
      }
    end

    messages << sys_msg
    messages << { role: "user", content: user }
    messages
  end

  def should_chunk?(code)
    estimate = Core::TokenEstimator.warn_if_expensive(code, LARGE_FILE_TOKEN_THRESHOLD)
    if estimate[:warning]
      Log.warn("Large file: ~#{estimate[:tokens]} tokens estimated")
    end

    chunk_config = @constitution.safety["cost_protection"]
    chunk_config["chunk_large_files"] && code.lines.size > chunk_config["chunk_size_lines"]
  end

  def detect_chunked(code, file_path)
    chunk_config = @constitution.safety["cost_protection"]
    chunk_size = chunk_config["chunk_size_lines"]
    overlap = chunk_config["chunk_overlap_lines"]

    lines = code.lines
    violations = []

    (0...lines.size).step(chunk_size - overlap) do |start_idx|
      end_idx = [start_idx + chunk_size, lines.size].min
      chunk = lines[start_idx...end_idx].join

      Log.info("Processing chunk #{start_idx + 1}-#{end_idx} of #{lines.size}")

      chunk_violations = run_detection(chunk, file_path)

      chunk_violations.each do |v|
        v["line"] = (v["line"] || 0) + start_idx
      end

      violations.concat(chunk_violations)
    end

    violations.uniq { |v| [v["line"], v["principle_id"]] }
  end

  def detect_violations_single(code, file_path)
    config = @constitution.llm_config["detection"]
    prompt = Core::LLMDetector.detect_violations(
      code, file_path, @constitution.active_principles, config["prompt"]
    )[:prompt]

    response = call_llm_with_fallback(
      model: config["model"],
      fallback_models: config["fallback_models"],
      messages: [
        { role: "system", content: DETECTION_SYSTEM_PROMPT },
        { role: "user", content: prompt }
      ],
      max_tokens: 4000
    )

    Core::LLMDetector.parse_violations(response.dig("choices", 0, "message", "content"))
  end

  def build_refactor_prompt(violation, code)
    principle_id = violation["principle_id"]
    principle = Core::PrincipleRegistry.find_by_id(@constitution.active_principles, principle_id)

    prompt = "Fix this violation:\n\n"
    prompt += "Violation: #{violation["explanation"]}\n"

    # Use full principle details (Level 2) for refactoring context
    if principle
      prompt += "\n#{Core::LLMDetector.build_full_details(principle)}\n\n"
    end

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
    @memory = PatternMemory.new
    @critic = ReflectionCritic.new(llm.tiered) if llm.tiered
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

    # For shell/zsh scripts, extract and analyze embedded configs
    if %w[shell zsh].include?(language)
      code = File.read(file_path, encoding: "UTF-8")
      openbsd_cfg = @constitution.raw.dig("openbsd") || {}
      config_map = openbsd_cfg["configs"] || {}
      base_url = openbsd_cfg["man_base_url"] || "https://man.openbsd.org"
      cache_ttl = openbsd_cfg["cache_ttl"] || 86400

      configs = Core::OpenBSDConfig.extract_configs(code, config_map)

      if configs.any?
        Log.info("Found #{configs.size} embedded OpenBSD configs (in memory):")

        fixes_to_apply = []

        configs.each do |cfg|
          Log.info("  • #{cfg[:name]} → #{cfg[:daemon]} (man: #{cfg[:man_page]})")

          # Fetch man page for this config
          man_content = Core::OpenBSDConfig.fetch_man_page(cfg[:man_page], base_url, cache_ttl)
          Log.info("    ↳ Fetched #{base_url}/#{cfg[:man_page]}") if man_content

          # Validate against rules from master.yml
          validation = Core::OpenBSDConfig.validate_config(cfg[:name], cfg[:content], config_map)

          if validation[:warnings].any?
            validation[:warnings].each { |w| Log.warn("    #{w}") }

            # Generate fix using LLM with man page context
            unless read_only
              man_summary = man_content || "Man page not available"
              fixed_content = Core::OpenBSDConfig.generate_fix(cfg, validation[:warnings], man_summary, @llm)

              if fixed_content && fixed_content != cfg[:content]
                fixes_to_apply << {
                  path: cfg[:path],
                  name: cfg[:name],
                  old_content: cfg[:content],
                  new_content: fixed_content
                }
                Log.ok("    Generated fix for #{cfg[:name]}")
              end
            end
          else
            Log.ok("    No issues found")
          end
        end

        # Apply all fixes directly to source file
        if fixes_to_apply.any? && !read_only
          puts
          Log.info("Applying #{fixes_to_apply.size} fixes to #{file_path}...")

          if Core::OpenBSDConfig.apply_fixes_to_source(file_path, fixes_to_apply)
            Log.ok("Fixed #{fixes_to_apply.size} embedded configs in place")
          else
            Log.warn("No changes applied (patterns not matched)")
          end
        end

        puts
        @openbsd_context = Core::OpenBSDConfig.config_context(configs, base_url, cache_ttl)
      end
    end

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
      history = update_history(history, iteration, violations)

      return Result.err("Too many violations. File too complex.") if too_many_violations?(history)
      return Result.ok(true) if converged?(violations, iteration)

      Log.info("Iteration #{iteration + 1}: #{violations.size} violations")

      stuck = check_convergence_issues(history)
      return Result.ok(false) if stuck

      break if read_only
      maybe_gc(iteration)
    end

    Result.ok(true)
  end

  def update_history(history, iteration, violations)
    history << {iteration: iteration + 1, violations: violations}
    max_size = @safety["convergence"]["max_history_size"]
    history.size > max_size ? history.drop(1) : history
  end

  def too_many_violations?(history)
    total = history.sum { |h| h[:violations].size }
    total > @safety["convergence"]["max_total_violations"]
  end

  def converged?(violations, iteration)
    return false unless violations.empty?

    Log.ok("Zero violations after #{iteration + 1} iteration(s)") unless Options.quiet
    true
  end

  def check_convergence_issues(history)
    if Core::ConvergenceDetector.detect_loop(history)
      Log.warn("Convergence loop detected (stuck)") unless Options.quiet
      return true
    end

    if Core::ConvergenceDetector.detect_oscillation(history)
      Log.warn("Oscillation detected (alternating states)") unless Options.quiet
      return true
    end

    if history.size >= 3 && !Core::ConvergenceDetector.improving?(history)
      Log.warn("No improvement detected") unless Options.quiet
      return true
    end

    false
  end

  def maybe_gc(iteration)
    interval = @safety["memory"]["gc_every_n_iterations"]
    GC.start if (iteration + 1) % interval == 0
  end

  def refactor_remaining(file_path)
    violations = scan_with_llm(file_path)
    auto_fixable = violations.select { |v| v["auto_fixable"] }

    if auto_fixable.empty?
      Log.info("No auto-fixable violations")
      return Result.ok(false)
    end

    Log.info("Refactoring #{auto_fixable.size} violations with AI")

    original_code = File.read(file_path, encoding: "UTF-8")

    # Check past success rate for these violations
    auto_fixable.each do |v|
      rate = @memory.success_rate(v["smell"])
      if rate > 0 && rate < 0.3
        Log.warn("  Low past success (#{(rate * 100).round}%) for: #{v['smell']}") unless Options.quiet
      end
    end

    # Generate fix using LLM
    proposed_fix = generate_fix_for_violations(file_path, original_code, auto_fixable)

    return Result.ok(false) if proposed_fix.nil? || proposed_fix == original_code

    # Reflection Critic: validate before applying
    if @critic
      critique = @critic.critique(original_code, proposed_fix, auto_fixable)
      confidence = critique["confidence"] || 0.5

      if critique["approved"] == false
        Log.warn("Fix rejected by critic (confidence: #{(confidence * 100).round}%)")
        (critique["issues"] || []).each { |i| Log.warn("  - #{i}") }

        # Remember this failure
        auto_fixable.each do |v|
          @memory.remember(file_path, v, false, false)
        end

        return Result.ok(false)
      end

      Log.info("Critic approved (confidence: #{(confidence * 100).round}%)") unless Options.quiet
    end

    # Apply fix in-place
    apply_fix_in_place(file_path, original_code, proposed_fix)

    # Remember success
    auto_fixable.each do |v|
      @memory.remember(file_path, v, true, true)
    end

    Result.ok(true)
  end

  def generate_fix_for_violations(file_path, code, violations)
    return code if violations.empty?

    violation_list = violations.map { |v|
      "Line #{v['line']}: #{v['smell']} - #{v['message']}"
    }.join("\n")

    prompt = <<~PROMPT
      Fix these violations in the code. Return ONLY the fixed code, no explanations.

      File: #{File.basename(file_path)}

      Violations to fix:
      #{violation_list}

      Current code:
      ```
      #{code}
      ```

      Return the complete fixed code:
    PROMPT

    begin
      response = @llm.call_llm_with_fallback(prompt, tier: :code)
      extract_code_from_response(response)
    rescue => e
      Log.warn("Fix generation failed: #{e.message}")
      nil
    end
  end

  def extract_code_from_response(response)
    return nil unless response

    content = response.content rescue response.to_s

    # Extract code from markdown code blocks
    if content =~ /```\w*\n(.*?)```/m
      return $1.strip
    end

    # If no code block, return as-is (might be raw code)
    content.strip
  end

  def apply_fix_in_place(file_path, original, fixed)
    return false if fixed.nil? || fixed.empty? || fixed == original

    # Create backup before modifying
    backup_path = "#{file_path}.bak.#{Time.now.to_i}"
    File.write(backup_path, original)
    Log.info("Backup: #{backup_path}")

    # Write fixed code
    File.write(file_path, fixed)
    Log.ok("Fixed in-place: #{file_path}")

    true
  rescue => e
    Log.error("Failed to apply fix: #{e.message}")
    false
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

  # Source abbreviations for display
  SOURCE_ABBREV = {
    "clean_code" => "CC",
    "fowler" => "MF",
    "poodr" => "SM",
    "pragmatic" => "PP",
    "unix" => "BSD"
  }.freeze

  def show_final_report(file_path)
    violations = scan_with_llm(file_path)
    analysis = Core::ScoreCalculator.analyze(violations)

    if violations.empty?
      puts "  #{Dmesg.green}ok#{Dmesg.reset}"
    else
      puts "  #{Dmesg.yellow}#{analysis[:score]}/100#{Dmesg.reset} (#{analysis[:total]})"
      violations.first(3).each do |v|
        src = SOURCE_ABBREV[v["source"]] || "?"
        puts "    #{Dmesg.dim}[#{src}]#{Dmesg.reset} :#{v["line"]} #{v["explanation"][0..45]}"
      end
      puts "    +#{violations.size - 3}" if violations.size > 3
    end

    # Trace mode: full transparency
    if ENV["TRACE"]
      stats = @llm.stats if @llm.enabled?
      puts "  #{Dmesg.dim}[trace] model=#{@llm&.current_model} tokens=#{stats&.dig(:tokens)} cost=$#{format("%.4f", stats&.dig(:cost) || 0)}#{Dmesg.reset}"
      content = File.read(file_path) rescue ""
      puts "  #{Dmesg.dim}[trace] cache_key=#{Core::Cache.key_for(file_path, content)}#{Dmesg.reset}"
      # Show source breakdown
      by_source = violations.group_by { |v| v["source"] }
      breakdown = by_source.map { |s, vs| "#{SOURCE_ABBREV[s] || s}:#{vs.size}" }.join(" ")
      puts "  #{Dmesg.dim}[trace] sources: #{breakdown}#{Dmesg.reset}" unless breakdown.empty?
    end
  end
end

class LanguageAsker
  def self.ask(file_path, constitution)
    puts "lang? #{File.basename(file_path)}"
    supported = constitution.language_detection["supported"]
    supported.each_with_index do |(lang, _), i|
      puts "  #{i + 1}. #{lang}"
    end
    print "> "
    input = $stdin.gets&.strip&.to_i
    if input >= 1 && input <= supported.size
      supported.keys[input - 1]
    else
      "unknown"
    end
  end
end

class CLI
  def initialize
    @constitution = Constitution.load
    @constitution.set_profile(Options.profile)
    @llm = LLMClient.new(@constitution)
    @engine = AutoEngine.new(@constitution, @llm)
    @results = []
    @status = StatusLine.new
    @session = Session.new
    @plan = nil
    @tiered = TieredLLM.new(@constitution) if @constitution
    @web_server = nil
  rescue => e
    Log.warn("Init warning: #{e.message}")
    @constitution ||= nil
    @llm ||= nil
    @engine ||= nil
    @results = []
    @status = StatusLine.new
    @session = Session.new
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
      puts "master.yml LLM OS v#{Dmesg::VERSION}" unless Options.quiet
    when "--cost"
      show_cost
    when "--rollback"
      rollback(args[1])
    when "--garden"
      run_gardener(:quick)
    when "--garden-full"
      run_gardener(:full)
    when "--shell", "-s", "--chat"
      shell_mode
    when "--ask"
      quick_ask(args[1..-1].join(" "))
    when "--session"
      manage_session(args[1], args[2])
    when "--complete"
      systematic_complete(args[1..-1])
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

  # Systematic file completion - analyzes gaps, creates plan, executes
  def systematic_complete(targets)
    targets = ["."] if targets.empty?
    @status.set("Scanning project structure")

    files = []
    targets.each do |t|
      if File.directory?(t)
        files += Dir.glob(File.join(t, "**/*.{rb,sh,yml,md,html,js,css}"))
      elsif File.exist?(t)
        files << t
      end
    end
    files = filter_ignored(files)

    return Log.warn("No files found") if files.empty?

    # Phase 1: Analyze what exists
    @status.set("Analyzing #{files.size} files")
    analysis = analyze_project_completeness(files)

    # Phase 2: Create plan
    @status.set("Creating completion plan")
    @plan = create_completion_plan(analysis)
    puts @plan.to_s
    puts

    print "Execute plan? (y/n) "
    return unless $stdin.gets&.strip&.downcase == "y"

    # Phase 3: Execute systematically
    @plan.tasks.each_with_index do |task, idx|
      @status.progress(idx + 1, @plan.tasks.size, task[:desc])
      execute_completion_task(task, idx)
      @plan.complete_task(idx)
      @session.plan = @plan.to_h
      @session.save
    end

    @status.clear
    Log.ok("Completion finished: #{@plan.progress}%")
  end

  def analyze_project_completeness(files)
    analysis = {
      files: files,
      incomplete: [],
      missing_docs: [],
      missing_tests: [],
      stub_functions: [],
      todos: [],
      errors: []
    }

    files.each_with_index do |file, idx|
      @status.progress(idx + 1, files.size, File.basename(file))
      content = Core.read_file(file)
      next if content.nil? || content.empty?

      # Detect incomplete markers
      if content.match?(/TODO|FIXME|XXX|HACK|WIP|INCOMPLETE/i)
        todos = content.lines.each_with_index.select { |l, _| l.match?(/TODO|FIXME|XXX|HACK|WIP/i) }
        analysis[:todos] += todos.map { |l, n| { file: file, line: n + 1, text: l.strip } }
      end

      # Detect stub functions (empty or raise NotImplementedError)
      if content.match?(/raise\s+NotImplementedError|pass\s*$|\.\.\.$/m)
        analysis[:stub_functions] << file
      end

      # Detect missing docs for Ruby/Python
      if file.end_with?(".rb", ".py")
        if !content.match?(/^#\s*@|^"""|^'''|^# frozen_string_literal/)
          analysis[:missing_docs] << file
        end
      end

      # Detect syntax errors
      if file.end_with?(".rb")
        result = `ruby -c "#{file}" 2>&1`
        analysis[:errors] << { file: file, error: result } unless $?.success?
      end
    end

    # Check for missing test files
    files.select { |f| f.end_with?(".rb") && !f.include?("_test") && !f.include?("_spec") }.each do |f|
      test_file = f.sub(".rb", "_test.rb")
      spec_file = f.sub(".rb", "_spec.rb")
      unless files.include?(test_file) || files.include?(spec_file) || File.exist?(test_file) || File.exist?(spec_file)
        analysis[:missing_tests] << f
      end
    end

    analysis
  end

  def create_completion_plan(analysis)
    plan = Plan.new("Complete project to production-ready state")

    # Priority 1: Fix errors
    if analysis[:errors].any?
      plan.add_task("Fix syntax errors", analysis[:errors].map { |e| "#{e[:file]}: #{e[:error].lines.first}" })
    end

    # Priority 2: Complete stub functions
    if analysis[:stub_functions].any?
      plan.add_task("Implement stub functions", analysis[:stub_functions].first(10))
    end

    # Priority 3: Address TODOs
    if analysis[:todos].any?
      grouped = analysis[:todos].group_by { |t| t[:file] }
      grouped.first(10).each do |file, todos|
        plan.add_task("Complete TODOs in #{File.basename(file)}", todos.map { |t| "L#{t[:line]}: #{t[:text][0..60]}" })
      end
    end

    # Priority 4: Add missing tests
    if analysis[:missing_tests].any?
      plan.add_task("Add test coverage", analysis[:missing_tests].first(5).map { |f| "Test for #{File.basename(f)}" })
    end

    # Priority 5: Add documentation
    if analysis[:missing_docs].any?
      plan.add_task("Add documentation", analysis[:missing_docs].first(5).map { |f| "Document #{File.basename(f)}" })
    end

    plan.notes << "#{analysis[:files].size} files analyzed"
    plan.notes << "#{analysis[:todos].size} TODOs found" if analysis[:todos].any?
    plan.notes << "#{analysis[:errors].size} syntax errors" if analysis[:errors].any?

    plan
  end

  def execute_completion_task(task, task_idx)
    return if task[:done]

    puts
    puts "Task #{task_idx + 1}: #{task[:desc]}"

    task[:subtasks]&.each_with_index do |sub, sub_idx|
      next if sub[:done]

      @status.set("Working on: #{sub[:desc][0..40]}")

      # Use LLM to help complete the task
      if sub[:desc].include?(".rb") || sub[:desc].include?(".py")
        match = sub[:desc].match(/[\w\/\.\-_]+\.(rb|py|sh|js)/)
        file = match ? match[0] : nil
        if file && File.exist?(file)
          complete_file_task(file, sub[:desc])
        end
      end

      @plan.complete_subtask(task_idx, sub_idx)
    end
  end

  def complete_file_task(file, task_desc)
    content = Core.read_file(file)
    return unless content

    prompt = <<~PROMPT
      Task: #{task_desc}

      File: #{file}
      Content:
      ```
      #{content[0..4000]}
      ```

      Provide the completed/fixed code. Return ONLY the code, no explanations.
      If the task is about TODOs, implement what the TODO describes.
      If the task is about stubs, implement the function logic.
      If the task is about docs, add appropriate documentation.
    PROMPT

    print "  Completing #{File.basename(file)}... "

    response = @tiered&.ask_tier("code", prompt)

    if response && response.length > 100
      # Extract code from response
      code = response.match(/```\w*\n(.+?)```/m)&.[](1) || response

      print "Apply changes? (y/n) "
      if $stdin.gets&.strip&.downcase == "y"
        Core.write_file(file, code, backup: true)
        Log.ok("Updated")
      else
        puts "Skipped"
      end
    else
      puts "No changes suggested"
    end
  end

  def manage_session(cmd, arg = nil)
    case cmd
    when "save"
      path = @session.save
      Log.ok("Session saved: #{path}")
    when "load"
      if arg
        loaded = Session.load(arg)
        if loaded
          @session = loaded
          @chat_history = loaded.history
          @plan = Plan.from_h(loaded.plan) if loaded.plan
          Log.ok("Session loaded: #{arg}")
        else
          Log.warn("Session not found: #{arg}")
        end
      else
        sessions = Session.list
        if sessions.empty?
          puts "No saved sessions"
        else
          puts "Available sessions:"
          sessions.first(10).each { |s| puts "  #{s}" }
        end
      end
    when "list"
      Session.list.each { |s| puts s }
    when "checkpoint"
      @session.checkpoint(arg)
      Log.ok("Checkpoint saved")
    else
      puts "Usage: --session save|load|list|checkpoint [name]"
    end
  end

  def run_gardener(mode)
    tiered = TieredLLM.new(@constitution)
    gardener = Gardener.new(@constitution, tiered)

    result = case mode
    when :quick
      puts "#{Dmesg.icon(:garden)} Running quick garden (reviewing learned smells)..."
      gardener.run_quick
    when :full
      puts "#{Dmesg.icon(:tree)} Running full garden (analyzing painful cases)..."
      gardener.run_full
    end

    puts
    puts result || "No suggestions."
    puts
    puts "Review and manually apply to master.yml if appropriate."
  end

  def shell_mode
    puts "#{Dmesg.icon(:shell)} Starting Shell Assistant..."
    puts "Natural language sysadmin for OpenBSD. Type 'help' for commands."
    puts
    Shell::REPL.new(@constitution).run
  end

  def quick_ask(question)
    return puts "Usage: ruby cli.rb --ask 'your question'" if question.empty?

    assistant = Shell::Assistant.new(@constitution)
    result = assistant.chat(question)

    puts result[:reply]

    if result[:commands].any?
      puts
      result[:commands].each do |cmd|
        print "Execute '#{cmd}'? (y/n/doas) "
        confirm = gets&.chomp&.downcase
        case confirm
        when "y", "yes"
          exec_result = assistant.execute(cmd)
          puts exec_result[:output]
        when "doas", "d"
          exec_result = assistant.execute(cmd, use_doas: true)
          puts exec_result[:output]
        end
      end
    end
  end

  def parse_flags!(args)
    Options.quiet = args.delete("--quiet") || args.delete("-q")
    Options.json = args.delete("--json")
    Options.git_changed = args.delete("--git-changed") || args.delete("-g")
    Options.watch = args.delete("--watch") || args.delete("-w")
    Options.no_cache = args.delete("--no-cache")
    Options.parallel = !args.delete("--no-parallel")
    Options.force = args.delete("--force") || args.delete("-f")

    # Profile handling
    if args.delete("--quick")
      Options.profile = "quick"
    elsif (idx = args.index("--profile"))
      Options.profile = args.delete_at(idx + 1)
      args.delete_at(idx)
    end
  end

  def watch_mode(targets)
    files = expand_targets(targets)

    Core::FileWatcher.watch(files) do |changed_file|
      Log.info("Changed: #{changed_file}")
      process_file(changed_file)
    end
  end

  def process_targets(targets)
    # Tree: show directory structure before entering
    targets.each do |t|
      if File.directory?(t)
        Log.info("#{Dmesg.icon(:folder)} Entering: #{t}") unless Options.quiet
        Core::TreeWalk.print_tree(t).first(20).each { |e| puts "  #{e}" } unless Options.quiet
        puts "  ..." if Core::TreeWalk.print_tree(t).size > 20 && !Options.quiet
      end
    end

    files = expand_targets(targets)

    # Auto git-changed filter if in git repo and many files
    if files.size > 10 && File.exist?(".git") && !Options.force
      changed = `git diff --name-only HEAD 2>/dev/null`.split("\n").map { |f| File.expand_path(f) }
      staged = `git diff --cached --name-only 2>/dev/null`.split("\n").map { |f| File.expand_path(f) }
      git_files = (changed + staged).uniq & files
      if git_files.any? && git_files.size < files.size
        puts "#{Dmesg.dim}git: #{git_files.size}/#{files.size} changed#{Dmesg.reset}"
        files = git_files
      end
    end

    if files.empty?
      Log.error("No files found") unless Options.quiet
      return
    end

    # Parallel processing if enabled and multiple files
    if Options.parallel && files.size > 1 && CONCURRENT_AVAILABLE
      process_files_parallel(files)
    else
      files.each_with_index do |file, idx|
        result = process_file(file)
        @results << result if result
      end
    end

    show_summary(files.size) unless Options.quiet || Options.json
  end

  def process_files_parallel(files)
    pool = Concurrent::FixedThreadPool.new([4, files.size].min)
    futures = files.map do |file|
      Concurrent::Future.execute(executor: pool) { process_file(file) }
    end
    futures.each { |f| @results << f.value if f.value }
    pool.shutdown
    pool.wait_for_termination
  end

  def expand_targets(targets)
    files = []

    targets.each do |target|
      # Expand relative paths
      expanded = File.expand_path(target)

      if File.directory?(expanded)
        files.concat(find_files_in_dir(expanded))
      elsif target.include?("*")
        files.concat(Dir.glob(target))
      elsif File.exist?(expanded)
        files << expanded
      else
        Log.debug("Target not found: #{target} (expanded: #{expanded})") if ENV["VERBOSE"]
      end
    end

    files = filter_git_changed(files) if Options.git_changed
    files.uniq.select { |f| supported_file?(f) }
  end

  def find_files_in_dir(dir)
    dir = File.expand_path(dir)
    return [] unless Dir.exist?(dir)

    extensions = @constitution.language_detection["supported"].values.flat_map { |v| v["extensions"] }

    files = []
    extensions.each do |ext|
      pattern = File.join(dir, "**", "*#{ext}")
      files.concat(Dir.glob(pattern))
    end

    Log.debug("find_files_in_dir(#{dir}): found #{files.size} files") if ENV["VERBOSE"]
    files
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
    @cwd = Dir.pwd
    @last_action = Time.now
    start_time = Time.now

    # Start web server for cli.html
    web_url = nil
    begin
      @web_server = WebServer.new(self)
      web_url = @web_server.start
    rescue => e
      puts "  [trace] web.fail #{e.message}" if ENV["TRACE"]
    end

    # Boot output
    if ENV["TRACE"]
      puts "[trace] boot cwd=#{@cwd}"
      puts "[trace] boot constitution=#{@constitution&.principles&.size}p"
      puts "[trace] boot llm=#{@llm&.enabled? ? 'ready' : 'disabled'}"
      puts "[trace] boot tiers=#{@constitution&.models&.keys&.join('|')}"
      puts "[trace] boot time=#{format("%.2fs", Time.now - start_time)}"
    end
    puts "#{web_url}" if web_url

    # First launch hint
    @empty_count = 0

    # Main loop
    loop do
      input = read_input

      break if input.nil?

      if input.empty?
        @empty_count += 1
        puts "try: help, ls, <file>, or rep img <prompt>" if @empty_count == 2
        next
      end
      @empty_count = 0

      @last_action = Time.now

      case input.downcase.strip
      when "quit", "exit", "q"
        @web_server&.stop
        @session.save
        puts "saved"
        break
      when "all", "."
        process_cwd_recursive
      when "help", "h", "?"
        interactive_help
      when "cost"
        show_cost
      when "trace"
        ENV["TRACE"] = ENV["TRACE"] ? nil : "1"
        puts ENV["TRACE"] ? "on" : "off"
      when "debug", "llm"
        puts "llm: #{@llm&.enabled? ? 'ok' : 'no'} key: #{ENV['OPENROUTER_API_KEY'] ? 'set' : 'no'}"
      when "sprawl", "analyze"
        show_sprawl_report
      when "clean"
        run_clean_only
      when "pwd"
        puts Dir.pwd
      when "status"
        show_status
      when "ls", "dir"
        shell_ls(".")
      when /^ls\s+(.+)/, /^dir\s+(.+)/
        shell_ls($1)
      when /^cd\s+(.+)/
        shell_cd($1)
      when /^cat\s+(.+)/, /^view\s+(.+)/, /^see\s+(.+)/, /^show\s+(.+)/, /^read\s+(.+)/
        shell_cat($1)
      when /^tree\s*(.*)$/
        shell_tree($1.empty? ? "." : $1)
      when /^rollback\s+(.+)/, /^undo\s+(.+)/
        rollback($1)
      when "undo"
        if @last_modified_file
          rollback(@last_modified_file)
        else
          puts "nothing to undo"
        end
      when /^(scan|check|analyze|process)\s+(.+)/i
        files = $2.split(/\s+and\s+|\s*,\s*|\s+/).map(&:strip).reject(&:empty?)
        process_targets(files)
      when /^fix\s+(.+)/i
        files = $1.split(/\s+and\s+|\s*,\s*|\s+/).map(&:strip).reject(&:empty?)
        print "apply fixes to #{files.size} file(s)? [y/N] "
        if $stdin.gets&.strip&.downcase == "y"
          process_targets(files, auto_fix: true)
        else
          puts "cancelled"
        end
      when /^run\s+(.+)/i, /^exec\s+(.+)/i, /^!\s*(.+)/
        run_shell_command($1)
      when /^structural\s+(.+)/i
        run_structural_analysis($1.strip)
      when /^plan\s+(.+)/i
        plan_mode($1.strip)
      when /^complete\s*(.*)$/i
        systematic_complete($1.empty? ? ["."] : [$1.strip])
      when /^autopilot\s*(.*)$/i, /^auto\s*(.*)$/i
        autopilot_mode($1.empty? ? "." : $1.strip)
      when /^replicate\s+(.+)/i, /^rep\s+(.+)/i
        run_replicate($1.strip)
      when /^research\s+(.+)/i
        result = research($1.strip)
        puts result if result
      when /^session\s+(.+)/i
        parts = $1.split
        manage_session(parts[0], parts[1])
      when "session"
        manage_session("list")
      when "plan"
        if @plan
          puts @plan.to_s
        else
          puts "No active plan. Use: plan <task description>"
        end
      else
        # Check if it looks like a file path or conversation
        if looks_like_path?(input)
          process_targets([input])
        else
          chat_response(input)
        end
      end

      puts
    end
  end

  # Autopilot: continuous autonomous completion until done
  def autopilot_mode(path)
    puts "Working on: #{path}"
    puts

    @autopilot = true
    @stuck_count = 0
    iteration = 0
    max_iterations = 500
    last_issue_count = nil
    plateau_count = 0

    trap("INT") { @autopilot = false; puts "\nStopped." }

    while @autopilot && iteration < max_iterations
      iteration += 1
      @status.set("#{iteration}")

      # Analyze current state
      analysis = analyze_project_completeness(find_project_files(path))

      # Check if done
      total_issues = analysis[:todos].size + analysis[:stub_functions].size + analysis[:errors].size
      if total_issues == 0
        # Look for missing features or improvements
        suggestions = find_improvements(path)
        if suggestions.empty?
          Log.ok("Complete.")
          break
        else
          # Work on improvements
          work_on_improvement(suggestions.first)
          next
        end
      end

      # Diminishing returns detection
      if last_issue_count && total_issues >= last_issue_count
        plateau_count += 1
        if plateau_count >= 5
          Log.warn("Diminishing returns (#{total_issues} issues, no progress in 5 iterations)")
          print "Continue? (y/n) "
          answer = $stdin.gets&.strip&.downcase
          break unless answer == 'y'
          plateau_count = 0
        end
      else
        plateau_count = 0
      end
      last_issue_count = total_issues

      # Brief status
      puts "#{iteration}: #{total_issues} remaining" if iteration % 5 == 1

      # Pick highest priority issue and fix it
      success = false
      if analysis[:errors].any?
        success = fix_error(analysis[:errors].first)
      elsif analysis[:stub_functions].any?
        success = implement_stub(analysis[:stub_functions].first)
      elsif analysis[:todos].any?
        success = complete_todo(analysis[:todos].first)
      end

      # Track if we're stuck
      if success
        @stuck_count = 0
      else
        @stuck_count += 1
        if @stuck_count >= 3
          # Ask user for help
          answer = ask_user_for_help(analysis)
          if answer
            @stuck_count = 0
          else
            Log.warn("Stuck. Moving to next issue.")
            rotate_issues(analysis)
          end
        end
      end

      # Brief pause
      sleep 0.5
      @session.save
    end

    @status.clear
    puts "Done. #{iteration} iterations."
  end

  def find_improvements(path)
    # Ask LLM what's missing
    files = find_project_files(path).first(20)
    file_list = files.map { |f| File.basename(f) }.join(", ")

    prompt = <<~P
      Project files: #{file_list}

      What features or improvements are missing? List up to 3 concrete items.
      Format: one per line, actionable tasks.
      If project looks complete, respond with: COMPLETE
    P

    response = @tiered&.ask_tier("fast", prompt)
    return [] if response.nil? || response.include?("COMPLETE")

    response.lines.map(&:strip).reject(&:empty?).first(3)
  end

  def work_on_improvement(suggestion)
    puts "Improving: #{suggestion[0..50]}"

    prompt = <<~P
      Implement this improvement: #{suggestion}

      Current directory: #{Dir.pwd}
      Files: #{find_project_files(".").first(10).map { |f| File.basename(f) }.join(", ")}

      Respond with:
      EDIT> filename
      <content>
      END>

      Or CREATE> filename for new files.
    P

    response = @tiered&.ask_tier("code", prompt)
    execute_chat_action(response) if response
  end

  def ask_user_for_help(analysis)
    issue = analysis[:errors].first || analysis[:stub_functions].first || analysis[:todos].first
    return nil unless issue

    desc = issue.is_a?(Hash) ? (issue[:text] || issue[:error] || issue[:file]) : issue

    puts
    print "Stuck on: #{desc[0..60]}. Hint? "
    answer = $stdin.gets&.strip

    return nil if answer.nil? || answer.empty?

    # Use hint to help fix
    prompt = <<~P
      User hint: #{answer}
      Issue: #{desc}
      File: #{issue[:file] rescue issue}

      Apply the hint to fix this. Return the fix.
    P

    response = @tiered&.ask_tier("code", prompt)
    execute_chat_action(response) if response
    true
  end

  def rotate_issues(analysis)
    # Move first issue to end (handled via array rotation in next iteration)
    # Just mark this one as attempted
    @attempted_issues ||= Set.new
    issue = analysis[:errors].first || analysis[:stub_functions].first || analysis[:todos].first
    @attempted_issues << (issue[:file] rescue issue) if issue
  end

  def find_project_files(path)
    files = Dir.glob(File.join(path, "**/*.{rb,py,js,ts,sh,yml,html,css,md}"))
    filter_ignored(files).reject { |f| @attempted_issues&.include?(f) }
  end

  def fix_error(error)
    file = error[:file]
    puts "Fixing: #{File.basename(file)}"

    content = Core.read_file(file)
    return false unless content

    prompt = <<~P
      Fix the syntax error in this file:
      Error: #{error[:error]}

      File: #{file}
      #{content[0..3000]}

      Return ONLY the corrected code, no explanation.
    P

    response = @tiered&.ask_tier("code", prompt)
    if response && response.length > 50
      Core.write_file(file, response, backup: true)
      Log.ok("Fixed")
      true
    else
      false
    end
  end

  def implement_stub(file)
    puts "Implementing: #{File.basename(file)}"

    content = Core.read_file(file)
    return false unless content

    prompt = <<~P
      Implement all stub/placeholder functions in this file.
      Replace `raise NotImplementedError`, `pass`, or `...` with working code.

      File: #{file}
      #{content[0..3000]}

      Return ONLY the complete file with implementations, no explanation.
    P

    response = @tiered&.ask_tier("code", prompt)
    if response && response.length > content.length * 0.5
      Core.write_file(file, response, backup: true)
      Log.ok("Implemented")
      true
    else
      false
    end
  end

  def complete_todo(todo)
    file = todo[:file]
    puts "TODO: #{todo[:text][0..40]}"

    content = Core.read_file(file)
    return false unless content

    prompt = <<~P
      Complete this TODO in the file:
      TODO at line #{todo[:line]}: #{todo[:text]}

      File: #{file}
      #{content[0..3000]}

      Return ONLY the complete file with the TODO implemented (remove the TODO comment), no explanation.
    P

    response = @tiered&.ask_tier("code", prompt)
    if response && response.length > content.length * 0.5
      Core.write_file(file, response, backup: true)
      Log.ok("Done")
      true
    else
      false
    end
  end

  # Smart research: expands keywords, tries related concepts
  def research(topic)
    puts "Researching: #{topic}"

    # First, expand the topic into related keywords
    expansion_prompt = <<~P
      Topic: #{topic}

      Generate 5 related search queries that would help implement this.
      Think laterally: related algorithms, similar problems, adjacent concepts.
      Examples: if topic is "graph visualization", also search "force-directed layout", "d3.js network", "adjacency matrix rendering"

      Return one query per line, no numbering.
    P

    expansions = @tiered&.ask_tier("fast", expansion_prompt)
    queries = [topic]
    queries += expansions.lines.map(&:strip).reject(&:empty?).first(5) if expansions

    results = []
    queries.each do |query|
      # Try web search (if available) or use LLM knowledge
      result = search_or_infer(query)
      results << { query: query, result: result } if result
    end

    # Synthesize findings
    if results.any?
      synthesis_prompt = <<~P
        Research findings on: #{topic}

        #{results.map { |r| "Query: #{r[:query]}\nResult: #{r[:result][0..500]}" }.join("\n\n")}

        Synthesize into actionable implementation guidance. Be specific about code patterns, libraries, approaches.
      P

      @tiered&.ask_tier("medium", synthesis_prompt)
    else
      nil
    end
  end

  def search_or_infer(query)
    # Try curl to a search API if available, otherwise use LLM inference
    # For now, use LLM knowledge as fallback
    prompt = <<~P
      Search query: #{query}

      Provide the most relevant technical information for implementing this.
      Include: libraries, code patterns, gotchas, best practices.
      Be specific and actionable.
    P

    @tiered&.ask_tier("fast", prompt)
  end

  def research_and_implement(issue, context = "")
    # Research first, then implement
    research_result = research(issue)

    if research_result
      prompt = <<~P
        Task: #{issue}
        Context: #{context}

        Research findings:
        #{research_result[0..2000]}

        Now implement this. Return code only.
      P

      @tiered&.ask_tier("code", prompt)
    else
      # Fallback: ask user
      puts "No research results. Need help with: #{issue[0..50]}"
      print "Hint? "
      hint = $stdin.gets&.strip
      return nil if hint.nil? || hint.empty?

      @tiered&.ask_tier("code", "Implement #{issue} using hint: #{hint}")
    end
  end

  # Replicate.com integration
  def run_replicate(args)
    unless ENV["REPLICATE_API_TOKEN"]
      Log.warn("set REPLICATE_API_TOKEN")
      return
    end

    # Parse command
    parts = args.split(/\s+/, 2)
    cmd = parts[0]
    prompt = parts[1] || ""

    case cmd
    when "img", "image", "gen"
      replicate_generate(prompt)
    when "vid", "video"
      replicate_video(prompt)
    when "audio", "music", "sound"
      replicate_audio(prompt)
    when "tts", "speech", "say"
      replicate_tts(prompt)
    when "chain"
      replicate_chain(prompt)
    when "wild"
      replicate_wild(prompt)
    when "search"
      replicate_search(prompt)
    when "styles"
      puts "Styles: #{Replicate::STYLES.keys.join(', ')}"
      puts "Usage: rep img +photo cyberpunk city"
    when "templates"
      puts "Templates:"
      Replicate::TEMPLATES.each { |k, v| puts "  #{k}: #{v[0..60]}..." }
    when "help", "?"
      puts "rep img <prompt>     image (nano-banana-pro)"
      puts "rep vid <prompt>     video (veo-3.1 w/ audio)"
      puts "rep audio <prompt>   music (elevenlabs)"
      puts "rep tts <text>       speech (qwen3-tts)"
      puts "rep wild <prompt>    random chain"
      puts "rep styles           list +style suffixes"
      puts "rep templates        list @template prefixes"
      puts "@portrait @product @cinematic @anime  templates"
      puts "+photo +film +neon +minimal +vintage  styles"
    else
      puts "try: rep img, vid, audio, tts, wild, styles"
    end
  end

  def replicate_api(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV['REPLICATE_API_TOKEN']}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  rescue => e
    Log.warn("Replicate API: #{e.message}")
    nil
  end

  def replicate_wait(id, name = "Task")
    print "#{name}..."
    loop do
      sleep 2
      res = replicate_api(:get, "/predictions/#{id}")
      return nil unless res

      data = JSON.parse(res.body)
      case data["status"]
      when "succeeded"
        puts " done"
        output = data["output"]
        return output.is_a?(Array) ? output.first : output
      when "failed"
        puts " failed: #{data['error']}"
        return nil
      else
        print "."
      end
    end
  end

  def replicate_generate(prompt)
    return Log.warn("No prompt") if prompt.empty?

    # Apply style suffix if +style present
    final_prompt = apply_replicate_styles(prompt)
    puts "Generating: #{final_prompt[0..60]}..."

    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:img],
      input: { prompt: final_prompt, num_outputs: 1 }
    })

    return unless res
    data = JSON.parse(res.body)

    url = replicate_wait(data["id"], "Image")
    if url
      filename = "gen_#{Time.now.strftime('%H%M%S')}.webp"
      download_file(url, filename)
      Log.ok("Saved: #{filename}")
    end
  end

  def replicate_video(prompt)
    return Log.warn("No prompt") if prompt.empty?

    final_prompt = apply_replicate_styles(prompt)

    # Veo 3.1 generates video with audio directly from text
    puts "Generating video+audio: #{final_prompt[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:vid],
      input: { prompt: final_prompt, duration: 5, aspect_ratio: "16:9" }
    })
    return unless res

    vid_url = replicate_wait(JSON.parse(res.body)["id"], "Video")
    if vid_url
      filename = "vid_#{Time.now.strftime('%H%M%S')}.mp4"
      download_file(vid_url, filename)
      Log.ok("Saved: #{filename}")
    end
  end

  def apply_replicate_styles(prompt)
    result = prompt.dup
    
    # Apply @template prefix (e.g., @portrait, @cinematic)
    Replicate::TEMPLATES.each do |key, template|
      if result.include?("@#{key}")
        result.gsub!("@#{key}", "")
        result = "#{result.strip}, #{template}"
      end
    end
    
    # Apply +style suffix (e.g., +photo, +film)
    Replicate::STYLES.each do |key, suffix|
      if result.include?("+#{key}")
        result.gsub!("+#{key}", "")
        result += suffix
      end
    end
    result.strip
  end

  def replicate_chain(prompt)
    # Use repligen.rb directly
    system("ruby", File.join(File.dirname(__FILE__), "repligen.rb"), "chain", prompt)
  end

  def replicate_wild(prompt)
    system("ruby", File.join(File.dirname(__FILE__), "repligen.rb"), "wild", prompt)
  end

  def replicate_search(query)
    system("ruby", File.join(File.dirname(__FILE__), "repligen.rb"), "search", query)
  end

  def replicate_audio(prompt)
    return Log.warn("no prompt") if prompt.empty?

    puts "Generating music: #{prompt[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:music],
      input: { prompt: prompt, duration: 30 }
    })
    return unless res

    url = replicate_wait(JSON.parse(res.body)["id"], "Music")
    if url
      filename = "music_#{Time.now.strftime('%H%M%S')}.mp3"
      download_file(url, filename)
      Log.ok("Saved: #{filename}")
    end
  end

  def replicate_tts(text)
    return Log.warn("no text") if text.empty?

    puts "Generating speech: #{text[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:tts],
      input: { text: text }
    })
    return unless res

    url = replicate_wait(JSON.parse(res.body)["id"], "Speech")
    if url
      filename = "speech_#{Time.now.strftime('%H%M%S')}.wav"
      download_file(url, filename)
      Log.ok("Saved: #{filename}")
    end
  end

  def download_file(url, filename)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      resp = http.get(uri.request_uri)
      File.binwrite(filename, resp.body)
    end
  rescue => e
    Log.warn("Download failed: #{e.message}")
  end

  def interactive_help
    puts <<~HELP
      ls cd pwd tree cat    navigation
      <path>                analyze
      rep img <prompt>      image generation
      rep vid <prompt>      video generation
      rep audio <prompt>    music/sound
      rep tts <text>        text-to-speech
      rep wild <prompt> N   N random effects chain
      sprawl clean          project
      plan complete         tasks
      session save/load     state
      run ! <cmd>           shell
      cost trace status     info
      quit                  exit
    HELP
  end

  def show_status
    puts "session: #{@session.name} msgs: #{@chat_history&.size || 0}"
    puts "plan: #{@plan ? "#{@plan.goal} #{@plan.progress}%" : 'none'}"
    if @llm&.enabled?
      s = @llm.stats
      puts "llm: #{s[:calls]}c #{s[:tokens]}t $#{format('%.4f', s[:cost])}"
    end
  end

  def looks_like_path?(input)
    # File paths: start with ./ or /, contain file extensions, or are single words with no spaces
    return true if input.match?(%r{^[./~]})
    return true if input.match?(/\.\w+$/)
    return true if input.match?(/^[\w\-_.]+$/) && (File.exist?(input) || Dir.exist?(input))
    return true if input.include?("*") # glob
    false
  end

  def chat_response(input)
    unless @llm
      Log.warn("LLM not available. Set OPENROUTER_API_KEY for chat.")
      return
    end

    # Plan mode detection
    if input.match?(/^plan\s+/i)
      return plan_mode(input.sub(/^plan\s+/i, ""))
    end

    @chat_history ||= []
    @chat_history << { role: "user", content: input }
    @session.history = @chat_history

    # Build context
    context = <<~CTX
      Current directory: #{Dir.pwd}
      Folders: #{Dir.entries('.').select { |e| File.directory?(e) && !e.start_with?('.') }.join(', ')}
      Recent files: #{Dir.glob('*').select { |f| File.file?(f) }.first(10).join(', ')}
    CTX

    # Include current plan if exists
    plan_context = @plan ? "\nCurrent plan:\n#{@plan.to_s}\n" : ""

    # Get directory listing for context
    files = Dir.entries('.').reject { |f| f.start_with?('.') }.first(20).join(', ') rescue ""

    # Trace context for LLM
    trace_info = ENV["TRACE"] ? " TRACE=on" : ""

    system_prompt = <<~SYS
      You run inside cli.rb on OpenBSD vmctl sandbox. All actions are safe.
      You can: ls, cat, tree, scan, analyze, !cmd (shell). No limits apply.
      NEVER hallucinate file contents. Say "run: cat <file>" to see files.
      BE HONEST. If you don't know, say "I don't know" or "I need more context".
      Don't guess. Don't make up answers. Ask clarifying questions if needed.
      Ronin coder. Stoic. Short sentences. No markdown. No code blocks.
      cwd: #{Dir.pwd}#{trace_info}
      files: #{files}
      #{plan_context}
    SYS

    begin
      @status.set("Thinking...")
      @status.spin_start

      # Use streaming for response
      reply = ""

      puts "[DEBUG chat_response] @tiered=#{@tiered.class} enabled=#{@tiered&.enabled? ? 'true' : 'false'}" if ENV["DEBUG"]

      if @tiered&.enabled?
        @status.spin_stop
        puts "[DEBUG: tiered enabled, calling stream]" if ENV["DEBUG"]
        @tiered.ask_tier_stream("medium", @chat_history.last[:content], system_prompt: system_prompt) do |chunk|
          print chunk
          reply += chunk
          $stdout.flush
        end
        puts
        puts "[DEBUG: stream done, reply len=#{reply.length}]" if ENV["DEBUG"]
      else
        puts "[DEBUG: tiered NOT enabled, using fallback]" if ENV["DEBUG"]
        # Fallback to non-streaming
        messages = [{ role: "system", content: system_prompt }]
        messages += @chat_history.last(10)

        response = nil
        llm_thread = Thread.new do
          response = @llm.chat(messages, tier: "medium")
        end

        while llm_thread.alive?
          sleep 0.1
        end
        @status.spin_stop

        llm_thread.join
        reply = response.is_a?(String) ? response : (response&.content || "I understand.")
        puts reply
      end

      reply = "I understand. What would you like me to do?" if reply.nil? || reply.empty?

      @chat_history << { role: "assistant", content: reply }
      @session.history = @chat_history
      @session.save

      @status.clear
      execute_chat_action(reply)

    rescue => e
      @status.spin_stop
      @status.clear
      puts "[DEBUG chat_response ERROR] #{e.class}: #{e.message}" if ENV["DEBUG"]
      puts "[DEBUG backtrace] #{e.backtrace.first(5).join("\n")}" if ENV["DEBUG"]
      Log.debug("Chat error: #{e.message}")
      puts "I understand. What would you like me to do next?"
    end
  end

  # Plan mode - create structured approach before implementation
  def plan_mode(task)
    @status.set("Creating plan...")

    prompt = <<~PROMPT
      Create a detailed implementation plan for: #{task}

      Current directory: #{Dir.pwd}
      Available files: #{Dir.glob('*').first(20).join(', ')}

      Return a structured plan with:
      1. Goal statement (one line)
      2. Numbered tasks (3-7 main tasks)
      3. Each task can have subtasks
      4. Notes about dependencies or risks

      Format:
      GOAL: <goal>
      TASK 1: <description>
        - subtask 1.1
        - subtask 1.2
      TASK 2: <description>
      NOTES:
      - <note>
    PROMPT

    response = @tiered&.ask_tier("medium", prompt)

    if response
      @plan = parse_plan_response(response, task)
      @session.plan = @plan.to_h
      @session.save

      puts
      puts @plan.to_s
      puts
      print "Start execution? (y/n) "
      if $stdin.gets&.strip&.downcase == "y"
        execute_plan
      end
    else
      Log.warn("Could not create plan")
    end

    @status.clear
  end

  def parse_plan_response(response, fallback_goal)
    plan = Plan.new(fallback_goal)

    # Extract goal
    if response.match?(/GOAL:\s*(.+)/i)
      plan = Plan.new($1.strip)
    end

    # Extract tasks
    current_task = nil
    response.lines.each do |line|
      case line
      when /^TASK\s*\d+:\s*(.+)/i
        current_task = { desc: $1.strip, subtasks: [] }
        plan.tasks << { desc: $1.strip, done: false, subtasks: [] }
      when /^\s*-\s*(.+)/
        if plan.tasks.any?
          plan.tasks.last[:subtasks] << { desc: $1.strip, done: false }
        end
      when /^NOTES?:/i
        # Notes section starts
      when /^\s*-\s*(.+)/
        # This might be a note if we're in notes section
      end
    end

    # Extract notes
    if response.match(/NOTES?:\s*(.+)/im)
      notes_section = $1
      notes_section.lines.each do |line|
        if line.match(/^\s*-\s*(.+)/)
          plan.notes << $1.strip
        end
      end
    end

    plan
  end

  def execute_plan
    return Log.warn("No plan to execute") unless @plan

    @plan.tasks.each_with_index do |task, idx|
      next if task[:done]

      @status.progress(idx + 1, @plan.tasks.size, task[:desc][0..40])

      puts
      puts "Executing: #{task[:desc]}"

      task[:subtasks]&.each_with_index do |sub, sub_idx|
        next if sub[:done]
        print "  - #{sub[:desc]}... "

        # Let LLM help execute
        chat_response("Execute: #{sub[:desc]}")

        @plan.complete_subtask(idx, sub_idx)
      end

      @plan.complete_task(idx)
      @session.plan = @plan.to_h
      @session.save
    end

    @status.clear
    Log.ok("Plan complete: #{@plan.progress}%")
  end

  # Files that are safe to auto-edit without confirmation
  AUTONOMOUS_PATTERNS = [
    /\.rb$/, /\.py$/, /\.js$/, /\.ts$/, /\.sh$/, /\.yml$/, /\.yaml$/,
    /\.html$/, /\.css$/, /\.md$/, /\.json$/
  ].freeze

  # Files that always require confirmation
  PROTECTED_FILES = %w[
    /etc/passwd /etc/shadow /etc/pf.conf /etc/rc.conf
    ~/.ssh/authorized_keys ~/.bashrc ~/.zshrc
  ].freeze

  def execute_chat_action(reply)
    # Auto-execute if the AI suggests a specific action
    # Uses plain markers: EDIT>, CREATE>, RUN> (no backticks)
    case reply
    when /EDIT>\s*([^\n]+)\n(.*?)END>/m
      file, content = $1.strip, $2
      apply_edit(file, content)
    when /CREATE>\s*([^\n]+)\n(.*?)END>/m
      file, content = $1.strip, $2
      create_file(file, content)
    when /RUN>\s*(.+)/i
      cmd = $1.strip.sub(/END>.*$/m, "").strip
      auto_run_command(cmd)
    when /ANALYZE:\s*(.+)/i
      process_targets([$1.strip])
    when /STRUCTURAL:\s*(.+)/i
      run_structural_analysis($1.strip)
    when /COMPLETE:\s*(.+)/i
      systematic_complete([$1.strip])
    when /PLAN:\s*(.+)/i
      plan_mode($1.strip)
    end
  end

  def apply_edit(file, content)
    expanded = File.expand_path(file)

    # Check if protected
    if PROTECTED_FILES.any? { |p| expanded.include?(p.gsub("~", ENV["HOME"] || "")) }
      print "Protected file #{file}. Apply edit? (y/n) "
      return unless $stdin.gets&.strip&.downcase == 'y'
    end

    if File.exist?(expanded)
      # Auto-apply for safe file types
      if AUTONOMOUS_PATTERNS.any? { |p| file.match?(p) }
        Core.write_file(expanded, content, backup: true)
        Log.ok("Applied: #{file}")
      else
        print "Apply edit to #{file}? (y/n) "
        if $stdin.gets&.strip&.downcase == 'y'
          Core.write_file(expanded, content, backup: true)
          Log.ok("Updated #{file}")
        end
      end
    else
      # File doesn't exist - create it
      create_file(file, content)
    end
  end

  def create_file(file, content)
    expanded = File.expand_path(file)
    dir = File.dirname(expanded)

    unless Dir.exist?(dir)
      FileUtils.mkdir_p(dir)
      Log.ok("Created directory: #{dir}")
    end

    File.write(expanded, content)
    Log.ok("Created: #{file}")
  end

  def auto_run_command(cmd)
    first_word = cmd.split.first&.split('/')&.last

    # Block dangerous commands
    if DANGEROUS_COMMANDS.include?(first_word)
      Log.warn("Blocked: #{first_word}")
      return
    end

    # Auto-run safe commands
    safe_prefixes = %w[ls cat head tail grep find echo pwd cd mkdir touch git ruby python node npm]
    if safe_prefixes.include?(first_word)
      Log.info("Running: #{cmd}")
      output = `#{cmd} 2>&1`
      puts output unless output.empty?
    else
      print "Run '#{cmd}'? (y/n) "
      if $stdin.gets&.strip&.downcase == 'y'
        output = `#{cmd} 2>&1`
        puts output unless output.empty?
      end
    end
  end

  def run_structural_analysis(path)
    Log.info("Running structural analysis on #{path}...")
    issues = Core::StructuralAnalyzer.full_analysis(path, @constitution)
    if issues.empty?
      Log.ok("No structural issues found")
    else
      Core::StructuralAnalyzer.report(issues)
    end
  end

  DANGEROUS_COMMANDS = %w[rm rmdir dd mkfs fdisk newfs disklabel].freeze

  def run_shell_command(cmd)
    # Safety check for dangerous commands
    first_word = cmd.split.first&.split('/')&.last
    if DANGEROUS_COMMANDS.include?(first_word) && !Options.force
      Log.warn("Blocked dangerous command: #{first_word}")
      Log.info("Use --force flag or prefix with ! to override")
      return
    end

    Log.info("Running: #{cmd}")
    output = `#{cmd} 2>&1`
    puts output unless output.empty?
    Log.ok("Exit: #{$?.exitstatus}") if $?.exitstatus != 0
  rescue => e
    Log.error("Command failed: #{e.message}")
  end

  def shell_ls(path)
    dir = File.expand_path(path)
    unless Dir.exist?(dir)
      Log.warn("Directory not found: #{path}")
      return
    end
    entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
    dirs = entries.select { |e| File.directory?(File.join(dir, e)) }.map { |d| "#{d}/" }
    files = entries.reject { |e| File.directory?(File.join(dir, e)) }
    (dirs + files).each_slice(4) { |row| puts row.map { |e| e.ljust(20) }.join }
  end

  def shell_cd(path)
    target = File.expand_path(path)
    if Dir.exist?(target)
      Dir.chdir(target)
      puts "→ #{Dir.pwd}"
    else
      Log.warn("Directory not found: #{path}")
    end
  end

  def shell_cat(path)
    file = File.expand_path(path)
    if File.exist?(file) && File.file?(file)
      content = File.read(file, encoding: "UTF-8") rescue ""
      lines = content.lines
      lines.first(50).each_with_index { |line, i| puts "#{(i+1).to_s.rjust(4)}  #{line}" }
      puts "... (#{lines.size - 50} more lines)" if lines.size > 50
    else
      Log.warn("File not found: #{path}")
    end
  end

  def shell_tree(path, depth: 2)
    dir = File.expand_path(path)
    unless Dir.exist?(dir)
      Log.warn("Directory not found: #{path}")
      return
    end
    puts dir
    print_tree(dir, "", depth)
  end

  def print_tree(dir, prefix, depth)
    return if depth <= 0
    entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
    entries.each_with_index do |entry, i|
      path = File.join(dir, entry)
      is_last = (i == entries.size - 1)
      connector = is_last ? "└── " : "├── "
      puts "#{prefix}#{connector}#{entry}#{File.directory?(path) ? '/' : ''}"
      if File.directory?(path)
        new_prefix = prefix + (is_last ? "    " : "│   ")
        print_tree(path, new_prefix, depth - 1)
      end
    end
  end

  def handle_natural_language(input)
    case input.downcase
    when /list.*files|show.*files|what files/
      shell_ls(".")
    when /where am i|current dir|pwd/
      puts Dir.pwd
    when /show.*structure|project.*structure|tree/
      shell_tree(".", depth: 3)
    when /what.*can|help|commands/
      usage
    when /how.*many.*files/
      count = Dir.glob("**/*").count { |f| File.file?(f) }
      puts "#{count} files in #{Dir.pwd}"
    when /find\s+(.+)/i, /where.*is\s+(.+)/i
      pattern = $1.strip
      matches = Dir.glob("**/#{pattern}*").first(20)
      matches.any? ? matches.each { |m| puts m } : puts("no match")
    else
      puts "commands: ls cd cat tree all sprawl cost trace quit"
    end
  end

  def show_sprawl_report
    report = Core::ProjectAnalyzer.analyze(".")
    puts "files: #{report[:file_count]}"
    report[:sprawl].each { |i| puts "  #{i[:type]}: #{i[:count]}" } if report[:sprawl].any?
    report[:duplicates].first(3).each { |d| puts "  dup: #{d[:duplicate]}" } if report[:duplicates].any?
    report[:fragmentation].each { |f| puts "  frag: #{f[:message]}" } if report[:fragmentation].any?
  end

  def run_clean_only
    cleaned = Core::ProjectAnalyzer.clean(".", dry_run: Options.dry_run)
    if cleaned.any?
      puts "cleaned: #{cleaned.size}"
    else
      puts "clean"
    end
  end

  def process_cwd_recursive
    # Pre-scan first (tree + clean)
    prescan_result = Core::ProjectAnalyzer.prescan(".", dry_run: Options.dry_run)
    files = prescan_result[:files].reject { |f| f.end_with?("/") }
    files = filter_ignored(files)

    if files.empty?
      Log.warn("No supported files found")
      return
    end

    Log.info("Processing #{files.size} files...")
    puts

    files.each_with_index do |file, idx|
      relative = file.sub("#{Dir.pwd}/", "")
      print "\r#{idx + 1}/#{files.size} #{relative.ljust(60)}"
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

  def build_prompt
    # Pure-style: dir and git on line above, simple > on input line
    parts = []

    # Directory in blue
    dir = Dir.pwd.split('/').last || Dir.pwd
    parts << "#{Dmesg.cyan}#{dir}#{Dmesg.reset}"

    # Git branch in dim
    if File.exist?(".git") || File.exist?("../.git")
      branch = `git branch --show-current 2>/dev/null`.strip rescue ""
      parts << "#{Dmesg.dim}#{branch}#{Dmesg.reset}" unless branch.empty?
    end

    # Print context line, then simple prompt
    puts parts.join(' ') unless parts.empty?
    "#{Dmesg.magenta}>#{Dmesg.reset} "
  end

  def read_input
    prompt = build_prompt
    if READLINE_AVAILABLE
      Readline.readline(prompt, true)&.strip
    else
      print prompt
      $stdin.gets&.strip
    end
  end

  def process_file(file_path)
    start_time = Time.now

    unless File.exist?(file_path)
      Log.error("File not found: #{file_path}") unless Options.quiet
      return nil
    end

    size = File.size(file_path)
    puts "  [trace] file.start path=#{file_path} size=#{size}" if ENV["TRACE"]

    # Clean: normalize file before analysis (CRLF, trailing whitespace, blank lines)
    if Core::FileCleaner.clean(file_path)
      puts "  [trace] file.cleaned path=#{file_path}" if ENV["TRACE"]
    end

    language = detect_language(file_path)
    puts "  [trace] file.lang=#{language}" if ENV["TRACE"]

    result = @engine.process(file_path, language)
    elapsed = Time.now - start_time
    puts "  [trace] file.done time=#{format("%.2fs", elapsed)}" if ENV["TRACE"]

    if result.ok?
      {file: file_path, language: language, score: 100, error: nil}
    else
      Log.error(result.error) unless Options.quiet
      {file: file_path, language: language, score: 0, error: result.error}
    end
  end

  def detect_language(file_path)
    config = @constitution.language_detection
    code = File.read(file_path, encoding: "UTF-8")

    # First try auto-detection
    detected = Core::LanguageDetector.detect_with_fallback(
      file_path,
      code,
      config["supported"]
    )

    # If auto-detected a known language, use it without asking
    return detected if detected != "unknown"

    # In quiet/json mode, return unknown without asking
    return "unknown" if Options.quiet || Options.json

    # Only ask if strategy requires it AND we couldn't auto-detect
    if config["strategy"] == "ask_user_first" && @constitution.defaults["ask_language"]
      return LanguageAsker.ask(file_path, @constitution)
    end

    "unknown"
  end

  def usage
    puts "master.yml LLM OS v#{Dmesg::VERSION}"
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
    puts "  --no-parallel   Disable parallel smell detection"
    puts "  --cost          Show LLM usage stats"
    puts "  --rollback <f>  Restore from backup"
    puts "  --force         Allow dangerous shell commands"
    puts
    puts "Fixing & Refactoring:"
    puts "  --fix, -f       Enable in-place fixing of violations"
    puts "  --dry-run, -n   Show what would be fixed (no changes)"
    puts
    puts "Shell Mode (sysadmin assistant):"
    puts "  --shell, -s     Interactive shell assistant"
    puts "  --chat          Same as --shell"
    puts "  --ask 'query'   One-shot question (with command execution)"
    puts
    puts "Profiles (principle filtering):"
    puts "  --quick         Fast scan with core principles only (5 principles)"
    puts "  --profile NAME  Use named profile (quick, full, axioms_only, solid_focus, critical)"
    puts
    puts "Gardener (self-improving):"
    puts "  --garden        Quick: review learned smells"
    puts "  --garden-full   Full: analyze painful cases, suggest improvements"
    puts
    puts "Interactive commands:"
    puts "  all             Process all files in cwd"
    puts "  sprawl          Show codebase sprawl report"
    puts "  clean           Clean all text files (CRLF, whitespace)"
    puts "  cost            Show LLM usage"
    puts "  quit            Exit"
    puts
    puts "Environment:"
    puts "  OPENROUTER_API_KEY   Required for AI features"
    puts "  VERBOSE=1            Show detailed logs"
    puts
    puts "Examples:"
    puts "  ruby cli.rb                     # Interactive mode"
    puts "  ruby cli.rb . --fix             # Process and fix in-place"
    puts "  ruby cli.rb src/ --fix --dry-run # Preview fixes"
    puts "  ruby cli.rb --quick .           # Fast scan with 5 core principles"
    puts "  ruby cli.rb --shell             # Sysadmin assistant"
    puts "  ruby cli.rb --ask 'check disk'  # Quick question"
    puts "  ruby cli.rb --garden-full       # Self-improve constitution"
  end

  def show_cost
    if @llm.enabled?
      s = @llm.stats
      puts "session: #{s[:calls]}c #{s[:tokens]}t $#{format("%.4f", s[:cost])}"
    end
    daily = Core::CostTracker.daily_totals(7)
    daily.each { |d, x| puts "  #{d}: #{x[:calls]}c $#{format("%.4f", x[:cost])}" } if daily.any?
    total = Core::CostTracker.total_spending
    puts "total: #{total[:calls]}c $#{format("%.4f", total[:cost])}" if total[:calls] > 0
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
  Options.fix = ARGV.include?("--fix") || ARGV.include?("-f")
  Options.dry_run = ARGV.include?("--dry-run") || ARGV.include?("-n")

  Dmesg.boot

  begin
    cli = CLI.new
    cli.run(ARGV)

    # Exit 1 if any files had violations
    if cli.instance_variable_get(:@results)&.any? { |r| r[:score] < 100 }
      exit 1
    end
  rescue StandardError => error
    Log.error("Fatal: #{error.message}") unless Options.quiet
    if ENV["VERBOSE"]
      Log.debug(error.backtrace.first(10).join("\n"))
    else
      Log.info("Run with VERBOSE=1 for stack trace")
    end
    exit 2
  end
end
