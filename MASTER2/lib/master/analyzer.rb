module MASTER
  module Analyzer
    REGISTRY = {}

    def self.register(name, analyzer)
      REGISTRY[name] = analyzer
    end

    def self.run(name, target)
      analyzer = REGISTRY[name]
      raise "unknown analyzer #{name}" unless analyzer
      analyzer.call(target)
    end

    def self.list
      REGISTRY.keys
    end
  end
end
