module MASTER
  class Agent
    def initialize(router:, tools:, memory:)
      @router = router
      @tools = tools
      @memory = memory
    end

    def run(input)
      response = @router.call(input)
      @memory.store(input, response)
      response
    end

    def analyze(type, code)
      Analyzer.run(type, code)
    end
  end
end
