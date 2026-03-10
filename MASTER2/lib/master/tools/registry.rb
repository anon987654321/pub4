module MASTER
  module Tools
    REGISTRY = {}

    def self.register(name, tool)
      REGISTRY[name.to_sym] = tool
    end

    def self.list
      REGISTRY.keys
    end
  end
end
