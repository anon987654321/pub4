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
  rescue LoadError, StandardError => e
    return if silent

    name = label || File.basename(path)
    warn "MASTER: #{name} unavailable (#{e.message})"
    Logging.warn("#{name} unavailable", error: e.message) if defined?(Logging)
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
require_relative "boot/modes"   # adjacent to boot — VISUAL_HIERARCHY fix

# Core
require_relative "result"
require_relative "logging"
require_relative "db_jsonl"
require_relative "event_bus"
require_relative "security/sanitizer"
require_relative "security/permissions"
require_relative "llm"
require_relative "personas"
require_relative "session"
require_relative "pledge"
require_relative "rubocop_detector"

MASTER.safe_require("parser/multi_language")
%w[nlu conversation].each { |dep| MASTER.safe_require(dep, silent: true) }

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
require_relative "lane"          # Lane Queue: serial execution guard

# Executor
require_relative "executor"

# Pipeline
require_relative "pipeline"
require_relative "hooks"
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
require_relative "review"
require_relative "learnings"
require_relative "file_processor"
require_relative "reflow"
require_relative "multi_refactor"

# Generators
require_relative "html_generator"

# Quality gates
require_relative "quality_gates"

# Self-governance
require_relative "axiom_resolver"
require_relative "dependency_map"
require_relative "convergence_tracker"
require_relative "pressure_pass"
require_relative "self_refactor"
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
require_relative "openbsd_validator"
require_relative "violation_hooks"
require_relative "learned_smells"
require_relative "conflict_resolver"
require_relative "phase_gates"

MASTER.safe_require("server")

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

# Proactive autonomy — ON by default (OpenClaw: acts without prompting)
# Disable explicitly: MASTER_HEARTBEAT=false
if ENV.fetch("MASTER_HEARTBEAT", "true") != "false"
  MASTER::Triggers.install_defaults
  MASTER::Scheduler.load
  MASTER::Heartbeat.register("scheduler") { MASTER::Scheduler.tick }
  MASTER::Heartbeat.start(interval: (ENV["MASTER_HEARTBEAT_INTERVAL"] || "300").to_i)
end
