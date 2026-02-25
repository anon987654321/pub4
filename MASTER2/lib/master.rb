# frozen_string_literal: true

module MASTER
  VERSION = "2.0.0"
  def self.root = File.expand_path("..", __dir__)

  def self.source_files
    Dir.glob(File.join(root, "lib", "**", "*.rb"))
  end

  # Safe require helper for optional dependencies
  def self.safe_require(path, label: nil, silent: false)
    require_relative path
  rescue LoadError, StandardError => err
    return if silent

    name = label || File.basename(path)
    warn "MASTER: #{name} unavailable (#{err.message})"
    Logging.warn("#{name} unavailable", error: err.message) if defined?(Logging)
  end
end

require "fileutils"
require "time"
require "shellwords"

require_relative "utils"
require_relative "decision_engine"
require_relative "syntax_validator"
require_relative "paths"
require_relative "platform_check"
require_relative "single_instance"
require_relative "text_hygiene"
require_relative "command_registry"
require_relative "auto_install"
require_relative "boot"

# Core
require_relative "result"
require_relative "logging"
require_relative "db_jsonl"
require_relative "event_bus"
require_relative "capabilities"
require_relative "security/sanitizer"
require_relative "security/permissions"
require_relative "llm"
require_relative "personas"
require_relative "session"
require_relative "pledge"
require_relative "rubocop_detector"

# Multi-language parsing (now in MASTER2); NLU and conversation are optional stubs
MASTER.safe_require("parser/multi_language")
# nlu and conversation are MASTER v4 stubs -- silently absent, not an error
%w[../../lib/nlu ../../lib/conversation].each do |dep|
  MASTER.safe_require(dep, silent: true)
end

# Safe Autonomy Architecture
require_relative "staging"

# UI & NN/g compliance
require_relative "ui"
require_relative "output"
require_relative "zsh_pattern_injector"
require_relative "project_memory"
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

# Proactive autonomy (stolen from OpenClaw)
require_relative "heartbeat"
require_relative "scheduler"
require_relative "triggers"

# Deliberation engines
require_relative "chamber"

# Tools
require_relative "shell"
require_relative "analysis"
require_relative "problem_solver"
require_relative "evolve"
require_relative "queue"
require_relative "harvester"

# Web browsing
require_relative "web"

# Speech
require_relative "speech"

# Media generation and post-processing bridges
require_relative "bridges"

# External services
%w[weaviate replicate cinematic semantic_cache].each do |mod|
  MASTER.safe_require(mod)
end

# Agents
require_relative "agent"

# Meta/Self-improvement
require_relative "scan"
require_relative "review"
require_relative "learnings"
require_relative "file_processor"
require_relative "reflow"
require_relative "multi_refactor"

# Generators
require_relative "html_generator"

# Quality gates
require_relative "quality_gates"

# Self-refactoring infrastructure
require_relative "axiom_resolver"
require_relative "dependency_map"
require_relative "convergence_tracker"
require_relative "pressure_pass"
require_relative "self_refactor"
require_relative "nlu"
require_relative "conversation"
require_relative "security/injection_guard"
require_relative "agent/credential_store"
require_relative "session/reminders"
require_relative "executor/tool_protocol"
require_relative "review/tool_scanner"
require_relative "llm/hesitation_detector"
require_relative "agent/behavior_monitor"
require_relative "session/per_step_reflection"
require_relative "mcp_server"
require_relative "introspection/friction_recorder"
require_relative "introspection/session_retrospective"
require_relative "boot/modes"

# Web UI
%w[server].each do |mod|
  MASTER.safe_require(mod)
end

Scan = MASTER::Scan if defined?(MASTER::Scan)

# Boot-time self-check
if ENV["MASTER_SELF_CHECK"] == "true" && defined?(MASTER::Enforcement)
  Thread.new do
    sleep (ENV["MASTER_SELF_CHECK_DELAY"] || "1").to_i
    begin
      MASTER::Enforcement.self_check!
    rescue StandardError => err
      warn "MASTER: self_check! failed (#{err.message})"
    end
  end
end

# Boot-time proactive autonomy setup
if ENV["MASTER_HEARTBEAT"] == "true"
  MASTER::Triggers.install_defaults
  MASTER::Scheduler.load
  MASTER::Heartbeat.register("scheduler") { MASTER::Scheduler.tick }
  MASTER::Heartbeat.start(interval: (ENV["MASTER_HEARTBEAT_INTERVAL"] || "60").to_i)
end
