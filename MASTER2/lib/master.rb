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
require_relative "result"  # Now includes Utils
require_relative "logging"  # Unified logging (replaces log.rb, logging.rb, dmesg.rb)
require_relative "db_jsonl"
require_relative "llm"  # Now includes Timeouts and ContextWindow
require_relative "memory"
require_relative "session"  # Now includes session_capture
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
require_relative "help"  # Now includes onboarding, nng_checklist
require_relative "autocomplete"
require_relative "progress"
require_relative "undo"
require_relative "dashboard"
require_relative "commands"  # Now includes keybindings
require_relative "confirmations"
require_relative "error_suggestions"

# Pipeline stages (needed by executor)
require_relative "boot"  # Now includes pledge
require_relative "stages"

# Executor (ReAct pattern - default behavior)
require_relative "executor"  # Now includes prescan

# Pipeline
require_relative "pipeline"  # Now includes questions
require_relative "hooks"
require_relative "convergence"
require_relative "workflow_engine"

# Deliberation engines
require_relative "chamber"  # Now includes swarm
require_relative "creative_chamber"  # Creative ideation engine (restored from MASTER v1)

# Tools
require_relative "shell"  # Now includes gh_helper
require_relative "introspection"  # Includes self_map functionality (consolidated)
require_relative "problem_solver"
require_relative "evolve"  # Now includes momentum
require_relative "validator"
require_relative "queue"              # Priority task queue (restored from MASTER v1)
require_relative "engine"             # Unified scan facade (restored from MASTER v1)
require_relative "agent_autonomy"     # Goal decomposition & self-correction (restored from MASTER v1)
require_relative "personas"           # Persona management (restored from MASTER v1)
require_relative "harvester"          # Ecosystem intelligence (restored from MASTER v1)

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
require_relative "agent"  # Now includes agent_pool
require_relative "agent_firewall"

# Meta/Self-improvement
require_relative "code_review"
require_relative "llm_friendly"
require_relative "learnings"  # Now includes learning_feedback, learning_quality, reflection_memory
require_relative "enforcement"  # Now includes quality_standards, language_axioms, axiom_stats
require_relative "file_processor"  # Now includes file_hygiene
require_relative "reflow"
require_relative "introspection"  # Unified introspection (includes SelfMap, SelfCritique, SelfRepair, SelfTest)
require_relative "audit"
require_relative "cross_ref"

# Quality & Analysis (restored from MASTER)
require_relative "violations"
require_relative "smells"
require_relative "bug_hunting"
require_relative "planner"

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
