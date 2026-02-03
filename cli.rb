#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: UTF-8

# Force UTF-8 on all platforms
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "yaml"
require "json"
require "fileutils"
require "time"
require "set"
require "timeout"

begin
  require "concurrent"
  CONCURRENT_AVAILABLE = true
rescue LoadError
  CONCURRENT_AVAILABLE = false
end

# Auto-install missing gems
module Bootstrap
  GEMS = {
    "ruby_llm" => "ruby_llm",
    "tty-spinner" => "tty-spinner",
    "concurrent-ruby" => "concurrent-ruby"
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
  @parallel = true
  @profile = nil

  class << self
    attr_accessor :quiet, :json, :git_changed, :watch, :no_cache, :parallel, :profile
  end
end

# FUNCTIONAL CORE
# All business logic as pure functions

module Core
  # Skill loader for modular skills system
  module SkillLoader
    SKILLS_DIRS = [
      File.join(Dir.home, ".constitutional", "skills"),
      File.expand_path("skills", __dir__)
    ].freeze

    STAGES = %w[pre-scan detection refactor validate post-process gardening].freeze

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

    def self.find_executable(skill_path)
      %w[.rb .py .sh].each do |ext|
        candidates = Dir.glob(File.join(skill_path, "*#{ext}"))
        return candidates.first if candidates.any?
      end
      nil
    end

    def self.execute_stage(stage, context, skills)
      stage_skills = skills.select { |s| s[:stages].include?(stage) }

      stage_skills.each do |skill|
        next unless skill[:executable]

        Log.info("Running skill: #{skill[:name]} (#{stage})") unless Options.quiet

        execute_skill(skill, context)
      end

      context
    end

    def self.execute_skill(skill, context)
      return unless skill[:executable]

      case File.extname(skill[:executable])
      when ".rb"
        # Load Ruby skill in isolated module (safer than eval in main binding)
        skill_module = Module.new do
          @skill_config = skill
          @context = context

          def self.skill_config = @skill_config
          def self.context = @context
        end

        skill_module.module_eval(File.read(skill[:executable]), skill[:executable], 1)

        if skill_module.respond_to?(:execute)
          skill_module.execute(context)
        end
      else
        Log.debug("Unsupported skill type: #{skill[:executable]}")
      end
    rescue StandardError => e
      Log.warn("Skill #{skill[:name]} failed: #{e.message}")
    end
  end

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

    # Filter principles by profile
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

  module CostEstimator
    # Unified cost estimation for all LLM calls
    RATES = {
      fast: { input: 0.1, output: 0.3 },      # Qwen, Gemma, etc
      medium: { input: 3.0, output: 15.0 },   # Claude Sonnet
      strong: { input: 15.0, output: 75.0 },  # Claude Opus
      gpt4: { input: 2.5, output: 10.0 },     # GPT-4o
      default: { input: 0.5, output: 1.5 }
    }.freeze

    def self.estimate(model, prompt_tokens, completion_tokens)
      rate = rate_for(model)
      (prompt_tokens * rate[:input] / 1_000_000) + (completion_tokens * rate[:output] / 1_000_000)
    end

    def self.rate_for(model)
      case model
      when /qwen|gemma|hermes/i then RATES[:fast]
      when /claude-3.5-sonnet/i then RATES[:medium]
      when /claude-opus|claude-4/i then RATES[:strong]
      when /gpt-4/i then RATES[:gpt4]
      else RATES[:default]
      end
    end
  end

  # Cross-session cost tracking with JSONL persistence
  module CostTracker
    COST_FILE = ".constitutional_costs.jsonl"

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

    def self.key_for(file_path, content)
      require "digest"
      Digest::SHA256.hexdigest("#{file_path}:#{content}")[0, 16]
    end

    def self.get(file_path, content)
      init
      cache_file = File.join(CACHE_DIR, "#{key_for(file_path, content)}.json")
      return nil unless File.exist?(cache_file)

      data = JSON.parse(File.read(cache_file))
      return nil if Time.now.to_i - data["timestamp"] > CACHE_TTL_SECONDS

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
  module FileCleaner
    def self.clean(file_path)
      return unless File.file?(file_path)
      return unless text_file?(file_path)

      content = File.read(file_path, encoding: "UTF-8")
      original = content.dup

      # Remove carriage returns
      content = content.gsub("\r", "")

      # Process lines
      lines = content.split("\n", -1)
      cleaned = []
      prev_blank = false

      lines.each do |line|
        # Trim trailing whitespace
        line = line.rstrip

        if line.empty?
          # Only add blank if previous wasn't blank
          unless prev_blank
            cleaned << ""
            prev_blank = true
          end
        else
          cleaned << line
          prev_blank = false
        end
      end

      # Remove trailing blank lines
      cleaned.pop while cleaned.last&.empty?

      result = cleaned.join("\n") + "\n"

      if result != original
        File.write(file_path, result)
        true
      else
        false
      end
    end

    def self.text_file?(path)
      # Check by extension
      text_exts = %w[.rb .yml .yaml .md .txt .sh .js .ts .jsx .tsx .css .html .json .xml .sql .py .go .rs .c .h .cpp .hpp]
      ext = File.extname(path).downcase
      text_exts.include?(ext)
    end

    def self.clean_dir(dir)
      cleaned = 0
      Dir.glob(File.join(dir, "**", "*")).each do |path|
        next unless File.file?(path)
        cleaned += 1 if clean(path)
      end
      cleaned
    end
  end
end

# IMPERATIVE SHELL

module Dmesg
  VERSION = "48.2"

  def self.boot
    return if Options.quiet

    if ENV["CONSTITUTIONAL_MINIMAL"]
      puts "#{green}constitutional #{VERSION}#{reset}"
      return
    end

    puts "#{bold}Constitutional AI #{VERSION}#{reset}"
    puts "#{dim}#{status_line}#{reset}"
    puts
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
    list: ["-", "\u{1F4CB}"]
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

  def call_model(model:, messages:, max_tokens:, temperature:)
    @stats[:calls] += 1

    chat = RubyLLM.chat(model: model, provider: :openrouter)

    user_msg = messages.find { |m| m[:role] == "user" }
    system_msg = messages.find { |m| m[:role] == "system" }

    full_prompt = ""
    full_prompt += "#{system_msg[:content]}\n\n" if system_msg
    full_prompt += user_msg[:content] if user_msg

    response = chat.ask(full_prompt)

    track_usage(response, model)

    response.content
  rescue StandardError => e
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

  DETECTION_SYSTEM_PROMPT = <<~PROMPT.strip
    You are a code quality analyzer. Your task:
    1. Scan code against 32 coding principles
    2. Return ONLY a valid JSON array of violations
    3. Each violation: {"principle_id": N, "line": N, "severity": "high|medium|low", "smell": "name", "explanation": "why", "auto_fixable": bool}
    4. Return [] if no violations found
    5. NO markdown, NO explanation text, ONLY JSON
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

    response = Spinner.run("Analyzing with AI (fast)") do
      call_llm_with_fallback(
        model: fast_model,
        fallback_models: config["fallback_models"],
        messages: build_cached_messages(system: DETECTION_SYSTEM_PROMPT, user: prompt),
        max_tokens: fast_max_tokens
      )
    end

    Core::LLMDetector.parse_violations(response.dig("choices", 0, "message", "content"))
  end

  def fast_model
    tiers = @constitution.llm_config["tiers"]
    config = @constitution.llm_config["detection"]
    tiers&.dig("fast", "model") || config["model"]
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
    
    # Generate fix (would call LLM to propose changes)
    proposed_fix = original_code # placeholder - would be LLM-generated fix
    
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
    
    # Apply fix and remember success
    auto_fixable.each do |v|
      @memory.remember(file_path, v, true, true)
    end

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
      Log.ok("Score 100/100 - Zero violations")
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
          when :perfect then Dmesg.icon(:up)
          when :tracking then Dmesg.icon(:chart)
          else Dmesg.icon(:list)
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
    @constitution.set_profile(Options.profile)
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
    when "--garden"
      run_gardener(:quick)
    when "--garden-full"
      run_gardener(:full)
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

  def parse_flags!(args)
    Options.quiet = args.delete("--quiet") || args.delete("-q")
    Options.json = args.delete("--json")
    Options.git_changed = args.delete("--git-changed") || args.delete("-g")
    Options.watch = args.delete("--watch") || args.delete("-w")
    Options.no_cache = args.delete("--no-cache")
    Options.parallel = !args.delete("--no-parallel")

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
    prompt = "#{Dmesg.cyan}c#{Dmesg.reset} "
    if READLINE_AVAILABLE
      Readline.readline(prompt, true)&.strip
    else
      print prompt
      $stdin.gets&.strip
    end
  end

  def process_file(file_path)
    unless File.exist?(file_path)
      Log.error("File not found: #{file_path}") unless Options.quiet
      return nil
    end

    # Clean: normalize file before analysis (CRLF, trailing whitespace, blank lines)
    if Core::FileCleaner.clean(file_path)
      Log.info("#{Dmesg.icon(:clean)} Cleaned: #{file_path}") unless Options.quiet
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
    puts "  --no-parallel   Disable parallel smell detection"
    puts "  --cost          Show LLM usage stats"
    puts "  --rollback <f>  Restore from backup"
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
    puts "  ruby cli.rb --quick .           # Fast scan with 5 core principles"
    puts "  ruby cli.rb --profile critical  # Critical issues only"
    puts "  ruby cli.rb --garden-full       # Self-improve constitution"
  end

  def show_cost
    puts
    puts "#{Dmesg.bold}LLM Cost Report#{Dmesg.reset}"
    puts

    # Current session
    if @llm.enabled?
      stats = @llm.stats
      puts "Session:"
      puts "  Calls:  #{stats[:calls]}"
      puts "  Tokens: #{stats[:tokens]}"
      puts "  Cost:   $#{format("%.4f", stats[:cost])}"
      puts
    end

    # Daily breakdown (last 7 days)
    daily = Core::CostTracker.daily_totals(7)
    if daily.any?
      puts "Daily (last 7 days):"
      daily.each do |date, data|
        puts "  #{date}: #{data[:calls]} calls, #{data[:tokens]} tokens, $#{format("%.4f", data[:cost])}"
      end
      puts
    end

    # Model breakdown
    by_model = Core::CostTracker.model_breakdown(7)
    if by_model.any?
      puts "By Model (last 7 days):"
      by_model.first(5).each do |model, data|
        short_name = model.split("/").last
        puts "  #{short_name}: #{data[:calls]} calls, $#{format("%.4f", data[:cost])}"
      end
      puts
    end

    # Total spending
    total = Core::CostTracker.total_spending
    if total[:calls] > 0
      puts "All Time:"
      puts "  Total calls:  #{total[:calls]}"
      puts "  Total tokens: #{total[:tokens]}"
      puts "  Total cost:   $#{format("%.4f", total[:cost])}"
      puts
    end
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
    cli = CLI.new
    cli.run(ARGV)

    # Exit 1 if any files had violations
    if cli.instance_variable_get(:@results)&.any? { |r| r[:score] < 100 }
      exit 1
    end
  rescue StandardError => error
    Log.error("Fatal: #{error.message}") unless Options.quiet
    Log.debug(error.backtrace.join("\n")) if ENV["VERBOSE"]
    exit 2
  end
end
