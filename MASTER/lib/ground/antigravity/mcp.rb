# frozen_string_literal: true

require "json"
require_relative "discovery"

module Master
  module Ground
    module Antigravity
      # Mcp discovers and normalizes Model Context Protocol servers from Antigravity
      # workspace mcp_config.json, plugin mcp_config.json, and global configs.
      class Mcp
        attr_reader :discovery

        def initialize(discovery: Discovery.new)
          @discovery = discovery
        end

        def discover_servers
          servers = {}

          # 1. Global config (~/.gemini/config/mcp_config.json)
          if @discovery.global_customization_root
            gm = File.join(@discovery.global_customization_root, "mcp_config.json")
            merge_config_file(servers, gm, scope: :global)
          end

          # 2. Workspace config (.agents/mcp_config.json)
          @discovery.workspace_customization_roots.reverse_each do |root|
            wm = File.join(root, "mcp_config.json")
            merge_config_file(servers, wm, scope: :workspace)
          end

          servers
        end

        def load_plugin_servers(plugin_dir)
          cfg_file = File.join(plugin_dir, "mcp_config.json")
          return {} unless File.file?(cfg_file)

          servers = {}
          plugin_name = File.basename(plugin_dir)
          merge_config_file(servers, cfg_file, scope: :plugin, prefix: plugin_name)
          servers
        end

        private

        def merge_config_file(servers, file_path, scope:, prefix: nil)
          return unless File.file?(file_path)

          content = File.read(file_path, encoding: "UTF-8")
          data = JSON.parse(content)
          return unless data.is_a?(Hash)

          raw_servers = data["mcpServers"] || data["servers"] || {}
          raw_servers.each do |key, spec|
            next unless spec.is_a?(Hash)

            server_key = prefix ? "#{prefix}__#{key}" : key.to_s
            normalized = normalize_server_spec(spec, scope:, source_file: file_path)
            servers[server_key] = normalized if normalized
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.mcp.merge", file_path:)
        end

        def normalize_server_spec(spec, scope:, source_file:)
          if spec["serverUrl"] || spec["url"]
            {
              "transport" => "sse",
              "url" => spec["serverUrl"] || spec["url"],
              "scope" => scope.to_s,
              "source_file" => source_file,
              "enabled" => spec.fetch("enabled", true),
            }
          elsif spec["command"]
            {
              "transport" => "stdio",
              "command" => spec["command"],
              "args" => Array(spec["args"]),
              "env" => spec["env"] || {},
              "scope" => scope.to_s,
              "source_file" => source_file,
              "enabled" => spec.fetch("enabled", true),
            }
          end
        end
      end
    end
  end
end
