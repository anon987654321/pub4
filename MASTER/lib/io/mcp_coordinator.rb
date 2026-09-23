# frozen_string_literal: true

require "timeout"
require "ruby_llm/mcp" if $LOAD_PATH.any? { |p| File.exist?(File.join(p, "ruby_llm/mcp.rb")) }

module Master
  module Io
    # McpCoordinator — manages MCP server connections and exposes
    # their tools to the agent alongside MASTER's native tools.
    # data/mcp_servers.yml defines servers.
    #
    # MCP is an external effect surface, not an escape hatch. Every exposed
    # tool is therefore wrapped with the same Governor used by native tools,
    # given a bounded call time, and emitted on the event bus.
    class McpCoordinator
      CONFIG_PATH = "data/mcp_servers.yml".freeze
      DEFAULT_TIMEOUT = 60
      DEFAULT_TIER = :dangerous

      def initialize(root:, event_bus: nil, governor: nil)
        @root = root
        @bus = event_bus
        @governor = governor
        @clients = {}
        @server_config = {}
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
            McpToolWrapper.new(
              name:,
              client:,
              tool:,
              governor: @governor,
              event_bus: @bus,
              timeout: @server_config.fetch(name, {}).fetch("timeout_seconds", DEFAULT_TIMEOUT),
              tier: @server_config.fetch(name, {}).fetch("tier", DEFAULT_TIER).to_sym,
            )
          rescue StandardError => e
            @bus&.publish("mcp:tool_wrap_error", name:, error: e.message)
            nil
          end
        end
      rescue StandardError => e
        @bus&.publish("mcp:tools_error", error: e.message)
        []
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
        @server_config[name] = cfg
        @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
      rescue StandardError => e
        @bus&.publish("mcp:server_failed", name:, error: e.message)
      end

      def mcp_transport_config(transport, cfg)
        case transport
        when :stdio
          { command: cfg["command"], args: cfg["args"] || [] }
        # Not passed through SsrfGuard. mcp_servers.yml is operator configuration that can already
        # name a stdio command, which is more than a URL can do, and the ordinary SSE server listens
        # on loopback, which the guard refuses.
        when :sse
          { url: cfg["url"] }
        end
      end

      def build_mcp_client(name, transport, mcp_config)
        ::RubyLLM::MCP::Client.new(
          name:,
          transport_type: transport,
          config: mcp_config,
          start: false,
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

    # Wraps an MCP tool as a RubyLLM::Tool for the agent. MCP cannot bypass
    # MASTER's approval/rate-limit boundary merely by arriving through a
    # different protocol.
    if defined?(::RubyLLM::Tool)
      class McpToolWrapper < ::RubyLLM::Tool
        def initialize(name:, client:, tool:, governor: nil, event_bus: nil, timeout: 60, tier: :dangerous)
          @mcp_name = name
          @mcp_client = client
          @mcp_tool = tool
          @governor = governor
          @bus = event_bus
          @timeout = timeout.to_i.clamp(1, 600)
          @tier = tier.to_sym
        end

        def name
          "#{@mcp_name}__#{@mcp_tool.name}"
        end

        def description
          "[MCP:#{@mcp_name}] #{@mcp_tool.description} [#{@tier}]"
        end

        def execute(**params)
          permit = @governor&.permit?(name, @tier, description)
          return "MCP tool refused: #{permit.message}" if permit && !permit.ok?

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @bus&.publish("mcp:tool_before", server: @mcp_name, tool: @mcp_tool.name, tier: @tier)
          result = Timeout.timeout(@timeout, Timeout::Error) { @mcp_client.call_tool(@mcp_tool.name, params) }
          @bus&.publish(
            "mcp:tool_after",
            server: @mcp_name,
            tool: @mcp_tool.name,
            ok: true,
            latency_ms: elapsed_ms(started),
          )
          result.respond_to?(:content) ? result.content : result.to_s
        rescue StandardError => e
          @bus&.publish(
            "mcp:tool_after",
            server: @mcp_name,
            tool: @mcp_tool.name,
            ok: false,
            error: e.message,
            latency_ms: started ? elapsed_ms(started) : nil,
          )
          "MCP tool error: #{e.class}: #{e.message}"
        end

        private

        def elapsed_ms(started)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
        end
      end
    end
  end
end
