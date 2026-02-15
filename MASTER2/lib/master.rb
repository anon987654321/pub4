# frozen_string_literal: true

module MASTER
  VERSION = "2.0.0"
  def self.root = File.expand_path("..", __dir__)

  # Utils - Shared utility methods (DRY)
  module Utils
    module_function

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      m = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      (0..a.length).each { |i| m[i][0] = i }
      (0..b.length).each { |j| m[0][j] = j }

      (1..a.length).each do |i|
        (1..b.length).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          m[i][j] = [m[i - 1][j] + 1, m[i][j - 1] + 1, m[i - 1][j - 1] + cost].min
        end
      end

      m[a.length][b.length]
    end

    def similarity(a, b)
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      max_len = [a.length, b.length].max
      1.0 - (levenshtein(a, b).to_f / max_len)
    end
  end

  # Centralized path management - DRY principle for all file system paths
  # All paths flow through this module to ensure consistency
  module Paths
    class << self
      # Root directory of MASTER installation
      # @return [String] Absolute path to root
      def root
        MASTER.root
      end

      # Library directory
      # @return [String] Path to lib/
      def lib
        File.join(root, "lib")
      end

      # Data directory for static resources
      # @return [String] Path to data/
      def data
        File.join(root, "data")
      end

      # Variable data directory (runtime state)
      # @return [String] Path to var/
      def var
        @var ||= mkdir(File.join(root, "var"))
      end

      # Temporary files directory
      # @return [String] Path to var/tmp/
      def tmp
        @tmp ||= mkdir(File.join(var, "tmp"))
      end

      # Configuration directory
      # @return [String] Path to var/config/
      def config
        @config ||= mkdir(File.join(var, "config"))
      end

      # Cache directory
      # @return [String] Path to var/cache/
      def cache
        @cache ||= mkdir(File.join(var, "cache"))
      end

      # Logs directory
      # @return [String] Path to var/logs/
      def logs
        @logs ||= mkdir(File.join(var, "logs"))
      end

      # Sessions directory
      # @return [String] Path to var/sessions/
      def sessions
        @sessions ||= mkdir(File.join(var, "sessions"))
      end

      # Database file path (JSONL backend)
      # @return [String] Path to db directory
      def db
        @db ||= mkdir(File.join(var, "db"))
      end

      # Dmesg log file path (kernel-style logging)
      # @return [String] Path to dmesg.log
      def dmesg_log
        @dmesg_log ||= File.join(logs, "dmesg.log")
      end

      # Semantic cache directory for embeddings
      # @return [String] Path to semantic_cache/
      def semantic_cache
        @semantic_cache ||= mkdir(File.join(cache, "semantic"))
      end

      # Edge TTS output directory
      # @return [String] Path to edge_tts output
      def edge_tts_output
        @edge_tts_output ||= mkdir(File.join(var, "edge_tts"))
      end

      # DRY helpers for common path patterns

      # Get session file path by ID
      # @param id [String] Session identifier
      # @return [String] Full path to session file
      def session_file(id)
        safe_id = File.basename(id.to_s)
        File.join(sessions, "#{safe_id}.json")
      end

      # Get file path in var directory
      # @param name [String] Filename
      # @return [String] Full path to var file
      def var_file(name)
        File.join(var, name)
      end

      # Get file path in data directory
      # @param name [String] Filename
      # @return [String] Full path to data file
      def data_file(name)
        File.join(data, name)
      end

      private

      # Create directory if it doesn't exist
      # @param path [String] Directory path
      # @return [String] The path created
      def mkdir(path)
        FileUtils.mkdir_p(path)
        path
      end
    end
  end

  # AutoInstall - Automatic gem and package installation
  module AutoInstall
    GEMS = %w[
      ruby_llm
      stoplight
      tty-reader
      tty-prompt
      tty-spinner
      tty-table
      tty-box
      tty-markdown
      tty-progressbar
      tty-cursor
      pastel
      rouge
      falcon
      async-websocket
    ].freeze

    OPENBSD_PACKAGES = %w[
      ruby
      git
      curl
    ].freeze

    class << self
      def missing_gems
        GEMS.reject { |g| gem_installed?(g) }
      end

      def gem_installed?(name)
        Gem::Specification.find_by_name(name)
        true
      rescue Gem::MissingSpecError
        false
      end

      def install_gems(verbose: false)
        missing = missing_gems
        return if missing.empty?

        puts "Installing #{missing.size} gems..." if verbose
        missing.each do |gem|
          next unless gem.match?(/\A[a-z0-9_-]+\z/)
          system("gem", "install", gem, "--no-document")
        end
      end

      def require_gem(name)
        require name
      rescue LoadError
        return if @installed&.dig(name)
        return unless name.to_s.match?(/\A[a-z0-9_-]+\z/)
        @installed ||= {}
        $stderr.puts "Installing #{name}..."
        @installed[name] = system("gem", "install", name, "--no-document")
        require name
      end

      def openbsd?
        RUBY_PLATFORM.include?("openbsd")
      end

      def missing_packages
        return [] unless openbsd?
        OPENBSD_PACKAGES.reject { |p| package_installed?(p) }
      end

      def package_installed?(name)
        system("pkg_info -e '#{name}-*' > /dev/null 2>&1")
      end

      def install_packages(verbose: false)
        return unless openbsd?
        missing = missing_packages
        return if missing.empty?

        puts "Installing #{missing.size} packages..." if verbose
        valid_packages = missing.select { |p| p.match?(/\A[a-z0-9_-]+\z/) }
        system("doas", "pkg_add", *valid_packages) unless valid_packages.empty?
      end

      def setup(verbose: false)
        install_packages(verbose: verbose)
        install_gems(verbose: verbose)
      end

      def status
        {
          gems: { installed: GEMS.size - missing_gems.size, missing: missing_gems },
          packages: openbsd? ? { installed: OPENBSD_PACKAGES.size - missing_packages.size, missing: missing_packages } : nil
        }
      end
    end
  end

  # Boot - OpenBSD dmesg-style startup (dense, terse, beautiful)
  module Boot
    class << self
      # Lazy SMOKE_TEST_METHODS to avoid crashes if modules didn't load
      def smoke_test_methods
        {
          LLM => %i[ask pick tier=],
          Executor => %i[call],
          Result => %i[ok err ok? err?],
        }
      rescue NameError => e
        warn "Smoke test skipped: #{e.message}"
        {}
      end
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || ENV["USERNAME"] || "user"
        host = `hostname`.strip rescue "localhost"

        # Smoke test first - catch runtime errors early
        smoke_result = smoke_test

        # Dense dmesg - no fluff, no breathing room
        puts [
          c("MASTER #{VERSION} #1: #{timestamp}"),
          c("#{user}@#{host}:#{MASTER.root}"),
          c("cpu0 at mainbus0: #{RUBY_PLATFORM}"),
          c("ruby0 at cpu0: ruby #{RUBY_VERSION}"),
          c("db0 at ruby0: #{DB.axioms.size} axioms, #{DB.council.size} personas"),
          c("llm0 at db0: openrouter #{tier_models}"),
          c("budget0 at llm0: #{UI.currency(LLM.budget_remaining)} remaining"),
          c("tts0 at budget0: #{tts_status}"),
          c("self0 at tts0: #{self_awareness_summary}"),
          c("pledge0 at cpu0: #{Pledge.available? ? 'armed' : 'unavailable'}"),
          c("executor0 at pledge0: #{Executor::PATTERNS.join('/')}"),
          c("smoke0 at executor0: #{smoke_result}")
        ].join("\n")

        yield if block_given?  # Allow caller to inject web line before boot summary

        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts c("boot: #{elapsed}ms")
        puts
      end

      # For web mode, also print the URL
      def banner_with_web(port)
        banner do
          puts c("web0 at smoke0: http://localhost:#{port}")
        end
      end

      # Verify critical methods exist at runtime
      def smoke_test
        missing = []

        smoke_test_methods.each do |mod, methods|
          methods.each do |method|
            unless mod.respond_to?(method) || (mod.is_a?(Class) && mod.instance_methods.include?(method))
              missing << "#{mod}##{method}"
            end
          end
        end

        # Also check optional modules
        optional_checks = []
        optional_checks << "Chamber" if defined?(Chamber) && !Chamber.respond_to?(:council_review)
        optional_checks << "CodeReview" if defined?(CodeReview) && !CodeReview.respond_to?(:analyze)
        optional_checks << "AutoFixer" if defined?(AutoFixer) && !AutoFixer.instance_methods.include?(:fix)

        if missing.any?
          UI.warn("Missing methods: #{missing.join(', ')}")
          "FAIL #{missing.size}"
        elsif optional_checks.any?
          "WARN #{optional_checks.join(',')}"
        else
          "ok"
        end
      rescue StandardError => e
        "FAIL #{e.message[0..30]}"
      end

      private

      def c(text)
        UI.colorize(text)
      end

      def tier_models
        LLM.model_tiers.map do |tier, models|
          names = models.first(2).map { |m| LLM.extract_model_name(m) }.join(",")
          "#{tier}:#{names}"
        end.join(" ")
      end

      def tts_status
        Speech.engine_status
      rescue StandardError
        "off"
      end

      def self_awareness_summary
        SelfMap.summary
      rescue StandardError
        "unavailable"
      end
    end
  end
end

require "fileutils"
require "time"
require "shellwords"

require_relative "utils"
require_relative "paths"
require_relative "auto_install"
require_relative "boot"

# Core
require_relative "result"
require_relative "logging"
require_relative "db_jsonl"
require_relative "llm"
require_relative "session"
require_relative "pledge"
require_relative "rubocop_detector"

# Multi-language parsing and NLU (optional)
%w[../../lib/parser/multi_language ../../lib/nlu ../../lib/conversation].each do |dep|
  begin
    require_relative dep
  rescue LoadError => e
    raise unless e.path.nil? || e.message.include?(File.basename(dep))
  end
end

# Safe Autonomy Architecture
require_relative "staging"

# UI & NN/g compliance
require_relative "ui"
require_relative "undo"
require_relative "commands"

# Pipeline stages
require_relative "stages"

# Executor
require_relative "executor"

# Pipeline
require_relative "pipeline"
require_relative "hooks"
require_relative "questions"
require_relative "workflow"

# Deliberation engines
require_relative "chamber"

# Tools
require_relative "shell"
require_relative "analysis"
require_relative "problem_solver"
require_relative "evolve"
require_relative "queue"
require_relative "personas"
require_relative "harvester"

# Web browsing
require_relative "web"

# Speech
require_relative "speech"

# Media generation and post-processing bridges
require_relative "bridges"

# External services
%w[weaviate replicate cinematic semantic_cache].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end

# Agents
require_relative "agent"

# Meta/Self-improvement
require_relative "review"
require_relative "learnings"
require_relative "file_processor"
require_relative "reflow"
require_relative "multi_refactor"

# Generators
require_relative "html_generator"

# Quality gates
require_relative "quality_gates"

# Web UI
%w[server].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end

# Boot-time self-check
if ENV["MASTER_SELF_CHECK"] == "true" && defined?(MASTER::Enforcement)
  Thread.new do
    sleep (ENV["MASTER_SELF_CHECK_DELAY"] || "1").to_i
    begin
      MASTER::Enforcement.self_check!
    rescue StandardError => e
      warn "MASTER: self_check! failed (#{e.message})"
    end
  end
end
