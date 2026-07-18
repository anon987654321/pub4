# frozen_string_literal: true

require "ruby_llm/mcp" if $LOAD_PATH.any? { |p| File.exist?(File.join(p, "ruby_llm/mcp.rb")) }

module Master
  module Io
    # McpCoordinator — manages MCP server connections and exposes
    # their tools to the agent alongside MASTER's native tools.
    # data/mcp_servers.yml defines servers.
    class McpCoordinator
      CONFIG_PATH = "data/mcp_servers.yml".freeze

      def initialize(root:, event_bus: nil)
        @root = root
        @bus = event_bus
        @clients = {}
      end

      # Connect to all configured MCP servers. Non-fatal on failure.
      def connect_all
        servers = load_servers
        servers.each do |name, cfg|
          connect(name, cfg)
        end
        @bus&.publish("mcp:connected", count: @clients.size)
      rescue StandardError => e
        @bus&.publish("mcp:error", error: e.message)
      end

      # Return all tools from all connected MCP servers as RubyLLM::Tool wrappers.
      def tools
        @clients.flat_map do |name, client|
          client.tools.filter_map do |tool|
            McpToolWrapper.new(name:, client:, tool:)
          rescue StandardError => e
            @bus&.publish("mcp:tool_wrap_error", name:, error: e.message)
            nil
          end
        end
      rescue StandardError => e
        @bus&.publish("mcp:tools_error", error: e.message)
        []
      end

      def connected?
        @clients.any?
      end

      def server_names
        @clients.keys
      end

      private

      def connect(name, cfg)
        return unless cfg.is_a?(Hash) && cfg["enabled"] != false

        transport = (cfg["transport"] || "stdio").to_sym
        mcp_config = mcp_transport_config(transport, cfg)
        return unless mcp_config

        client = build_mcp_client(name, transport, mcp_config)
        client.start
        @clients[name] = client
        @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
      rescue StandardError => e
        @bus&.publish("mcp:server_failed", name:, error: e.message)
      end

      def mcp_transport_config(transport, cfg)
        case transport
        when :stdio
          { command: cfg["command"], args: cfg["args"] || [] }
        when :sse
          { url: cfg["url"] }
        end
      end

      def build_mcp_client(name, transport, mcp_config)
        ::RubyLLM::MCP::Client.new(
          name: name,
          transport_type: transport,
          config: mcp_config,
          start: false
        )
      end

      def load_servers
        path = File.join(@root, CONFIG_PATH)
        return {} unless File.exist?(path)
        require "yaml"
        data = Master.load_yaml(path) || {}
        data.fetch("servers", {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "mcp_coordinator.load_servers", event_bus: @bus, path:)
        {}
      end
    end

    # Wraps an MCP tool as a RubyLLM::Tool for the agent's tool list.
    if defined?(::RubyLLM::Tool)
      class McpToolWrapper < ::RubyLLM::Tool
        def initialize(name:, client:, tool:)
          @mcp_name = name
          @mcp_client = client
          @mcp_tool = tool
        end

        def name
          "#{@mcp_name}__#{@mcp_tool.name}"
        end

        def description
          "[MCP:#{@mcp_name}] #{@mcp_tool.description}"
        end

        def execute(**params)
          result = @mcp_client.call_tool(@mcp_tool.name, params)
          result.respond_to?(:content) ? result.content : result.to_s
        rescue StandardError => e
          "MCP tool error: #{e.message}"
        end
      end
    end
  end
end
