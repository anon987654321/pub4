# frozen_string_literal: true

module MASTER
  VERSION = "2.0.0"
  def self.root = File.expand_path("..", __dir__)
end

require "fileutils"
require "time"
require "shellwords"

require_relative "utils"
require_relative "decision_engine"
require_relative "syntax_validator"
require_relative "paths"
require_relative "single_instance"
require_relative "text_hygiene"
require_relative "command_registry"
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
    Logging.warn("#{mod} unavailable", error: e.message) if defined?(Logging)
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

# Boot-time proactive autonomy setup
if ENV["MASTER_HEARTBEAT"] == "true"
  MASTER::Triggers.install_defaults
  MASTER::Scheduler.load
  MASTER::Heartbeat.register("scheduler") { MASTER::Scheduler.tick }
  MASTER::Heartbeat.start(interval: (ENV["MASTER_HEARTBEAT_INTERVAL"] || "60").to_i)
end
