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
end

require "fileutils"

# Auto-install missing gems first
require_relative "auto_install"
# Gems auto-install on first LoadError — no blocking boot

# Core
require_relative "result"
require_relative "logging"  # Unified logging (replaces log.rb, logging.rb, dmesg.rb)
require_relative "db_jsonl"
require_relative "llm"
require_relative "memory"
require_relative "session"
require_relative "pledge"
require_relative "rubocop_detector"  # Style checking integration

# Multi-language parsing and NLU (optional — from parent repo)
%w[../../lib/parser/multi_language ../../lib/nlu ../../lib/conversation].each do |dep|
  begin
    require_relative dep
  rescue LoadError
    # MASTER2 runs standalone without parent repo
  end
end

# Safe Autonomy Architecture
require_relative "constitution"
require_relative "staging"

# UI & NN/g compliance
require_relative "ui"
require_relative "help"
require_relative "axiom_stats"
require_relative "autocomplete"
require_relative "progress"
require_relative "undo"
require_relative "dashboard"
require_relative "commands"
require_relative "keybindings"
require_relative "confirmations"
require_relative "error_suggestions"
require_relative "nng_checklist"
require_relative "onboarding"
require_relative "context_window"

# Pipeline stages (needed by executor)
require_relative "boot"
require_relative "stages"

# Executor (ReAct pattern - default behavior)
require_relative "executor"

# Pipeline
require_relative "pipeline"
require_relative "hooks"
require_relative "convergence"
require_relative "questions"
require_relative "workflow_engine"

# Deliberation engines
require_relative "chamber"
require_relative "swarm"
require_relative "creative_chamber"  # Creative ideation engine (restored from MASTER v1)

# Tools
require_relative "shell"
require_relative "introspection"  # Includes self_map functionality (consolidated)
require_relative "problem_solver"
require_relative "evolve"
require_relative "validator"
require_relative "queue"              # Priority task queue (restored from MASTER v1)
require_relative "engine"             # Unified scan facade (restored from MASTER v1)
require_relative "agent_autonomy"     # Goal decomposition & self-correction (restored from MASTER v1)
require_relative "personas"           # Persona management (restored from MASTER v1)
require_relative "harvester"          # Ecosystem intelligence (restored from MASTER v1)
require_relative "prescan"            # Situational awareness ritual (restored from MASTER v1)

# Auto-fixer (restored from MASTER)
require_relative "auto_fixer"

# Web browsing (restored from MASTER)
require_relative "web"

# Speech (unified TTS - replaces edge_tts, piper_tts, stream_tts, tts)
require_relative "speech"

# Media generation and post-processing bridges
require_relative "postpro_bridge"
require_relative "repligen_bridge"

# External services
%w[weaviate replicate cinematic].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end

# Agents
require_relative "agent"
require_relative "agent_pool"
require_relative "agent_firewall"

# Meta/Self-improvement
require_relative "code_review"
require_relative "llm_friendly"
require_relative "learnings"
require_relative "session_capture"
require_relative "enforcement"
require_relative "language_axioms"
require_relative "file_processor"
require_relative "reflow"
require_relative "audit"
require_relative "cross_ref"
require_relative "learning_feedback"
require_relative "learning_quality"

# Quality & Analysis (restored from MASTER)
require_relative "violations"
require_relative "smells"
require_relative "bug_hunting"
require_relative "planner"
require_relative "reflection_memory"

# Generators (restored from historical features)
require_relative "generators/html"

# Quality gates (restored from MASTER)
require_relative "framework/quality_gates"

# Web UI
%w[server].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end
