require_relative "tools/registry"

module MASTER
  module ToolDispatch
    TOOLS = MASTER::Tools::REGISTRY

    def self.call(name, args)
      tool = TOOLS[name.to_sym]
      raise MASTER::ToolMissing, "tool not found: #{name}" unless tool
      tool.call(args)
    end
  end
end
