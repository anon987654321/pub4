# frozen_string_literal: true

# MASTER v50.8 - Modular AI System for Technical Excellence and Reasoning

module MASTER
  VERSION = '50.8'
  ROOT = File.expand_path('..', __dir__)

  autoload :Paths,     'paths'
  autoload :Result,    'result'
  autoload :Principle, 'principle'
  autoload :Persona,   'persona'
  autoload :Sandbox,   'sandbox'
  autoload :Boot,      'boot'
  autoload :LLM,       'llm'
  autoload :Engine,    'engine'
  autoload :Memory,    'memory'
  autoload :Safety,    'safety'
  autoload :Converge,  'converge'
  autoload :Smells,    'smells'
  autoload :OpenBSD,   'openbsd'
  autoload :Web,       'web'
  autoload :Replicate, 'replicate'
  autoload :Server,    'server'
  autoload :CLI,       'cli'

  class << self
    def boot
      Boot.run
    end

    def root
      ROOT
    end
  end
end
