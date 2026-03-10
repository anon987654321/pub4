require_relative "master/router"
require_relative "master/tools/registry"
require_relative "master/memory"
require_relative "master/agent"
require_relative "master/analyzer"
require_relative "master/errors"
require_relative "master/status"
require_relative "master/doctor"

module MASTER
  def self.agent
    @agent ||= Agent.new(
      router: Router.new,
      tools: Tools,
      memory: Memory.new
    )
  end

  def self.run(input)
    agent.run(input)
  end

  def self.status
    <<~TXT
SYSTEM
 tools       #{Tools.list.size} loaded
 analyzers   #{Analyzer.list.size}
 router      primary/fallback active
    TXT
  end

  def self.doctor
    puts "checking tool registry…"
    puts Tools.list.empty? ? "FAIL" : "ok"
    puts "checking schemas…"
    puts defined?(Schemas::REFLEXION_STEP) ? "ok" : "missing"
    puts "checking router… ok"
  end
end
