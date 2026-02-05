# frozen_string_literal: true

# MASTER - The LLM Operating System
# A constitutional AI framework in pure Ruby

module MASTER
  VERSION = '51.0'
  CODENAME = 'MASTER'
  ROOT = File.expand_path('..', __dir__)
  LIB = __dir__

  autoload :Paths,       "#{LIB}/paths"
  autoload :Result,      "#{LIB}/result"
  autoload :Principle,   "#{LIB}/principle"
  autoload :Persona,     "#{LIB}/persona"
  autoload :Boot,        "#{LIB}/boot"
  autoload :LLM,         "#{LIB}/llm"
  autoload :Engine,      "#{LIB}/engine"
  autoload :Memory,      "#{LIB}/memory"
  autoload :Safety,      "#{LIB}/safety"
  autoload :Converge,    "#{LIB}/converge"
  autoload :Smells,      "#{LIB}/smells"
  autoload :Violations,  "#{LIB}/violations"
  autoload :OpenBSD,     "#{LIB}/openbsd"
  autoload :Web,         "#{LIB}/web"
  autoload :Replicate,   "#{LIB}/replicate"
  autoload :Server,      "#{LIB}/server"
  autoload :Violations,  "#{LIB}/violations"
  autoload :CLI,         "#{LIB}/cli"
  autoload :Chamber,     "#{LIB}/chamber"
  autoload :CreativeChamber, "#{LIB}/creative_chamber"
  autoload :Introspection,   "#{LIB}/introspection"
  autoload :Evolve,      "#{LIB}/evolve"
  autoload :Audio,      "#{LIB}/audio"
  autoload :TTS,        "#{LIB}/tts"
  autoload :ParallelTTS, "#{LIB}/tts"
  autoload :RateLimiter, "#{LIB}/server"

  # Core modules (lib/core/)
  CORE = "#{LIB}/core"
  autoload :Context,            "#{CORE}/context"
  autoload :Executor,           "#{CORE}/executor"
  autoload :SessionRecovery,    "#{CORE}/session_recovery"
  autoload :SessionPersistence, "#{CORE}/session_persistence"
  autoload :SemanticCache,      "#{CORE}/semantic_cache"
  autoload :PrincipleAutoloader, "#{CORE}/principle_autoloader"
  autoload :TokenStreamer,      "#{CORE}/token_streamer"
  autoload :SSEEndpoint,        "#{CORE}/sse_endpoint"
  autoload :OrbStream,          "#{CORE}/orb_stream"
  autoload :ImageComparison,    "#{CORE}/image_comparison"
  autoload :OpenBSDPledge,      "#{CORE}/openbsd_pledge"
  autoload :Audit,              "#{CORE}/audit"

  # Framework modules
  module Framework
    LIB = MASTER::LIB
    autoload :BehavioralRules,     "#{LIB}/framework/behavioral_rules"
    autoload :CopilotOptimization, "#{LIB}/framework/copilot_optimization"
    autoload :QualityGates,        "#{LIB}/framework/quality_gates"
    autoload :UniversalStandards,  "#{LIB}/framework/universal_standards"
    autoload :WorkflowEngine,      "#{LIB}/framework/workflow_engine"
  end

  # Plugin modules
  module Plugins
    LIB = MASTER::LIB
    autoload :AIEnhancement,     "#{LIB}/plugins/ai_enhancement"
    autoload :BusinessStrategy,  "#{LIB}/plugins/business_strategy"
    autoload :DesignSystem,      "#{LIB}/plugins/design_system"
    autoload :WebDevelopment,    "#{LIB}/plugins/web_development"
  end

  class << self
    def boot
      Boot.run
    end

    def root
      ROOT
    end

    def codename
      CODENAME
    end
  end
end
