# frozen_string_literal: true

require "json"
require_relative "discovery"

module Master
  module Ground
    module Antigravity
      # Settings manages Antigravity global and project-level settings,
      # auto-execution policies, file access policies, sandboxing, and permission grants.
      class Settings
        attr_reader :discovery, :settings

        def initialize(discovery: Discovery.new)
          @discovery = discovery
          @settings = load_settings
        end

        def reload!
          @settings = load_settings
        end

        def tool_execution_policy
          @settings.fetch("autoExecutionPolicy", @settings.fetch("toolExecutionPolicy", "always-proceed"))
        end

        def non_workspace_file_access
          @settings.fetch("nonWorkspaceFileAccess", @settings.fetch("fileAccessPolicy", "allow"))
        end

        def internet_access_policy
          @settings.fetch("internetAccessPolicy", "allow")
        end

        def sandbox_mode?
          !!@settings.fetch("sandboxMode", @settings.fetch("terminalSandbox", false))
        end

        def artifact_review_mode
          @settings.fetch("artifactReviewMode", "agent-decides")
        end

        def command_allowed?(command)
          cmd_str = command.to_s.strip
          denylist = Array(@settings["commandDenylist"])
          return false if denylist.any? { |pattern| File.fnmatch?(pattern, cmd_str) }

          allowlist = Array(@settings["commandAllowlist"])
          return true if allowlist.empty?

          allowlist.any? { |pattern| File.fnmatch?(pattern, cmd_str) }
        end

        def file_accessible?(file_path, workspace_root: @discovery.workspace_root)
          expanded = File.expand_path(file_path)
          in_workspace = expanded.start_with?(File.expand_path(workspace_root))
          return true if in_workspace

          policy = non_workspace_file_access
          policy != "deny"
        end

        def domain_allowed?(url)
          allowlist = Array(@settings["browserAllowlist"])
          return true if allowlist.empty?

          uri = URI.parse(url) rescue nil
          return false unless uri&.host

          allowlist.any? { |pattern| File.fnmatch?(pattern, uri.host) }
        end

        private

        def load_settings
          merged = {}
          @discovery.settings_files.reverse_each do |file_path|
            next unless File.file?(file_path)

            data = JSON.parse(File.read(file_path, encoding: "UTF-8")) rescue {}
            merged.merge!(data) if data.is_a?(Hash)
          end
          merged
        end
      end
    end
  end
end
