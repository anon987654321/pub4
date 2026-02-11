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
require_relative "paths"
require_relative "result"  # includes Utils
require_relative "logging"  # Unified logging
require_relative "db_jsonl"
require_relative "llm"  # includes Timeouts, ContextWindow
require_relative "memory"
require_relative "session"  # includes SessionCapture
require_relative "rubocop_detector"

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
require_relative "boot"  # includes Pledge

# UI & NN/g compliance
require_relative "ui"
require_relative "help"  # includes Onboarding
require_relative "progress"
require_relative "undo"
require_relative "dashboard"
require_relative "commands"  # includes Keybindings, Autocomplete, ProblemSolver
require_relative "confirmations"
require_relative "error_suggestions"
require_relative "nng_checklist"

# Pipeline
require_relative "stages"
require_relative "executor"  # includes Prescan
require_relative "pipeline"  # includes Questions
require_relative "hooks"
require_relative "convergence"
require_relative "workflow_engine"

# Deliberation engines
require_relative "chamber"  # includes Swarm
require_relative "creative_chamber"

# Tools
require_relative "shell"  # includes GHHelper
require_relative "introspection"  # Unified introspection (includes SelfMap, SelfCritique, SelfRepair, SelfTest)
require_relative "evolve"  # includes Momentum
require_relative "validator"
require_relative "file_processor"  # includes FileHygiene, Reflow
require_relative "queue"
require_relative "engine"
require_relative "agent_autonomy"
require_relative "personas"
require_relative "harvester"

# Auto-fixer
require_relative "auto_fixer"

# Web browsing
require_relative "web"

# Speech (unified TTS)
require_relative "speech"

# External services
%w[weaviate replicate cinematic].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end

# Agents
require_relative "agent"  # includes AgentPool, AgentFirewall
require_relative "agent_autonomy"

# Meta/Self-improvement
require_relative "code_review"
require_relative "llm_friendly"
require_relative "learnings"  # includes LearningQuality, LearningFeedback, ReflectionMemory
require_relative "enforcement"  # includes QualityStandards, LanguageAxioms, AxiomStats
require_relative "audit"
require_relative "cross_ref"

# Quality & Analysis
require_relative "violations"
require_relative "smells"
require_relative "bug_hunting"
require_relative "planner"

# Generators
require_relative "generators/html"

# Quality gates
require_relative "framework/quality_gates"

# Web UI
%w[server].each do |mod|
  begin
    require_relative mod
  rescue LoadError, StandardError => e
    warn "MASTER: #{mod} unavailable (#{e.message})"
  end
end
