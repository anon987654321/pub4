# frozen_string_literal: true

require "json"
require "securerandom"
require "timeout"
require "mcp"
# McpToolWrapper subclasses RubyLLM::Tool; a caller that reached this file
# before anything loaded the gem got no wrapper at all.
require "ruby_llm"
require_relative "../execution/contract"
require_relative "../trace/tool_observer"

module Master
  module Io
    # McpCoordinator — manages MCP server connections and exposes
    # their tools to the agent alongside MASTER's native tools.
    class McpCoordinator
      CONFIG_PATH = "data/mcp_servers.yml".freeze
      DEFAULT_TIMEOUT = 60
      DEFAULT_TIER = :dangerous

      def initialize(root:, event_bus: nil, governor: nil)
        @root = root
        @bus = event_bus
        @governor = governor
        @tool_observer = if event_bus&.respond_to?(:publish_required)
                           Master::Trace::ToolObserver.new(bus: event_bus)
                         end
        @clients = {}
        @server_config = {}
      end

      def connect_all
        load_servers.each { |name, cfg| connect(name, cfg) }
        @bus&.publish("mcp:connected", count: @clients.size)
      rescue StandardError => e
        @bus&.publish("mcp:error", **Master::Execution::Contract.diagnostic_fields(e.message))
      end

      def tools
        @clients.flat_map do |name, client|
          client.tools.filter_map do |tool|
            McpToolWrapper.new(
              name:,
              client:,
              tool:,
              governor: @governor,
              event_bus: @bus,
              tool_observer: @tool_observer,
              timeout: @server_config.fetch(name, {}).fetch("timeout_seconds", DEFAULT_TIMEOUT),
              tier: @server_config.fetch(name, {}).fetch("tier", DEFAULT_TIER).to_sym,
            )
          rescue StandardError => e
            @bus&.publish("mcp:tool_wrap_error", name:, **Master::Execution::Contract.diagnostic_fields(e.message))
            nil
          end
        end
      rescue StandardError => e
        @bus&.publish("mcp:tools_error", **Master::Execution::Contract.diagnostic_fields(e.message))
        []
      end

      private

      def connect(name, cfg)
        return unless cfg.is_a?(Hash) && cfg["enabled"] != false

        transport = (cfg["transport"] || "stdio").to_sym
        return unless %i[stdio sse].include?(transport)

        client = build_mcp_client(name, transport, cfg)
        client.connect
        @clients[name] = client
        @server_config[name] = cfg
        @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
      rescue StandardError => e
        @bus&.publish("mcp:server_failed", name:, **Master::Execution::Contract.diagnostic_fields(e.message))
      end

      def build_mcp_client(_name, transport, cfg)
        transport_client = case transport
                          when :stdio
                            MCP::Client::Stdio.new(
                              command: cfg["command"],
                              args: expand_args(cfg["args"] || []),
                              read_timeout: timeout_for(cfg),
                            )
                          when :sse
                            MCP::Client::HTTP.new(url: cfg["url"])
                          end
        return unless transport_client

        MCP::Client.new(transport: transport_client)
      end

      def timeout_for(cfg)
        cfg.fetch("timeout_seconds", DEFAULT_TIMEOUT).to_i.clamp(1, 600)
      end

      # Configuration names the repo root, not one developer's absolute home
      # path. This keeps the same mcp_servers.yml valid on macOS and vm23.
      def expand_args(args)
        repo_root = File.expand_path("..", @root)
        Array(args).map do |arg|
          arg.to_s
            .gsub("${MASTER_ROOT}", @root)
            .gsub("${MASTER_REPO_ROOT}", repo_root)
            .gsub("${HOME}", ENV.fetch("HOME", ""))
        end
      end

      def load_servers
        path = File.join(@root, CONFIG_PATH)
        return {} unless File.exist?(path)

        Master.load_yaml(path)&.fetch("servers", {}) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "mcp_coordinator.load_servers", event_bus: @bus, path:)
        {}
      end
    end

    if defined?(::RubyLLM::Tool)
      class McpToolWrapper < ::RubyLLM::Tool
        def initialize(name:, client:, tool:, governor: nil, event_bus: nil, tool_observer: nil, timeout: 60, tier: :dangerous)
          @mcp_name = name
          @mcp_client = client
          @mcp_tool = tool
          @governor = governor
          @bus = event_bus
          @tool_observer = tool_observer || if event_bus&.respond_to?(:publish_required)
                                             Master::Trace::ToolObserver.new(bus: event_bus)
                                           end
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

          identity = nil
          started = nil
          executing = false
          after_attempted = false
          receipt_written = false
          if @tool_observer
            identity = @tool_observer.before(tool: name, tier: @tier, args: params)
          end

          invocation_id = identity&.invocation_id || SecureRandom.uuid
          @bus&.publish("mcp:tool_before", server: @mcp_name, tool: @mcp_tool.name,
                        tier: @tier, invocation_id:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          executing = true
          response = Timeout.timeout(@timeout, Timeout::Error) do
            @mcp_client.call_tool(tool: @mcp_tool, arguments: params)
          end
          content = tool_content(response)
          if identity
            after_attempted = true
            @tool_observer.after(
              identity:, tool: name, tier: @tier, args: params, status: "success",
              elapsed_ms: elapsed_ms(started), result_bytes: content.to_s.bytesize
            )
            receipt_written = true
          end
          publish_after(started, ok: true, invocation_id:)
          content
        rescue Master::Trace::ToolObserver::UnknownOutcome => e
          publish_after(started, ok: false, error: e.message, invocation_id:) if executing
          "Error: MCP invocation outcome is unresolved; verify the current state and reconcile before retrying."
        rescue StandardError => e
          return content if identity && receipt_written
          if identity && executing && !after_attempted
            after_attempted = true
            begin
              @tool_observer.after(
                identity:, tool: name, tier: @tier, args: params, status: "unknown_outcome",
                elapsed_ms: elapsed_ms(started), error: e.message
              )
            rescue StandardError
              # The observer keeps the invocation quarantined when a terminal
              # receipt cannot be persisted.
            end
          end
          publish_after(started, ok: false, error: e.message, invocation_id:) if executing
          if identity && executing
            "Error: MCP invocation #{identity.invocation_id} may have run; verify current state and reconcile before retrying."
          else
            "MCP tool error: #{e.class}: #{e.message}"
          end
        end

        private

        def tool_content(response)
          return response.to_s unless response.is_a?(Hash)

          structured = response.dig("result", "structuredContent")
          return JSON.generate(structured) if structured

          content = response.dig("result", "content")
          return JSON.generate(content) unless content.nil?

          response.to_json
        end

        def publish_after(started, ok:, error: nil, invocation_id: nil)
          payload = {
            server: @mcp_name,
            tool: @mcp_tool.name,
            invocation_id:,
            ok:,
            latency_ms: started ? elapsed_ms(started) : nil,
          }
          payload.merge!(Master::Execution::Contract.diagnostic_fields(error)) if error
          @bus&.publish("mcp:tool_after", **payload)
        end

        def elapsed_ms(started)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
        end
      end
    end
  end
end
