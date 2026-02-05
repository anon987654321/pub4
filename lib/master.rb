# frozen_string_literal: true

# LLM-Ruby - The LLM Operating System
# A constitutional AI framework in pure Ruby

module MASTER
  VERSION = '50.9'
  CODENAME = 'LLM-Ruby'
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
  autoload :OpenBSD,     "#{LIB}/openbsd"
  autoload :Web,         "#{LIB}/web"
  autoload :Replicate,   "#{LIB}/replicate"
  autoload :Server,      "#{LIB}/server"
  autoload :CLI,         "#{LIB}/cli"
  autoload :Chamber,     "#{LIB}/chamber"
  autoload :CreativeChamber, "#{LIB}/creative_chamber"
  autoload :Introspection,   "#{LIB}/introspection"
  autoload :Evolve,      "#{LIB}/evolve"
  autoload :Queue,       "#{LIB}/queue"

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
