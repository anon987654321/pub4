# frozen_string_literal: true

module MASTER
  VERSION = "1.0.0"
  def self.root = File.expand_path("..", __dir__)
end

require "fileutils"

# Auto-install missing gems first
require_relative "auto_install"
MASTER::AutoInstall.install_gems if MASTER::AutoInstall.missing_gems.any?

# Core
require_relative "utils"
require_relative "paths"
require_relative "result"
require_relative "db_jsonl"
require_relative "llm"
require_relative "memory"
require_relative "session"
require_relative "pledge"

# UI & NN/g compliance
require_relative "ui"
require_relative "help"
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

# Pipeline
require_relative "boot"
require_relative "stages"
require_relative "pipeline"

# Deliberation engines
require_relative "chamber"
require_relative "creative_chamber"
require_relative "swarm"

# Tools
require_relative "shell"
require_relative "introspection"
require_relative "problem_solver"
require_relative "evolve"
require_relative "converge"
require_relative "edge_tts"
require_relative "momentum"
require_relative "validator"
require_relative "self_map"
require_relative "file_hygiene"

# External services
require_relative "weaviate"
require_relative "replicate"

# Agents
require_relative "agent"
require_relative "agent_pool"
require_relative "agent_firewall"

# Meta/Self-improvement
require_relative "code_review"
require_relative "llm_friendly"
require_relative "learnings"
require_relative "enforcement"
require_relative "file_processor"
require_relative "reflow"
require_relative "self_test"

# Optional
require_relative "server"
