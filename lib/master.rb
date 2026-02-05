# frozen_string_literal: true

# MASTER v50.8 - Modular AI System for Technical Excellence and Reasoning

module MASTER
  VERSION = '50.8'
  ROOT = File.expand_path('..', __dir__)
  LIB = __dir__

  autoload :Paths,     "#{LIB}/paths"
  autoload :Result,    "#{LIB}/result"
  autoload :Principle, "#{LIB}/principle"
  autoload :Persona,   "#{LIB}/persona"
  autoload :Sandbox,   "#{LIB}/sandbox"
  autoload :Boot,      "#{LIB}/boot"
  autoload :LLM,       "#{LIB}/llm"
  autoload :Engine,    "#{LIB}/engine"
  autoload :Memory,    "#{LIB}/memory"
  autoload :Safety,    "#{LIB}/safety"
  autoload :Converge,  "#{LIB}/converge"
  autoload :Smells,    "#{LIB}/smells"
  autoload :OpenBSD,   "#{LIB}/openbsd"
  autoload :Web,       "#{LIB}/web"
  autoload :Replicate, "#{LIB}/replicate"
  autoload :Server,    "#{LIB}/server"
  autoload :CLI,       "#{LIB}/cli"

  class << self
    def boot
      Boot.run
    end

    def root
      ROOT
    end
  end
end
