# frozen_string_literal: true

require 'readline'
require 'fileutils'

module MASTER
  class CLI
    include Colors
    
    attr_reader :llm, :engine, :repl, :total_cost
    
    # Command lists
    COMMANDS = %w[ask audit chamber clear converge evolve exit help introspect quit].freeze
    ALIASES = { 'q' => 'quit', 'h' => 'help', 'c' => 'chamber', 'e' => 'evolve' }.freeze
    QUOTES = ["Simplicity is the ultimate sophistication.", "Make it work, make it right, make it fast."].freeze
    
    def initialize(llm: LLM.new)
      @llm = llm
      @engine = Engine.new(llm)
      @repl = REPL.new(self)
      @total_cost = 0.0
    end
    
    def run
      repl.start
    end
  end
end
