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
MASTER.safe_require("review")
MASTER.safe_require("learnings")
MASTER.safe_require("file_processor")
MASTER.safe_require("reflow")
MASTER.safe_require("multi_refactor")

# Generators
require_relative "html_generator"

# Quality gates
MASTER.safe_require("quality_gates")

# Self-governance
MASTER.safe_require("axiom_resolver")
MASTER.safe_require("dependency_map")
MASTER.safe_require("convergence_tracker")
MASTER.safe_require("pressure_pass")
MASTER.safe_require("self_refactor")
MASTER.safe_require("security/injection_guard")
MASTER.safe_require("agent/credential_store")
MASTER.safe_require("session/reminders")
MASTER.safe_require("executor/tool_protocol")
MASTER.safe_require("review/tool_scanner")
MASTER.safe_require("llm/hesitation_detector")
MASTER.safe_require("agent/behavior_monitor")
MASTER.safe_require("session/per_step_reflection")
MASTER.safe_require("mcp_server")
MASTER.safe_require("introspection/friction_recorder")
MASTER.safe_require("introspection/session_retrospective")

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
