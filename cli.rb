#!/usr/bin/env ruby
# frozen_string_literal: true
# cli.rb v49.75 - Constitutional AI code quality + autonomous assistant

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

module Bootstrap
  GEMS = {
    "ruby_llm" => "ruby_llm",
    "tty-spinner" => "tty-spinner",
    "tty-prompt" => "tty-prompt",
    "tty-table" => "tty-table",
    "tty-progressbar" => "tty-progressbar",
    "concurrent-ruby" => "concurrent-ruby",
    "falcon" => "falcon"
  }.freeze
  OPENBSD_DEPS = {
    "ruby_llm" => [],
    "falcon" => []
  }.freeze
  def self.run
    missing = GEMS.select { |gem_name, _| !gem_installed?(gem_name) }
    return if missing.empty?
    puts "Installing missing gems: #{missing.keys.join(', ')}..."
    install_openbsd_deps(missing.keys) if platform == :openbsd
    missing.each { |_, pkg_name| install_gem(pkg_name) }
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
  COMMANDS = %w[ls cd pwd cat tree scan fix sprawl clean plan complete session cost trace status help quit exit mode scrape].freeze
  Readline.completion_proc = proc do |input|
    COMMANDS.grep(/^#{Regexp.escape(input)}/)
  end
rescue LoadError
  READLINE_AVAILABLE = false
end
begin
  require "ferrum"
  FERRUM_AVAILABLE = true
rescue LoadError
  FERRUM_AVAILABLE = false
end
module Sandbox
  def self.init
    return unless RUBY_PLATFORM =~ /openbsd/
    begin
      unveil("/home", "r")
      unveil("/tmp", "rwc")
      unveil("/usr/local/lib/ruby", "r")
      unveil("/usr/local/bin", "rx")
      unveil("/etc/ssl", "r")
      unveil(nil, nil)
      pledge("stdio rpath wpath cpath inet dns proc exec tty")
      Log.debug("sandbox: pledge/unveil active") if defined?(Log)
    rescue => e
      warn "sandbox: #{e.message}" if ENV["DEBUG"]
    end
  end
  private
  def self.unveil(path, permissions)
    return unless defined?(OpenBSD)
    OpenBSD.unveil(path, permissions)
  rescue NoMethodError
  end
  def self.pledge(promises)
    return unless defined?(OpenBSD)
    OpenBSD.pledge(promises)
  rescue NoMethodError
  end
end
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
    attr_accessor :quiet, :json, :git_changed, :watch, :no_cache, :parallel, :profile, :force, :fix, :dry_run
  end
end
module Core
  FILE_SCAN_LIMIT = 50
  LARGE_SCAN_LIMIT = 100
  CODE_EXTENSIONS = "*.{rb,py,js,ts}"
  def self.read_file(path)
    File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  rescue
    ""
  end
  def self.glob_files(root_dir, pattern = CODE_EXTENSIONS, limit: FILE_SCAN_LIMIT)
    Dir.glob(File.join(root_dir, "**", pattern))
      .reject { |f| f.include?("node_modules") || f.include?("vendor") || f.include?(".git") }
      .first(limit)
  end
  def self.write_file(path, content, backup: false)
    if backup && File.exist?(path)
      FileUtils.cp(path, "#{path}.bak.#{Time.now.to_i}")
    end
    File.write(path, content)
  end
  module PrincipleRegistry
    def self.load(constitution)
      constitution["principles"] || {}
    end
    def self.find_by_id(principles, id)
      principles.find { |_key, p| p["id"] == id }&.last
    end
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
      principle_summary = build_compact_summary(principles)
      prompt = prompt_template.gsub("{principles}", principle_summary)
      prompt += "\n\nCode to analyze:\n```ruby\n#{code}\n```"
      {
        prompt: prompt,
        file_path: file_path
      }
    end
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
    RATES = {
      deepseek_v3: { input: 0.14, output: 0.28 },
      grok_code: { input: 0.20, output: 1.50 },
      glm: { input: 0.30, output: 0.60 },
      gemini_flash: { input: 0.10, output: 0.40 },
      kimi: { input: 0.50, output: 1.50 },
      medium: { input: 3.0, output: 15.0 },
      strong: { input: 15.0, output: 75.0 },
      grok: { input: 5.0, output: 15.0 },
      default: { input: 1.0, output: 3.0 }
    }.freeze
    def self.estimate(model, prompt_tokens, completion_tokens)
      rate = rate_for(model)
      (prompt_tokens * rate[:input] / 1_000_000) + (completion_tokens * rate[:output] / 1_000_000)
    end
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
  end
  module Cache
    CACHE_DIR = File.join(Dir.home, ".cache", "constitutional")
    CACHE_TTL_SECONDS = 24 * 60 * 60
    def self.init
      FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
    end
    def self.key_for(file_path, content)
      require "digest"
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
  module ModelCooldown
    @cooldowns = {}
    @mutex = Mutex.new
    DEFAULT_COOLDOWN = 300
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
  end
  module LanguageDetector
    AUTO_DETECT = %w[.rb .py .js .ts .jsx .tsx .sh .bash .zsh .yml .yaml .md].freeze
    def self.detect_with_fallback(file_path, code, supported_languages)
      ext = File.extname(file_path).downcase
      if AUTO_DETECT.include?(ext)
        lang = detect_by_extension(file_path, supported_languages)
        return lang if lang != "unknown"
      end
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
  end
  module ProjectAnalyzer
    def self.tree(root_dir)
      root = root_dir.chomp("/")
      entries = []
      Dir.glob(File.join(root, "**", "*")).each do |path|
        next if path.include?("/.") || File.basename(path).start_with?(".")
        next if skip_dir?(path)
        entries << "#{path}/" if File.directory?(path)
      end
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
    def self.clean(root_dir, dry_run: false)
      cleaned = []
      tree(root_dir).each do |path|
        next if path.end_with?("/")
        next unless text_file?(path)
        result = clean_file(path, dry_run: dry_run)
        cleaned << result if result[:changed]
      end
      cleaned
    end
    def self.text_file?(path)
      text_exts = %w[.rb .py .js .ts .sh .zsh .yml .yaml .json .md .txt .html .css .erb .haml .slim .rake .gemspec .conf]
      return true if text_exts.include?(File.extname(path).downcase)
      begin
        bytes = File.binread(path, 512)
        return false if bytes.include?("\x00")
        true
      rescue
        false
      end
    end
    def self.clean_file(path, dry_run: false)
      original = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace, mode: "rb")
      cleaned = original.dup
      cleaned.gsub!("\r\n", "\n")
      cleaned.gsub!("\r", "")
      lines = cleaned.split("\n", -1)
      lines = lines.map { |line| line.rstrip }
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
      cleaned = result.join("\n").rstrip + "\n"
      changed = cleaned != original
      if changed && !dry_run
        File.write(path, cleaned)
        Log.info("Cleaned: #{path}")
      end
      { path: path, changed: changed, original_size: original.bytesize, cleaned_size: cleaned.bytesize }
    end
    def self.prescan(root_dir, dry_run: true)
      Log.info("Pre-scanning: #{root_dir}")
      files = tree(root_dir)
      Log.info("Found #{files.count { |f| !f.end_with?('/') }} files in #{files.count { |f| f.end_with?('/') }} directories")
      { files: files, cleaned_count: 0 }
    end
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
    def self.detect_sprawl(files, config)
      sprawl = []
      temp_patterns = config.dig("sprawl", "temp_patterns") || %w[.tmp .bak .swp ~$ .orig .cache]
      temp_files = files.select { |f| temp_patterns.any? { |p| f[:path].include?(p) } }
      sprawl << { type: :temp_files, files: temp_files.map { |f| f[:path] }, count: temp_files.size } if temp_files.any?
      tiny_threshold = config.dig("sprawl", "tiny_threshold") || 20
      tiny_files = files.select { |f| f[:lines] > 0 && f[:lines] < tiny_threshold }
      if tiny_files.size > 5
        sprawl << { type: :tiny_files, files: tiny_files.map { |f| f[:path] }, count: tiny_files.size,
                    message: "#{tiny_files.size} tiny files (<#{tiny_threshold} lines) - consider consolidating" }
      end
      dir_counts = files.group_by { |f| File.dirname(f[:path]) }
      crowded_dirs = dir_counts.select { |_, v| v.size > 15 }
      crowded_dirs.each do |dir, dir_files|
        sprawl << { type: :crowded_dir, path: dir, count: dir_files.size,
                    message: "#{dir_files.size} files in #{dir} - consider subdirectories" }
      end
      deep_files = files.select { |f| f[:path].split(File::SEPARATOR).size > 8 }
      if deep_files.any?
        sprawl << { type: :deep_nesting, files: deep_files.map { |f| f[:path] }, count: deep_files.size,
                    message: "#{deep_files.size} deeply nested files (>8 levels)" }
      end
      sprawl
    end
    def self.find_duplicates(files)
      duplicates = []
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
    def self.detect_fragmentation(files, config)
      fragmentation = []
      semantic_groups = {}
      files.each do |f|
        basename = File.basename(f[:path], ".*")
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
    def self.suggest_consolidations(files, config)
      suggestions = []
      helper_files = files.select { |f| f[:path] =~ /helper/ }
      if helper_files.size > 3
        suggestions << {
          action: :merge,
          files: helper_files.map { |f| f[:path] },
          target: "lib/helpers.rb",
          reason: "Consolidate #{helper_files.size} helper files"
        }
      end
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
  end
  module StructuralAnalyzer
    def self.analyze(root_dir, constitution)
      questions = constitution.data["structural_analysis"] || {}
      issues = []
      config_files = Dir.glob(File.join(root_dir, "**", "*.{yml,yaml,json}"))
      config_files.each do |f|
        issues.concat(analyze_config(f, questions["config_hierarchy"] || []))
        issues.concat(check_merge_opportunities(f, questions["merge_opportunities"] || []))
      end
      code_files = Dir.glob(File.join(root_dir, "**", "*.{rb,py,js,ts}"))
      code_files.each do |f|
        issues.concat(analyze_code_structure(f, questions["code_hierarchy"] || []))
      end
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
        if keys.size > 15
          issues << { file: file_path, type: :sprawl, message: "#{keys.size} top-level keys - consider grouping" }
        end
        scalars = keys.select { |k| !content[k].is_a?(Hash) && !content[k].is_a?(Array) }
        complex = keys.select { |k| content[k].is_a?(Hash) || content[k].is_a?(Array) }
        if scalars.any? && complex.any? && scalars.size > 2
          issues << { file: file_path, type: :hierarchy, message: "Mixed scalars (#{scalars[0..2].join(', ')}) with complex sections" }
        end
        keys.combination(2).each do |a, b|
          if similar_keys?(a, b)
            issues << { file: file_path, type: :merge, message: "Possibly overlapping: #{a} and #{b}" }
          end
        end
      rescue => e
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
      top_level = content.scan(/^(module|class)\s+(\w+)/).map(&:last)
      if top_level.size > 10
        issues << { file: file_path, type: :sprawl, smell: :god_file, message: "#{top_level.size} top-level modules/classes" }
      end
      util_patterns = %w[Log Logger Util Utils Helper Helpers]
      scattered = top_level.select { |t| util_patterns.any? { |p| t.include?(p) } }
      if scattered.size > 1
        issues << { file: file_path, type: :fragmentation, smell: :scattered_functionality, message: "Scattered utilities: #{scattered.join(', ')}" }
      end
      method_lengths = detect_method_lengths(content)
      method_lengths.each do |name, length|
        if length > 20
          issues << { file: file_path, type: :bloater, smell: :long_method, message: "#{name}: #{length} lines" }
        end
      end
      content.scan(/def\s+(\w+)\(([^)]+)\)/).each do |name, params|
        param_count = params.split(",").size
        if param_count > 4
          issues << { file: file_path, type: :bloater, smell: :long_parameter_list, message: "#{name}: #{param_count} params" }
        end
      end
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
      Dir.glob(File.join(root_dir, "**", "*.{rb,py,yml,yaml}")).first(50).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
        if content.match?(/[A-Z]:\\|\/home\/\w+|\/Users\/\w+/)
          issues << { file: f, type: :decouple, smell: :hardcoded_path, message: "Hardcoded path - use env var" }
        end
      end
      issues
    end
    def self.detect_dead_code(root_dir)
      issues = []
      definitions = {}
      references = Hash.new(0)
      Dir.glob(File.join(root_dir, "**", "*.rb")).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
        content.scan(/def\s+(\w+)/).each { |m| definitions[m[0]] = f }
        content.scan(/class\s+(\w+)/).each { |m| definitions[m[0]] = f }
        content.scan(/module\s+(\w+)/).each { |m| definitions[m[0]] = f }
        content.scan(/\b([A-Z]\w+)\b/).each { |m| references[m[0]] += 1 }
        content.scan(/\.(\w+)/).each { |m| references[m[0]] += 1 }
      end
      definitions.each do |name, file|
        next if %w[initialize new call].include?(name)
        if references[name] <= 1
          issues << { file: file, type: :dispensable, smell: :dead_code, message: "#{name} may be unused" }
        end
      end
      issues.first(20)
    end
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
    def self.cross_reference(root_dir)
      issues = []
      terms = Hash.new { |h, k| h[k] = [] }
      types = Hash.new { |h, k| h[k] = [] }
      Dir.glob(File.join(root_dir, "**", "*.{rb,py,js,ts,yml,yaml}")).first(100).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
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
        content.scan(/\b(user|account|member|config|settings|options|data|info|params|args)\b/i).each do |term|
          terms[term[0].downcase] << f
        end
      end
      types.each do |name, occurrences|
        type_set = occurrences.map { |o| o[:type] }.uniq
        if type_set.size > 1
          issues << { type: :cross_ref, smell: :type_inconsistency,
                      message: "#{name} has types: #{type_set.join(', ')}" }
        end
      end
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
    def self.simulate_edge_cases(root_dir)
      issues = []
      Dir.glob(File.join(root_dir, "**", "*.rb")).first(50).each do |f|
        content = File.read(f, encoding: "UTF-8") rescue ""
        if content.match?(/\.(\w+)/) && !content.match?(/&\.|\.nil\?|rescue|if .+\.nil/)
          method_calls = content.scan(/(\w+)\.(\w+)/).size
          nil_checks = content.scan(/&\.|\.nil\?|unless.*nil|if.*nil/).size
          if method_calls > 10 && nil_checks < method_calls / 5
            issues << { file: f, type: :simulation, smell: :missing_nil_checks,
                        message: "#{method_calls} method calls, only #{nil_checks} nil checks" }
          end
        end
        if content.match?(/\.each|\.map|\.select/) && !content.match?(/\.empty\?|\.any\?|\.size\s*[>=<]/)
          issues << { file: f, type: :simulation, smell: :no_empty_check,
                      message: "Iterates without checking empty" }
        end
        if content.match?(/File\.(read|write|open|delete)/) && !content.match?(/rescue|begin.*File/)
          issues << { file: f, type: :simulation, smell: :unhandled_io,
                      message: "File operations without error handling" }
        end
        if content.match?(/`.*#\{|system.*#\{|exec.*#\{|%x.*#\{/)
          issues << { file: f, type: :simulation, smell: :injection_risk,
                      message: "String interpolation in shell command" }
        end
      end
      issues
    end
    def self.detect_micro_refinements(root_dir)
      issues = []
      Core.glob_files(root_dir, Core::CODE_EXTENSIONS).each do |f|
        content = Core.read_file(f)
        next if content.empty?
        lines = content.lines
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
        content.scan(/[^a-zA-Z_](\d{2,})[^a-zA-Z_\d]/).each do |match|
          num = match[0].to_i
          next if [10, 60, 100, 1000, 1024].include?(num)
          issues << { file: f, type: :refinement, check: :magic_number,
                      message: "Magic number: #{num}" } if issues.count { |i| i[:check] == :magic_number } < 5
        end
        if content.match?(/rescue\s*($|#)/) || content.match?(/rescue\s+=>/)
          issues << { file: f, type: :refinement, check: :bare_rescue,
                      message: "Bare rescue without exception type" }
        end
        content.scan(%r{["'](/(?:usr|etc|home|var|tmp)/[^"']+)["']}).each do |match|
          issues << { file: f, type: :refinement, check: :hardcoded_path,
                      message: "Hardcoded path: #{match[0][0..40]}" } if issues.count { |i| i[:check] == :hardcoded_path } < 3
        end
        line_hashes = {}
        lines.each_cons(3).with_index do |block, i|
          hash = block.map(&:strip).join.hash
          if line_hashes[hash]
            issues << { file: f, type: :refinement, check: :duplicate_pattern,
                        message: "Lines #{line_hashes[hash]+1} and #{i+1} are similar" }
            break
          end
          line_hashes[hash] = i
        end
        camel = content.scan(/\b[a-z]+[A-Z][a-zA-Z]+\b/).uniq
        snake = content.scan(/\b[a-z]+_[a-z]+\b/).uniq
        if camel.size > 3 && snake.size > 3
          issues << { file: f, type: :refinement, check: :inconsistent_naming,
                      message: "Mixed naming: #{camel.size} camelCase, #{snake.size} snake_case" }
        end
      end
      issues.first(30)
    end
    def self.detect_cross_file_dry(root_dir)
      issues = []
      files = Core.glob_files(root_dir, Core::CODE_EXTENSIONS, limit: Core::LARGE_SCAN_LIMIT)
      call_patterns = Hash.new { |h, k| h[k] = [] }
      block_hashes = Hash.new { |h, k| h[k] = [] }
      constants_used = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        content = Core.read_file(f)
        next if content.empty?
        lines = content.lines
        content.scan(/(File\.(?:read|write|open)\([^)]{20,}\))/).each do |match|
          call_patterns[match[0].gsub(/["'][^"']+["']/, '...')] << f
        end
        content.scan(/(Dir\.glob\([^)]+\))/).each do |match|
          call_patterns[match[0].gsub(/["'][^"']+["']/, '...')] << f
        end
        lines.each_cons(5).with_index do |block, i|
          normalized = block.map { |l| l.strip.gsub(/\s+/, ' ') }.join("\n")
          next if normalized.length < 50
          block_hashes[normalized.hash] << { file: f, line: i + 1 }
        end
        content.scan(/\b(\d{2,4})\b/).each do |match|
          num = match[0]
          next if %w[10 100 1000 1024 2048 4096].include?(num)
          constants_used[num] << f
        end
      end
      call_patterns.each do |pattern, occurrences|
        if occurrences.uniq.size >= 3
          issues << { type: :cross_file_dry, check: :duplicate_function_calls,
                      message: "#{pattern[0..50]}... in #{occurrences.uniq.size} files",
                      files: occurrences.uniq.first(3) }
        end
      end
      block_hashes.each do |hash, occurrences|
        if occurrences.size >= 2 && occurrences.map { |o| o[:file] }.uniq.size >= 2
          issues << { type: :cross_file_dry, check: :copy_paste_blocks,
                      message: "5-line block duplicated",
                      files: occurrences.map { |o| "#{o[:file]}:#{o[:line]}" }.first(3) }
        end
      end
      constants_used.each do |num, occurrences|
        if occurrences.uniq.size >= 3
          issues << { type: :cross_file_dry, check: :magic_number_spread,
                      message: "Magic number #{num} in #{occurrences.uniq.size} files",
                      files: occurrences.uniq.first(3) }
        end
      end
      issues.first(20)
    end
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
  module OpenBSDConfig
    CACHE_DIR = File.join(Dir.home, ".constitutional", "man_cache")
    def self.extract_configs(code, config_map)
      configs = []
      return configs unless config_map
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
    def self.fetch_man_page(man_page, base_url, cache_ttl = 86400)
      FileUtils.mkdir_p(CACHE_DIR)
      cache_file = File.join(CACHE_DIR, "#{man_page}.txt")
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
    def self.validate_config(config_name, content, config_rules)
      return { valid: true, warnings: [] } unless config_rules
      rules = config_rules[config_name]
      return { valid: true, warnings: [] } unless rules
      warnings = []
      (rules["required_patterns"] || []).each do |pattern|
        unless content.include?(pattern)
          warnings << "Missing required: '#{pattern}'"
        end
      end
      (rules["warnings"] || []).each do |w|
        if w["pattern"]
          if w["absent_message"] && !content.include?(w["pattern"])
            warnings << w["absent_message"]
          elsif w["message"] && content.include?(w["pattern"])
            warnings << w["message"]
          end
        end
      end
      (rules["forbidden_patterns"] || []).each do |pattern|
        if content.include?(pattern)
          warnings << "Forbidden pattern found: '#{pattern}'"
        end
      end
      { valid: warnings.empty?, warnings: warnings }
    end
    def self.fix_config_in_source(source_code, config_path, old_content, new_content)
      escaped_old = Regexp.escape(old_content)
      pattern = /(cat\s*>+\s*#{Regexp.escape(config_path)}\s*<<[-~]?['"]?(\w+)['"]?\n)#{escaped_old}(\n\2)/m
      if source_code.match?(pattern)
        source_code.gsub(pattern, "\\1#{new_content}\\3")
      else
        source_code
      end
    end
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
          full_content: cfg[:content]
        }
      end
      context
    end
    def self.generate_fix(config, warnings, man_summary, llm)
      return nil unless llm&.enabled?
      prompt = <<~PROMPT
        You are an OpenBSD system administrator expert.
        Config file: #{config[:name]} (for #{config[:daemon]} daemon)
        Man page: #{config[:man_url]}
        Current config content:
        ```
        ```
        Issues found:
        Man page reference (excerpt):
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
  module FileWatcher
    def self.watch(paths, interval: 1.0, &block)
      mtimes = {}
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
  module TreeWalk
    def self.print_tree(dir = ".")
      dir = dir.chomp("/")
      entries = []
      Dir.glob(File.join(dir, "**", "*")).each do |path|
        next if File.basename(path).start_with?(".")
        if File.directory?(path)
          entries << "#{path}/"
        end
      end
      Dir.glob(File.join(dir, "**", "*")).each do |path|
        next if File.basename(path).start_with?(".")
        next unless File.file?(path)
        entries << path
      end
      entries
    end
  end
  module FileCleaner
    def self.clean(file_path)
      return false unless File.file?(file_path)
      result = ProjectAnalyzer.clean_file(file_path, dry_run: false)
      result[:changed]
    end
  end
end
module Replicate
  API_BASE = "https://api.replicate.com/v1"
  MODELS = {
    img: "google/nano-banana-pro",
    img_fast: "black-forest-labs/flux-2-klein-4b",
    img_edit: "bytedance/seedream-4.5",
    img_openai: "openai/gpt-image-1.5",
    vid: "google/veo-3.1-fast",
    vid_pro: "kwaivgi/kling-v2.6",
    vid_physics: "pixverse/pixverse-v5.6",
    music: "elevenlabs/music",
    tts: "qwen/qwen3-tts",
    llm: "google/gemini-3-flash",
    llm_agent: "moonshotai/kimi-k2.5"
  }.freeze
  TEMPLATES = {
    portrait:   "photorealistic portrait, 85mm f/1.8, shallow DOF, golden hour 45°, " \
                "natural skin texture, ARRI Alexa Mini LF, Kodak Vision3 500T",
    headshot:   "professional headshot, 85mm f/1.8, soft diffused studio lighting, " \
                "neutral background, crisp detail, confident expression",
    product:    "commercial product photography, studio softbox lighting, " \
                "clean white background, shallow DOF, professional",
    cinematic:  "cinematic 2.39:1 anamorphic, teal/orange grading, dramatic rim light, " \
                "Atlas Orion 40mm, lens flares, film grain",
    anime:      "anime illustration, Studio Ghibli aesthetic, cel shading, " \
                "vibrant colors, detailed background, soft lighting",
    cyberpunk:  "neon cyberpunk cityscape, rain-slicked streets, holographic ads, " \
                "dramatic contrast, cool tones, blade runner aesthetic",
    epic:       "dramatic composition, rocky cliff above clouds, ethereal atmosphere, " \
                "flowing robes, cinematic grading, serene power",
    fashion:    "high fashion editorial, dramatic studio lighting, bold shading, " \
                "crisp details, Vogue aesthetic",
    retro:      "early-2000s digital aesthetic, harsh flash, blown highlights, " \
                "subtle grain, nostalgic, V6 realism",
    minimal:    "minimalist composition, clean lines, negative space, " \
                "muted tones, elegant simplicity",
    vid_slow:   "Camera: Slow dolly-in, smooth motion. Subject: Subtle movement, " \
                "natural breathing. Cinematic lighting, film grain.",
    vid_action: "Camera: Tracking shot, low angle. Subject: Dynamic movement, " \
                "realistic momentum. Slow-mo 120fps, dramatic light.",
    vid_orbit:  "Camera: Smooth 270° orbital. Subject: Centered, micro-movements. " \
                "Golden hour, shallow DOF, documentary style.",
    vid_talk:   "Camera: Medium shot, slight sway. Subject: Speaking, lip sync, " \
                "natural expressions. Ambient audio matching scene.",
    lofi:       "lo-fi hip hop, warm vinyl crackle, jazzy piano, relaxed drums, " \
                "study vibes, nostalgic atmosphere",
    epic_music: "epic orchestral, sweeping strings, powerful brass, " \
                "cinematic percussion, emotional crescendo",
    edm:        "high-energy EDM, punchy drums, synth leads, build-up and drop, " \
                "festival-ready, 128 BPM",
    ambient:    "ambient soundscape, ethereal pads, gentle textures, " \
                "meditation quality, peaceful atmosphere",
    narrator:   "warm storyteller voice, gentle pacing, audiobook quality, engaging",
    news:       "professional news anchor, confident, measured pace, authoritative",
    casual:     "friendly conversational voice, natural rhythm, approachable tone"
  }.freeze
  STYLES = {
    photo:   ", photorealistic, 8K, ultra-detailed",
    film:    ", 35mm film grain, Kodak Portra 400, nostalgic",
    neon:    ", neon lighting, cyberpunk, vibrant colors",
    minimal: ", minimalist, clean, negative space",
    vintage: ", vintage aesthetic, film grain, muted colors",
    hdr:     ", HDR, high dynamic range, vivid colors",
    anime:   ", anime style, cel shading, vibrant",
    dark:    ", dark moody, dramatic shadows, noir",
    bright:  ", bright and airy, soft natural light",
    dreamy:  ", ethereal atmosphere, soft focus, pastels",
    sharp:   ", ultra-sharp, crisp details, high clarity",
    soft:    ", soft focus, gentle blur, romantic"
  }.freeze
end
module Scraper
  MAX_DEPTH = 2
  TIMEOUT = 30
  SCREENSHOT_DIR = File.join(Dir.home, ".constitutional", "screenshots")
  def self.fetch(url, screenshot: false, depth: 0)
    FileUtils.mkdir_p(SCREENSHOT_DIR) if screenshot
    if FERRUM_AVAILABLE
      fetch_ferrum(url, screenshot: screenshot, depth: depth)
    else
      fetch_simple(url)
    end
  rescue => e
    { error: e.message, url: url }
  end
  def self.fetch_ferrum(url, screenshot: false, depth: 0)
    browser = Ferrum::Browser.new(
      timeout: TIMEOUT,
      headless: true,
      window_size: [1920, 1080]
    )
    browser.goto(url)
    sleep 1
    result = {
      url: url,
      title: browser.title,
      content: browser.body,
      text: extract_text(browser.body),
      links: extract_links(browser.body, url)
    }
    if screenshot
      filename = "#{Time.now.to_i}_#{url.gsub(/[^a-z0-9]/i, '_')[0..50]}.png"
      path = File.join(SCREENSHOT_DIR, filename)
      browser.screenshot(path: path)
      result[:screenshot] = path
    end
    browser.quit
    if depth > 0 && result[:links].any?
      result[:children] = result[:links].first(5).map do |link|
        fetch_ferrum(link, screenshot: false, depth: depth - 1)
      end
    end
    result
  end
  def self.fetch_simple(url)
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    {
      url: url,
      status: response.code,
      content: response.body,
      text: extract_text(response.body),
      links: extract_links(response.body, url)
    }
  rescue => e
    { error: e.message, url: url }
  end
  def self.extract_text(html)
    text = html.gsub(/<script[^>]*>.*?<\/script>/mi, '')
    text = text.gsub(/<style[^>]*>.*?<\/style>/mi, '')
    text = text.gsub(/<[^>]+>/, ' ')
    text = text.gsub(/\s+/, ' ')
    text.strip[0..10000]
  end
  def self.extract_links(html, base_url)
    links = html.scan(/href=["']([^"']+)["']/i).flatten
    base = URI(base_url)
    links.map do |link|
      begin
        resolved = URI.join(base, link).to_s
        resolved if resolved.start_with?('http')
      rescue
        nil
      end
    end.compact.uniq.first(20)
  end
end
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
      commands = extract_commands(assistant_reply)
      { reply: assistant_reply, commands: commands }
    end
    def execute(cmd, use_doas: false)
      full_cmd = use_doas ? "doas #{cmd}" : cmd
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
  VERSION = "49.75"
  def self.boot
    return if Options.quiet
    puts ">> master.yml #{VERSION}"
    if llm_ready?
      puts "boot> llm0: #{primary_model} (#{tier_count} tiers)"
    else
      puts "boot> llm0: offline (set OPENROUTER_API_KEY)"
    end
    puts "boot> const0: #{principle_count} principles armed"
    puts "boot> root: #{Dir.pwd}"
  end
  def self.primary_model
    content = File.read(File.expand_path("master.yml", __dir__), encoding: "UTF-8", invalid: :replace, undef: :replace)
    yaml = YAML.safe_load(content, permitted_classes: [Symbol])
    yaml.dig("llm", "tiers", "fast", "models")&.first || "openrouter/auto"
  rescue
    "openrouter/auto"
  end
  def self.tier_count
    content = File.read(File.expand_path("master.yml", __dir__), encoding: "UTF-8", invalid: :replace, undef: :replace)
    yaml = YAML.safe_load(content, permitted_classes: [Symbol])
    yaml.dig("llm", "tiers")&.keys&.size || 4
  rescue
    4
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
  def self.log(level, message)
    prefix = case level
    when :ok then "#{Dmesg.green}ok#{Dmesg.reset}"
    when :error then "#{Dmesg.red}err#{Dmesg.reset}"
    when :warn then "#{Dmesg.yellow}warn#{Dmesg.reset}"
    else "#{Dmesg.dim}#{level}#{Dmesg.reset}"
    end
    puts "#{prefix} #{message}"
  end
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
    kill_old_servers
    html_path = File.join(File.dirname(__FILE__), "cli.html")
    @server = WEBrick::HTTPServer.new(
      Port: @port,
      BindAddress: "0.0.0.0",
      Logger: WEBrick::Log.new(File.exist?("/dev/null") ? "/dev/null" : "NUL"),
      AccessLog: []
    )
    @server.mount_proc "/" do |req, res|
      if File.exist?(html_path)
        res.content_type = "text/html"
        res.body = File.read(html_path)
      else
        res.status = 404
        res.body = "cli.html not found"
      end
    end
    @server.mount_proc "/poll" do |req, res|
      res.content_type = "application/json"
      begin
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
    @server.mount_proc "/chat" do |req, res|
      res.content_type = "application/json"
      begin
        body = JSON.parse(req.body)
        message = body["message"]
        if message && !message.empty?
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
    @server.mount_proc "/persona" do |req, res|
      res.content_type = "application/json"
      if req.request_method == "POST"
        body = JSON.parse(req.body) rescue {}
        @current_persona = body["persona"] if body["persona"]
      end
      res.body = JSON.generate({ persona: @current_persona })
    end
    @thread = Thread.new { @server.start }
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
    if RUBY_PLATFORM =~ /openbsd|linux|darwin/
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
  end
  def process_chat(message)
    return nil unless @cli
    @cli.instance_variable_set(:@chat_history, @cli.instance_variable_get(:@chat_history) || [])
    @cli.instance_variable_get(:@chat_history) << { role: "user", content: message }
    tiered = @cli.instance_variable_get(:@tiered)
    return "LLM not available" unless tiered&.enabled?
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
    # Hooks loaded from master.yml (optional)
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
    if response.respond_to?(:cached_tokens)
      @stats[:cached_tokens] += response.cached_tokens || 0
    end
  end
  def estimate_cost(model, prompt, completion)
    Core::CostEstimator.estimate(model, prompt, completion)
  end
end
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
      Based on these patterns, suggest:
      1. New principles or smells to add
      2. Existing principles that need clarification
      3. Priority adjustments
      Return structured YAML that can merge into master.yml
    PROMPT
    @tiered.ask_tier("strong", prompt)
  end
end
module Learning
  MASTER_PATH = File.expand_path("master.yml", __dir__)
  BACKUP_PATH = File.expand_path("master.yml.bak", __dir__)
  def self.record_correction(smell, correction, context = {})
    entry = {
      "id" => "learned_#{Time.now.to_i}",
      "original_smell" => smell,
      "correction" => correction,
      "context" => context,
      "recorded_at" => Time.now.iso8601,
      "confirmed" => false
    }
    update_master_yml do |yaml|
      yaml["learned_smells"] ||= []
      yaml["learned_smells"] << entry
      yaml["learned_smells"] = yaml["learned_smells"].last(100)
    end
    Log.ok("Learned: #{smell[0..30]}... → #{correction[0..30]}...")
    entry
  end
  def self.confirm(id)
    update_master_yml do |yaml|
      smell = yaml["learned_smells"]&.find { |s| s["id"] == id }
      if smell
        smell["confirmed"] = true
        smell["confirmed_at"] = Time.now.iso8601
        Log.ok("Confirmed: #{id}")
      end
    end
  end
  def self.promote(id, principle_name)
    update_master_yml do |yaml|
      smell = yaml["learned_smells"]&.find { |s| s["id"] == id }
      return Log.warn("Not found: #{id}") unless smell
      yaml["principles"] ||= {}
      yaml["principles"][principle_name] = {
        "priority" => 5,
        "description" => "Learned: #{smell['correction']}",
        "learned_from" => id,
        "promoted_at" => Time.now.iso8601
      }
      yaml["learned_smells"].delete(smell)
      Log.ok("Promoted #{id} → principle:#{principle_name}")
    end
  end
  def self.update_master_yml
    FileUtils.cp(MASTER_PATH, BACKUP_PATH) if File.exist?(MASTER_PATH)
    content = File.read(MASTER_PATH, encoding: "UTF-8")
    yaml = YAML.safe_load(content, permitted_classes: [Symbol, Time, Date])
    yield yaml
    header = content.lines.take_while { |l| l.start_with?('#') || l.strip.empty? }.join
    new_content = header + yaml.to_yaml.sub(/^---\n/, "---\n")
    File.write(MASTER_PATH, new_content, encoding: "UTF-8")
    true
  rescue => e
    Log.warn("Learning failed: #{e.message}")
    FileUtils.cp(BACKUP_PATH, MASTER_PATH) if File.exist?(BACKUP_PATH)
    false
  end
  def self.list
    content = File.read(MASTER_PATH, encoding: "UTF-8")
    yaml = YAML.safe_load(content, permitted_classes: [Symbol, Time, Date])
    yaml["learned_smells"] || []
  end
end
class ReflectionCritic
  def initialize(tiered_llm)
    @tiered = tiered_llm
  end
  def critique(original_code, proposed_fix, violations_fixed)
    return { approved: true, confidence: 1.0 } unless @tiered.enabled?
    prompt = <<~PROMPT
      You are a strict code quality critic. Review this proposed fix:
      ORIGINAL CODE:
      PROPOSED FIX:
      VIOLATIONS BEING FIXED:
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
  def ask_tier(tier, prompt_or_messages, system_prompt: nil)
    return nil unless @enabled
    if prompt_or_messages.is_a?(Array)
      @tiered&.ask_tier(tier, prompt_or_messages.last[:content], system_prompt: system_prompt || prompt_or_messages.first[:content])
    else
      @tiered&.ask_tier(tier, prompt_or_messages, system_prompt: system_prompt)
    end
  end
  def chat(messages, tier: "medium")
    return nil unless @enabled
    @tiered&.ask_tier(tier, messages.last[:content], system_prompt: messages.first[:content])
  end
  def query(prompt, tier: "fast")
    return nil unless @enabled
    @tiered&.ask_tier(tier, prompt)
  end
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
    @tiered = TieredLLM.new(@constitution)
  end
  def call_llm_with_fallback(model:, fallback_models:, messages:, max_tokens:)
    models = [model] + (fallback_models || [])
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
          man_content = Core::OpenBSDConfig.fetch_man_page(cfg[:man_page], base_url, cache_ttl)
          Log.info("    ↳ Fetched #{base_url}/#{cfg[:man_page]}") if man_content
          validation = Core::OpenBSDConfig.validate_config(cfg[:name], cfg[:content], config_map)
          if validation[:warnings].any?
            validation[:warnings].each { |w| Log.warn("    #{w}") }
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
                puts "#{Dmesg.dim}    - #{cfg[:content].lines.first&.strip&.slice(0, 60)}#{Dmesg.reset}"
                puts "#{Dmesg.green}    + #{fixed_content.lines.first&.strip&.slice(0, 60)}#{Dmesg.reset}"
              end
            end
          else
            Log.ok("    No issues found")
          end
        end
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
    auto_fixable.each do |v|
      rate = @memory.success_rate(v["smell"])
      if rate > 0 && rate < 0.3
        Log.warn("  Low past success (#{(rate * 100).round}%) for: #{v['smell']}") unless Options.quiet
      end
    end
    proposed_fix = generate_fix_for_violations(file_path, original_code, auto_fixable)
    return Result.ok(false) if proposed_fix.nil? || proposed_fix == original_code
    if @critic
      critique = @critic.critique(original_code, proposed_fix, auto_fixable)
      confidence = critique["confidence"] || 0.5
      if critique["approved"] == false
        Log.warn("Fix rejected by critic (confidence: #{(confidence * 100).round}%)")
        (critique["issues"] || []).each { |i| Log.warn("  - #{i}") }
        auto_fixable.each do |v|
          @memory.remember(file_path, v, false, false)
        end
        return Result.ok(false)
      end
      Log.info("Critic approved (confidence: #{(confidence * 100).round}%)") unless Options.quiet
    end
    apply_fix_in_place(file_path, original_code, proposed_fix)
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
      Current code:
      ```
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
    if content =~ /```\w*\n(.*?)```/m
      return $1.strip
    end
    content.strip
  end
  def apply_fix_in_place(file_path, original, fixed)
    return false if fixed.nil? || fixed.empty? || fixed == original
    backup_path = "#{file_path}.bak.#{Time.now.to_i}"
    File.write(backup_path, original)
    Log.info("Backup: #{backup_path}")
    File.write(file_path, fixed)
    Log.ok("Fixed in-place: #{file_path}")
    true
  rescue => e
    Log.error("Failed to apply fix: #{e.message}")
    false
  end
  def scan_with_llm(file_path)
    code = File.read(file_path, encoding: "UTF-8")
    unless Options.no_cache
      cached = Core::Cache.get(file_path, code)
      if cached
        Log.info("(cached)") unless Options.quiet
        return cached
      end
    end
    violations = @llm.detect_violations(code, file_path)
    Core::Cache.set(file_path, code, violations) unless Options.no_cache
    violations
  end
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
    if ENV["TRACE"]
      stats = @llm.stats if @llm.enabled?
      puts "  #{Dmesg.dim}[trace] model=#{@llm&.current_model} tokens=#{stats&.dig(:tokens)} cost=$#{format("%.4f", stats&.dig(:cost) || 0)}#{Dmesg.reset}"
      content = File.read(file_path) rescue ""
      puts "  #{Dmesg.dim}[trace] cache_key=#{Core::Cache.key_for(file_path, content)}#{Dmesg.reset}"
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
    @status.set("Analyzing #{files.size} files")
    analysis = analyze_project_completeness(files)
    @status.set("Creating completion plan")
    @plan = create_completion_plan(analysis)
    puts @plan.to_s
    puts
    print "Execute plan? (y/n) "
    return unless $stdin.gets&.strip&.downcase == "y"
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
      if content.match?(/TODO|FIXME|XXX|HACK|WIP|INCOMPLETE/i)
        todos = content.lines.each_with_index.select { |l, _| l.match?(/TODO|FIXME|XXX|HACK|WIP/i) }
        analysis[:todos] += todos.map { |l, n| { file: file, line: n + 1, text: l.strip } }
      end
      if content.match?(/raise\s+NotImplementedError|pass\s*$|\.\.\.$/m)
        analysis[:stub_functions] << file
      end
      if file.end_with?(".rb", ".py")
        if !content.match?(/^#\s*@|^"""|^'''|^# frozen_string_literal/)
          analysis[:missing_docs] << file
        end
      end
      if file.end_with?(".rb")
        result = `ruby -c "#{file}" 2>&1`
        analysis[:errors] << { file: file, error: result } unless $?.success?
      end
    end
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
    if analysis[:errors].any?
      plan.add_task("Fix syntax errors", analysis[:errors].map { |e| "#{e[:file]}: #{e[:error].lines.first}" })
    end
    if analysis[:stub_functions].any?
      plan.add_task("Implement stub functions", analysis[:stub_functions].first(10))
    end
    if analysis[:todos].any?
      grouped = analysis[:todos].group_by { |t| t[:file] }
      grouped.first(10).each do |file, todos|
        plan.add_task("Complete TODOs in #{File.basename(file)}", todos.map { |t| "L#{t[:line]}: #{t[:text][0..60]}" })
      end
    end
    if analysis[:missing_tests].any?
      plan.add_task("Add test coverage", analysis[:missing_tests].first(5).map { |f| "Test for #{File.basename(f)}" })
    end
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
      ```
      Provide the completed/fixed code. Return ONLY the code, no explanations.
      If the task is about TODOs, implement what the TODO describes.
      If the task is about stubs, implement the function logic.
      If the task is about docs, add appropriate documentation.
    PROMPT
    print "  Completing #{File.basename(file)}... "
    response = @tiered&.ask_tier("code", prompt)
    if response && response.length > 100
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
    targets.each do |t|
      if File.directory?(t)
        Log.info("#{Dmesg.icon(:folder)} Entering: #{t}") unless Options.quiet
        tree = Core::TreeWalk.print_tree(t)
        tree.first(20).each { |e| puts "  #{e}" } unless Options.quiet
        puts "  ..." if tree.size > 20 && !Options.quiet
        unless Options.force || Options.quiet
          print "#{Dmesg.dim}process #{tree.size} items? [y/N]#{Dmesg.reset} "
          return unless $stdin.gets&.strip&.downcase == "y"
        end
      end
    end
    files = expand_targets(targets)
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
    passed = @results.count { |r| (r[:score] || 0) == 100 }
    puts
    Log.ok("Processed #{total} files: #{passed}/#{total} at 100/100")
  end
  def output_results
    puts JSON.pretty_generate({
      version: Dmesg::VERSION,
      files: @results,
      summary: {
        total: @results.size,
        passed: @results.count { |r| (r[:score] || 0) == 100 },
        failed: @results.count { |r| (r[:score] || 0) < 100 }
      }
    })
  end
  def interactive_mode
    @cwd = Dir.pwd
    @last_action = Time.now
    start_time = Time.now
    web_url = nil
    begin
      @web_server = WebServer.new(self)
      web_url = @web_server.start
    rescue => e
      puts "  [trace] web.fail #{e.message}" if ENV["TRACE"]
    end
    if ENV["TRACE"]
      puts "[trace] boot cwd=#{@cwd}"
      puts "[trace] boot constitution=#{@constitution&.principles&.size}p"
      puts "[trace] boot llm=#{@llm&.enabled? ? 'ready' : 'disabled'}"
      puts "[trace] boot tiers=#{@constitution&.models&.keys&.join('|')}"
      puts "[trace] boot time=#{format("%.2fs", Time.now - start_time)}"
    end
    puts "#{web_url}" if web_url
    @empty_count = 0
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
      when /^mode\s+(.+)/i, /^persona\s+(.+)/i
        switch_mode($1.strip)
      when "mode", "modes", "personas"
        list_modes
      when /^gen\s+(\S+)\s+(.+)/i
        generate_file($1.strip, $2.strip)
      when /^gen\s+(\S+)/i
        generate_file($1.strip)
      when "gen"
        puts "gen <type> [name]  - html, css, rb, sh, yml, erb"
      when /^learn\s+(.+)/i
        record_learning($1)
      when "learned", "learnings"
        show_learnings
      when /^scrape\s+(.+)/i
        scrape_url($1.strip)
      when /^agent\s+(\w+)\s*(.*)/i, /^(snap|whatsapp|tiktok|insta|openclaw)\s*(.*)/i
        launch_agent($1.downcase, $2.strip)
      when "agents"
        list_agents
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
        if looks_like_path?(input)
          process_targets([input])
        else
          chat_response(input)
        end
      end
      puts
    end
  end
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
      analysis = analyze_project_completeness(find_project_files(path))
      total_issues = analysis[:todos].size + analysis[:stub_functions].size + analysis[:errors].size
      if total_issues == 0
        suggestions = find_improvements(path)
        if suggestions.empty?
          Log.ok("Complete.")
          break
        else
          work_on_improvement(suggestions.first)
          next
        end
      end
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
      puts "#{iteration}: #{total_issues} remaining" if iteration % 5 == 1
      success = false
      if analysis[:errors].any?
        success = fix_error(analysis[:errors].first)
      elsif analysis[:stub_functions].any?
        success = implement_stub(analysis[:stub_functions].first)
      elsif analysis[:todos].any?
        success = complete_todo(analysis[:todos].first)
      end
      if success
        @stuck_count = 0
      else
        @stuck_count += 1
        if @stuck_count >= 3
          answer = ask_user_for_help(analysis)
          if answer
            @stuck_count = 0
          else
            Log.warn("Stuck. Moving to next issue.")
            rotate_issues(analysis)
          end
        end
      end
      sleep 0.5
      @session.save
    end
    @status.clear
    puts "Done. #{iteration} iterations."
  end
  def find_improvements(path)
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
  def research(topic)
    puts "Researching: #{topic}"
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
      result = search_or_infer(query)
      results << { query: query, result: result } if result
    end
    if results.any?
      synthesis_prompt = <<~P
        Research findings on: #{topic}
        Synthesize into actionable implementation guidance. Be specific about code patterns, libraries, approaches.
      P
      @tiered&.ask_tier("medium", synthesis_prompt)
    else
      nil
    end
  end
  def search_or_infer(query)
    prompt = <<~P
      Search query: #{query}
      Provide the most relevant technical information for implementing this.
      Include: libraries, code patterns, gotchas, best practices.
      Be specific and actionable.
    P
    @tiered&.ask_tier("fast", prompt)
  end
  def research_and_implement(issue, context = "")
    research_result = research(issue)
    if research_result
      prompt = <<~P
        Task: #{issue}
        Context: #{context}
        Research findings:
        Now implement this. Return code only.
      P
      @tiered&.ask_tier("code", prompt)
    else
      puts "No research results. Need help with: #{issue[0..50]}"
      print "Hint? "
      hint = $stdin.gets&.strip
      return nil if hint.nil? || hint.empty?
      @tiered&.ask_tier("code", "Implement #{issue} using hint: #{hint}")
    end
  end
  def run_replicate(args)
    unless ENV["REPLICATE_API_TOKEN"]
      Log.warn("set REPLICATE_API_TOKEN")
      return
    end
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
    when "find", "search", "?"
      replicate_find(prompt)
    when "top", "popular", "hot"
      replicate_top(prompt)
    when "pick"
      replicate_pick
    when "styles"
      puts "Styles: #{Replicate::STYLES.keys.join(', ')}"
      puts "Usage: rep img +film woman in cafe"
    when "templates"
      puts "Templates: #{Replicate::TEMPLATES.keys.join(', ')}"
      puts "Usage: rep img @portrait woman with red hair"
    when "help"
      replicate_help
    else
      puts "rep img|vid|audio|tts <prompt>   generate content"
      puts "rep find|top|pick                discover models"
      puts "rep styles|templates             list modifiers"
      puts "rep help                         full reference"
    end
  end
  def replicate_help
    puts <<~HELP
      ╭─ GENERATE ────────────────────────────────────╮
      │ rep img <prompt>    image (nano-banana-pro)   │
      │ rep vid <prompt>    video+audio (veo-3.1)     │
      │ rep audio <prompt>  music (elevenlabs)        │
      │ rep tts <text>      speech (qwen3-tts)        │
      │ rep wild <prompt>   random model chain        │
      ╰───────────────────────────────────────────────╯
      ╭─ DISCOVER ────────────────────────────────────╮
      │ rep find <query>    search 50k+ models        │
      │ rep top [category]  popular by category       │
      │ rep pick            interactive picker        │
      ╰───────────────────────────────────────────────╯
      ╭─ TEMPLATES (@) ───────────────────────────────╮
      │ @portrait @headshot @product @cinematic       │
      │ @anime @cyberpunk @epic @fashion @retro       │
      │ @vid_slow @vid_action @vid_orbit @vid_talk    │
      │ @lofi @epic_music @edm @ambient               │
      │ @narrator @news @casual                       │
      ╰───────────────────────────────────────────────╯
      ╭─ STYLES (+) ──────────────────────────────────╮
      │ +photo +film +neon +minimal +vintage +hdr     │
      │ +anime +dark +bright +dreamy +sharp +soft     │
      ╰───────────────────────────────────────────────╯
      Examples:
        rep img @portrait woman with red hair +film
        rep vid @vid_slow ocean waves at sunset
        rep audio @lofi rainy night study session
        rep tts @narrator Once upon a time...
    HELP
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
  def replicate_wait(id, name = "Task", timeout: 300)
    Cursor.hide
    spin_chars = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
    start = Time.now
    i = 0
    loop do
      sleep 2
      res = replicate_api(:get, "/predictions/#{id}")
      unless res
        Cursor.show
        return nil
      end
      data = JSON.parse(res.body)
      elapsed = (Time.now - start).to_i
      case data["status"]
      when "succeeded"
        print "\r#{name} ✓ (#{elapsed}s)      \n"
        Cursor.show
        output = data["output"]
        return output.is_a?(Array) ? output.first : output
      when "failed"
        print "\r#{name} ✗ #{data['error']&.slice(0,40)}      \n"
        Cursor.show
        return nil
      else
        print "\r#{spin_chars[i % spin_chars.size]} #{name}... #{elapsed}s"
        i += 1
      end
      if Time.now - start > timeout
        print "\r#{name} timeout      \n"
        Cursor.show
        return nil
      end
    end
  end
  def replicate_generate(prompt)
    return Log.warn("No prompt") if prompt.empty?
    final_prompt = apply_replicate_styles(prompt)
    puts "🖼 #{final_prompt[0..60]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:img],
      input: { prompt: final_prompt, num_outputs: 1 }
    })
    return unless res
    data = JSON.parse(res.body)
    url = replicate_wait(data["id"], "Image", timeout: 60)
    if url
      filename = "gen_#{Time.now.strftime('%H%M%S')}.webp"
      download_file(url, filename)
      Log.ok("Saved: #{filename}")
    end
  end
  def replicate_video(prompt)
    return Log.warn("No prompt") if prompt.empty?
    final_prompt = apply_replicate_styles(prompt)
    puts "🎬 #{final_prompt[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:vid],
      input: { prompt: final_prompt, duration: 5, aspect_ratio: "16:9" }
    })
    return unless res
    vid_url = replicate_wait(JSON.parse(res.body)["id"], "Video", timeout: 180)
    if vid_url
      filename = "vid_#{Time.now.strftime('%H%M%S')}.mp4"
      download_file(vid_url, filename)
      Log.ok("Saved: #{filename}")
    end
  end
  def apply_replicate_styles(prompt)
    result = prompt.dup
    Replicate::TEMPLATES.each do |key, template|
      if result.include?("@#{key}")
        result.gsub!("@#{key}", "")
        result = "#{result.strip}, #{template}"
      end
    end
    Replicate::STYLES.each do |key, suffix|
      if result.include?("+#{key}")
        result.gsub!("+#{key}", "")
        result += suffix
      end
    end
    result.strip
  end
  def replicate_chain(prompt)
    system("ruby", File.join(File.dirname(__FILE__), "repligen.rb"), "chain", prompt)
  end
  def replicate_wild(prompt)
    system("ruby", File.join(File.dirname(__FILE__), "repligen.rb"), "wild", prompt)
  end
  def replicate_find(query)
    return puts("Usage: rep find <query>") if query.empty?
    puts "Searching: #{query}"
    res = replicate_api(:get, "/models?query=#{URI.encode_www_form_component(query)}")
    return unless res
    data = JSON.parse(res.body)
    models = data["results"] || []
    if models.empty?
      puts "No models found"
      return
    end
    puts ""
    models.first(8).each_with_index do |m, i|
      runs = m["run_count"] ? "#{(m['run_count']/1000.0).round(1)}K" : "-"
      name = "#{m['owner']}/#{m['name']}"
      desc = m['description']&.slice(0,45) || ""
      printf "  %d. %-35s %6s  %s\n", i+1, name, runs, desc
    end
    puts "\n  Use: rep img --model=owner/name <prompt>"
  end
  def replicate_top(category = "")
    models = {
      "img"   => { img: "nano-banana-pro", img_fast: "flux-2-klein", img_edit: "seedream-4.5" },
      "vid"   => { vid: "veo-3.1-fast", vid_pro: "kling-v2.6", vid_physics: "pixverse-v5.6" },
      "audio" => { music: "elevenlabs/music", tts: "qwen/qwen3-tts" },
      "llm"   => { llm: "gemini-3-flash", agent: "kimi-k2.5" }
    }
    if category.empty? || !models[category]
      puts "Top models:"
      models.each do |cat, items|
        puts "  #{cat}:"
        items.each { |k, v| puts "    #{k}: #{v}" }
      end
      puts "\n  rep top img|vid|audio|llm"
    else
      puts "#{category}:"
      models[category].each { |k, v| puts "  #{k}: #{Replicate::MODELS[k]}" }
    end
  end
  def replicate_pick
    cats = {
      "1" => ["img", "🖼  Image"],
      "2" => ["vid", "🎬 Video"],
      "3" => ["audio", "🎵 Music"],
      "4" => ["tts", "🗣  Speech"],
      "5" => ["wild", "🎲 Chain"]
    }
    puts "Select:"
    cats.each { |k, v| puts "  #{k}. #{v[1]}" }
    print "> "
    choice = $stdin.gets&.strip
    return if choice.nil? || choice.empty?
    cat_info = cats[choice]
    unless cat_info
      puts "Pick 1-5"
      return
    end
    print "Prompt: "
    prompt = $stdin.gets&.strip
    return if prompt.nil? || prompt.empty?
    case cat_info[0]
    when "img"   then replicate_generate(prompt)
    when "vid"   then replicate_video(prompt)
    when "audio" then replicate_audio(prompt)
    when "tts"   then replicate_tts(prompt)
    when "wild"  then replicate_wild(prompt)
    end
  end
  def replicate_audio(prompt)
    return Log.warn("no prompt") if prompt.empty?
    final_prompt = apply_replicate_styles(prompt)
    puts "🎵 #{final_prompt[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:music],
      input: { prompt: final_prompt, duration: 30 }
    })
    return unless res
    url = replicate_wait(JSON.parse(res.body)["id"], "Music", timeout: 120)
    if url
      filename = "music_#{Time.now.strftime('%H%M%S')}.mp3"
      download_file(url, filename)
      Log.ok("Saved: #{filename}")
    end
  end
  def replicate_tts(text)
    return Log.warn("no text") if text.empty?
    final_text = apply_replicate_styles(text)
    puts "🗣 #{final_text[0..50]}..."
    res = replicate_api(:post, "/predictions", {
      model: Replicate::MODELS[:tts],
      input: { text: final_text }
    })
    return unless res
    url = replicate_wait(JSON.parse(res.body)["id"], "TTS", timeout: 60)
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
      gen html|css|rb|sh    generate minimalist code
      rep img <prompt>      image generation
      rep vid <prompt>      video generation
      snap|whatsapp|insta   social agents
      openclaw              universal chatbot
      mode <name>           switch persona
      scrape <url>          fetch webpage
      learn <pattern>       record improvement
      plan complete         tasks
      run ! <cmd>           shell
      quit                  exit
    HELP
  end
  def switch_mode(mode_name)
    personas = @constitution.raw_config.dig("identity", "personas", "available") || {}
    if personas[mode_name]
      @current_mode = mode_name
      persona = personas[mode_name]
      if persona["knowledge_sources"]
        @knowledge_sources = persona["knowledge_sources"]
        puts "knowledge: #{@knowledge_sources.size} sources loaded"
      end
      puts persona["greeting"] || "Mode: #{mode_name}"
      puts "focus: #{persona['focus']}" if persona["focus"]
    else
      puts "Unknown mode: #{mode_name}"
      list_modes
    end
  end
  def list_modes
    personas = @constitution.raw_config.dig("identity", "personas", "available") || {}
    puts "Available modes:"
    personas.each do |name, config|
      current = @current_mode == name ? " *" : ""
      puts "  #{name}#{current}: #{config['description']}"
    end
    puts "\nSwitch: mode <name>"
  end
  def record_learning(pattern)
    if pattern.include?("->")
      parts = pattern.split("->", 2).map(&:strip)
      Learning.record_correction(parts[0], parts[1], { cwd: Dir.pwd })
    else
      puts "Format: learn <wrong> -> <correct>"
      puts "Example: learn 'use puts' -> 'prefer Log.info for structured output'"
    end
  end
  def show_learnings
    learnings = Learning.list
    if learnings.empty?
      puts "No learnings recorded yet"
      puts "Record with: learn <wrong> -> <correct>"
    else
      puts "Learned patterns (#{learnings.size}):"
      learnings.last(10).each do |l|
        status = l["confirmed"] ? "✓" : "○"
        puts "  #{status} #{l['id']}: #{l['original_smell'][0..30]} → #{l['correction'][0..30]}"
      end
    end
  end
  def scrape_url(url)
    url = "https://#{url}" unless url.start_with?("http")
    puts "Fetching: #{url}"
    result = Scraper.fetch(url, screenshot: FERRUM_AVAILABLE)
    if result[:error]
      Log.warn("Scrape failed: #{result[:error]}")
      return
    end
    puts "Title: #{result[:title]}" if result[:title]
    puts "Text: #{result[:text][0..500]}..." if result[:text]
    puts "Links: #{result[:links]&.size || 0} found"
    puts "Screenshot: #{result[:screenshot]}" if result[:screenshot]
    @last_scrape = result
  end
  AGENTS = {
    "snap" => {
      name: "Snapchat Agent",
      description: "Engagement bot for Snapchat",
      persona: "casual, fun, emoji-friendly, Gen-Z voice",
      actions: %w[dm story react add_friend]
    },
    "whatsapp" => {
      name: "WhatsApp Agent",
      description: "Business messaging automation",
      persona: "helpful, professional, multilingual",
      actions: %w[message broadcast template catalog]
    },
    "tiktok" => {
      name: "TikTok Agent",
      description: "Content and engagement automation",
      persona: "trendy, viral-aware, hashtag-savvy",
      actions: %w[post duet comment follow trend]
    },
    "insta" => {
      name: "Instagram Agent",
      description: "Feed and DM automation",
      persona: "aesthetic, influencer-style, visual-first",
      actions: %w[post story reel dm engage]
    },
    "openclaw" => {
      name: "OpenClaw",
      description: "Universal AI chatbot framework",
      persona: "adaptive, context-aware, platform-agnostic",
      actions: %w[chat respond learn adapt]
    }
  }.freeze
  def launch_agent(agent_name, args = "")
    agent = AGENTS[agent_name]
    unless agent
      puts "Unknown agent: #{agent_name}"
      list_agents
      return
    end
    puts "#{agent[:name]} starting..."
    puts "Persona: #{agent[:persona]}"
    puts "Actions: #{agent[:actions].join(', ')}"
    if args.empty?
      puts "\nEnter message (or 'exit'):"
      loop do
        print "#{agent_name}> "
        input = $stdin.gets&.strip
        break if input.nil? || input == "exit"
        response = agent_respond(agent_name, input, agent[:persona])
        puts response
      end
    else
      puts agent_respond(agent_name, args, agent[:persona])
    end
  end
  def agent_respond(agent_name, message, persona)
    return "LLM required for agent responses" unless @tiered&.enabled?
    prompt = <<~PROMPT
      You are the #{agent_name} social media agent.
      Persona: #{persona}
      Respond to this user message in character:
      "#{message}"
      Keep response under 280 chars. No hashtags unless asked.
    PROMPT
    @tiered.ask_tier("fast", prompt) || "..."
  end
  def list_agents
    puts "Available agents:"
    AGENTS.each do |key, agent|
      puts "  #{key.ljust(10)} #{agent[:description]}"
    end
    puts "\nLaunch: agent <name> [message]"
    puts "        snap hello world"
  end
  def generate_file(type, name = nil)
    gen_config = @constitution.raw_config.dig("generation", type)
    unless gen_config
      puts "Unknown type: #{type}"
      puts "Available: html, css, rb, sh, yml, erb"
      return
    end
    ext = type == "yml" ? "yml" : type
    name ||= "new"
    filename = name.include?(".") ? name : "#{name}.#{ext}"
    if File.exist?(filename)
      print "#{filename} exists. Overwrite? [y/N] "
      return unless $stdin.gets&.strip&.downcase == "y"
    end
    if gen_config["template"]
      content = gen_config["template"] % { name: name.capitalize, title: name.capitalize, content: "", body: "echo 'hello'" }
    elsif @tiered&.enabled?
      rules = gen_config["rules"]&.join("\n- ") || ""
      prompt = <<~PROMPT
        Generate a minimal #{type} file named #{name}.
        Follow these rules:
        - #{rules}
        Return ONLY the file content, no explanation.
      PROMPT
      content = @tiered.ask_tier("medium", prompt)
    else
      Log.warn("No template and LLM unavailable")
      return
    end
    File.write(filename, content.strip + "\n", encoding: "UTF-8")
    Log.ok("Created: #{filename}")
    puts "Style: #{gen_config['rules']&.first}" if gen_config["rules"]
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
    return true if input.match?(%r{^[./~]})
    return true if input.match?(/\.\w+$/)
    return true if input.match?(/^[\w\-_.]+$/) && (File.exist?(input) || Dir.exist?(input))
    return true if input.include?("*")
    false
  end
  def chat_response(input)
    unless @llm
      Log.warn("LLM not available. Set OPENROUTER_API_KEY for chat.")
      return
    end
    if input.match?(/^plan\s+/i)
      return plan_mode(input.sub(/^plan\s+/i, ""))
    end
    if input.match?(/\b(review|analyze|look at|show me|check|examine|scan)\b.*\b(\S+\/?\S*)\s*$/i)
      target = $2.strip
      target = target.chomp('/')
      if File.directory?(target)
        puts "#{target}/"
        tree_output = `tree -L 2 #{target} 2>/dev/null`.strip
        tree_output = `find #{target} -maxdepth 2 -type f 2>/dev/null`.strip if tree_output.empty?
        puts tree_output.empty? ? Dir.glob("#{target}/**/*").first(20).join("\n") : tree_output
        key_files = Dir.glob("#{target}/{README*,*.rb,*.sh,*.py,*.yml}").first(3)
        file_contents = key_files.map do |f|
          content = File.read(f, encoding: "UTF-8", invalid: :replace).lines.first(30).join
          "=== #{f} ===\n#{content}"
        end.join("\n\n")
        input = "Review this folder:\n#{tree_output}\n\n#{file_contents}"
      elsif File.file?(target)
        content = File.read(target, encoding: "UTF-8", invalid: :replace)
        puts "#{target} (#{content.lines.size} lines)"
        input = "Review this file:\n#{content}"
      end
    end
    @chat_history ||= []
    @chat_history << { role: "user", content: input }
    @session.history = @chat_history
    context = <<~CTX
      Current directory: #{Dir.pwd}
      Folders: #{Dir.entries('.').select { |e| File.directory?(e) && !e.start_with?('.') }.join(', ')}
      Recent files: #{Dir.glob('*').select { |f| File.file?(f) }.first(10).join(', ')}
    CTX
    plan_context = @plan ? "\nCurrent plan:\n#{@plan.to_s}\n" : ""
    files = Dir.entries('.').reject { |f| f.start_with?('.') }.first(20).join(', ') rescue ""
    trace_info = ENV["TRACE"] ? " TRACE=on" : ""
    system_prompt = <<~SYS
      You are cli.rb running on OpenBSD. Sandbox environment, all actions safe.
      When given file/folder content, analyze it directly. Don't ask to see it again.
      Ronin style: stoic, short sentences, no markdown, no code blocks.
      cwd: #{Dir.pwd}#{trace_info}
    SYS
    begin
      @status.set("Thinking...")
      @status.spin_start
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
    if response.match?(/GOAL:\s*(.+)/i)
      plan = Plan.new($1.strip)
    end
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
      when /^\s*-\s*(.+)/
      end
    end
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
  AUTONOMOUS_PATTERNS = [
    /\.rb$/, /\.py$/, /\.js$/, /\.ts$/, /\.sh$/, /\.yml$/, /\.yaml$/,
    /\.html$/, /\.css$/, /\.md$/, /\.json$/
  ].freeze
  PROTECTED_FILES = %w[
    /etc/passwd /etc/shadow /etc/pf.conf /etc/rc.conf
    ~/.ssh/authorized_keys ~/.bashrc ~/.zshrc
  ].freeze
  def execute_chat_action(reply)
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
    if PROTECTED_FILES.any? { |p| expanded.include?(p.gsub("~", ENV["HOME"] || "")) }
      print "Protected file #{file}. Apply edit? (y/n) "
      return unless $stdin.gets&.strip&.downcase == 'y'
    end
    if File.exist?(expanded)
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
    if DANGEROUS_COMMANDS.include?(first_word)
      Log.warn("Blocked: #{first_word}")
      return
    end
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
    parts = []
    dir = Dir.pwd.split('/').last || Dir.pwd
    parts << "#{Dmesg.cyan}#{dir}#{Dmesg.reset}"
    if File.exist?(".git") || File.exist?("../.git")
      branch = `git branch --show-current 2>/dev/null`.strip rescue ""
      parts << "#{Dmesg.dim}#{branch}#{Dmesg.reset}" unless branch.empty?
    end
    "#{parts.join(' ')} #{Dmesg.magenta}>#{Dmesg.reset} "
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
    detected = Core::LanguageDetector.detect_with_fallback(
      file_path,
      code,
      config["supported"]
    )
    return detected if detected != "unknown"
    return "unknown" if Options.quiet || Options.json
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
    if cli.instance_variable_get(:@results)&.any? { |r| (r[:score] || 0) < 100 }
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
