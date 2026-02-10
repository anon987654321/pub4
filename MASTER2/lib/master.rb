# frozen_string_literal: true

module MASTER
  VERSION = "1.0.0"
  def self.root = File.expand_path("..", __dir__)
end

require "fileutils"

# Auto-install missing gems first
require_relative "auto_install"
# Gems auto-install on first LoadError — no blocking boot

# Core
require_relative "utils"
require_relative "paths"
require_relative "result"
require_relative "quality_standards"
require_relative "logging"
require_relative "dmesg"
require_relative "log"  # Unified logging facade
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

# Deliberation engines
require_relative "chamber"
require_relative "swarm"

# Tools
require_relative "shell"
require_relative "introspection"
require_relative "problem_solver"
require_relative "evolve"
require_relative "converge"
require_relative "momentum"
require_relative "validator"
require_relative "self_map"
require_relative "file_hygiene"
require_relative "planner_helper"
require_relative "gh_helper"

# Auto-fixer (restored from MASTER)
require_relative "auto_fixer"

# Web browsing (restored from MASTER)
require_relative "web"

# Speech (unified TTS - replaces edge_tts, piper_tts, stream_tts, tts)
require_relative "speech"

# External services
%w[weaviate replicate].each do |mod|
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
require_relative "enforcement"
require_relative "language_axioms"
require_relative "file_processor"
require_relative "reflow"
require_relative "self_test"
require_relative "audit"
require_relative "confirmation_gate"
require_relative "cross_ref"
require_relative "self_repair"
require_relative "learning_feedback"
require_relative "learning_quality"

# Quality & Analysis (restored from MASTER)
require_relative "violations"
require_relative "smells"
require_relative "bug_hunting"
require_relative "planner"
require_relative "self_critique"
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
