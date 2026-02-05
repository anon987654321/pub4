# frozen_string_literal: true

# MASTER v50.8 - Modular AI System for Technical Excellence and Reasoning

module MASTER
  VERSION = '50.8'
  ROOT = File.expand_path('..', __dir__)

  autoload :Result,    'result'
  autoload :Principle, 'principle'
  autoload :Persona,   'persona'
  autoload :Sandbox,   'sandbox'
  autoload :Boot,      'boot'
  autoload :LLM,       'llm'
  autoload :Engine,    'engine'
  autoload :Memory,    'memory'
  autoload :Smells,    'smells'
  autoload :OpenBSD,   'openbsd'
  autoload :Web,       'web'
  autoload :Replicate, 'replicate'
  autoload :Server,    'server'
  autoload :CLI,       'cli'
  autoload :App,       'app'

  # New modules for multi-agent system
  module Agents
    autoload :BaseAgent,          'agents/base_agent'
    autoload :SecurityAgent,      'agents/security_agent'
    autoload :PerformanceAgent,   'agents/performance_agent'
    autoload :StyleAgent,         'agents/style_agent'
    autoload :ArchitectureAgent,  'agents/architecture_agent'
    autoload :ReviewCrew,         'agents/review_crew'
  end

  module Workflow
    autoload :Engine, 'workflow/engine'
  end

  module Optimizer
    autoload :CostAware, 'optimizer/cost_aware'
  end

  class << self
    def boot
      Boot.run
    end

    def root
      ROOT
    end
  end
end

# Load all lib files
Dir[File.join(__dir__, '*.rb')].each do |f|
  require f unless f.end_with?('master.rb')
end
