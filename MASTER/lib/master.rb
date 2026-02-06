# frozen_string_literal: true

# MASTER - The LLM Operating System
# A constitutional AI framework in pure Ruby

module MASTER
  VERSION = '52.0'
  CODENAME = 'REFLEXION'
  ROOT = File.expand_path('..', __dir__)
  LIB = __dir__
  BOOT_TIME = Time.now

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
  autoload :CLI,         "#{LIB}/cli"
  autoload :Chamber,     "#{LIB}/chamber"
  autoload :CreativeChamber, "#{LIB}/creative_chamber"
  autoload :Introspection,   "#{LIB}/introspection"
  autoload :Evolve,      "#{LIB}/evolve"
  autoload :Audio,       "#{LIB}/audio"
  autoload :TTS,         "#{LIB}/tts"
  autoload :ParallelTTS, "#{LIB}/tts"
  autoload :RateLimiter, "#{LIB}/server"
  autoload :Weaviate,    "#{LIB}/weaviate"
  autoload :AutoInstall, "#{LIB}/auto_install"
  autoload :BugHunting,  "#{LIB}/bug_hunting"
  autoload :UI,          "#{LIB}/ui"
  autoload :SelfAwareness, "#{LIB}/self_awareness"
  autoload :ConvergenceLoop, "#{LIB}/convergence_loop"
  autoload :MultiFileAnalyzer, "#{LIB}/multi_file_analyzer"
  autoload :AutoFixer,   "#{LIB}/auto_fixer"
  autoload :Planner,     "#{LIB}/planner"
  autoload :Autonomy,    "#{LIB}/autonomy"
  autoload :PromptAutonomy, "#{LIB}/prompt_autonomy"
  autoload :AgentAutonomy,  "#{LIB}/agent_autonomy"
  autoload :Dmesg,       "#{LIB}/dmesg"
  autoload :Momentum,    "#{LIB}/momentum"
  autoload :ProblemSolver, "#{LIB}/problem_solver"
  autoload :Shell,       "#{LIB}/shell"
  autoload :Layout,      "#{LIB}/layout"

  # Core modules (lib/core/)
  CORE = "#{LIB}/core"
  autoload :Context,            "#{CORE}/context"
  autoload :Executor,           "#{CORE}/executor"
  autoload :SessionRecovery,    "#{CORE}/session_recovery"
  autoload :SessionPersistence, "#{CORE}/session_persistence"
  autoload :SemanticCache,      "#{CORE}/semantic_cache"
  autoload :PrincipleAutoloader, "#{CORE}/principle_autoloader"
  autoload :TokenStreamer,      "#{CORE}/token_streamer"
  autoload :Colors,             "#{CORE}/colors"
  autoload :CommandHandler,     "#{CORE}/command_handler"
  autoload :REPL,               "#{CORE}/repl"
  autoload :SSEEndpoint,        "#{CORE}/sse_endpoint"
  autoload :OrbStream,          "#{CORE}/orb_stream"
  autoload :ImageComparison,    "#{CORE}/image_comparison"
  autoload :OpenBSDPledge,      "#{CORE}/openbsd_pledge"
  autoload :Audit,              "#{CORE}/audit"
  autoload :Validator,          "#{CORE}/validator"
  
  # Reflexion System (NEW)
  autoload :ReflectionMemory,   "#{CORE}/reflection_memory"
  autoload :SelfCritique,       "#{CORE}/self_critique"
  autoload :AdaptiveRetry,      "#{CORE}/adaptive_retry"
  autoload :ReActExecutor,      "#{CORE}/react_executor"
  
  # Phase 2: Event Bus and Actors (NEW - Microkernel + Event-Driven Architecture)
  module Events
    LIB = MASTER::LIB
    autoload :Event,     "#{LIB}/events/event"
    autoload :Bus,       "#{LIB}/events/bus"
  end
  
  module Actors
    LIB = MASTER::LIB
    autoload :Base,      "#{LIB}/actors/base"
    autoload :Registry,  "#{LIB}/actors/registry"
  end
  
  module Kernel
    LIB = MASTER::LIB
    autoload :Boot,      "#{LIB}/kernel/boot"
  end

  # Dreams modules
  DREAMS = "#{LIB}/dreams"
  autoload :SocialDreamer,      "#{DREAMS}/social_dreamer"

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
    
    # Reflexion API
    def reflect(task:, model: 'smart', max_retries: 3)
      Core::AdaptiveRetry.execute_with_reflection(task: task, max_attempts: max_retries) do |context, attempt|
        LLM.call(context, model: model)
      end
    end
    
    def react(goal:, model: 'smart', max_steps: 15)
      Core::ReActExecutor.execute(goal: goal, model: model, max_steps: max_steps)
    end
  end
end
