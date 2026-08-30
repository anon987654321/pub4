# frozen_string_literal: true

require_relative "antigravity/json_config"
require_relative "antigravity/discovery"
require_relative "antigravity/rules"
require_relative "antigravity/skills"
require_relative "antigravity/hooks"
require_relative "antigravity/plugins"
require_relative "antigravity/mcp"
require_relative "antigravity/settings"
require_relative "antigravity/subagents"
require_relative "antigravity/artifacts"

module Master
  module Ground
    # Antigravity is the unified adapter and coordinator for full Antigravity documentation
    # compatibility (https://antigravity.google/docs/home/).
    module Antigravity
      class << self
        def instance(cwd: Dir.pwd, workspace_root: nil, event_bus: nil)
          @instance ||= Coordinator.new(cwd:, workspace_root:, event_bus:)
        end

        def reset!
          @instance = nil
        end
      end

      # Coordinator brings together all Antigravity subsystems.
      class Coordinator
        attr_reader :discovery, :rules, :skills, :hooks, :plugins, :mcp, :settings, :subagents, :artifacts

        def initialize(cwd: Dir.pwd, workspace_root: nil, event_bus: nil)
          @bus = event_bus
          @discovery = Discovery.new(cwd:, workspace_root:)
          @rules = Rules.new(discovery: @discovery)
          @skills = Skills.new(discovery: @discovery)
          @hooks = Hooks.new(discovery: @discovery)
          @plugins = Plugins.new(discovery: @discovery)
          @mcp = Mcp.new(discovery: @discovery)
          @settings = Settings.new(discovery: @discovery)
          @subagents = Subagents.new(event_bus: @bus)
          @artifacts = Artifacts.new
        end

        # System prompt enhancements: merges active rules + progressive skills disclosure
        def system_prompt_context(target_path: @discovery.cwd)
          rules_text = @rules.active_rules_prompt(target_path:)
          skills_text = @skills.prompt_catalog

          [rules_text, skills_text].compact.join("\n\n---\n\n")
        end

        # Hook helpers
        def before_tool(tool_name, args, context = {})
          @hooks.run_pre_tool_use(tool_name, args, context)
        end

        def after_tool(tool_name, step_idx:, error: nil, context: {})
          @hooks.run_post_tool_use(tool_name, step_idx:, error:, context:)
        end

        def before_invocation(invocation_num:, initial_num_steps: 0, context: {})
          @hooks.run_pre_invocation(invocation_num:, initial_num_steps:, context:)
        end

        def after_invocation(invocation_num:, initial_num_steps: 0, context: {})
          @hooks.run_post_invocation(invocation_num:, initial_num_steps:, context:)
        end

        def on_stop(execution_num:, termination_reason: "model_stop", error: nil, fully_idle: true, context: {})
          @hooks.run_stop(execution_num:, termination_reason:, error:, fully_idle:, context:)
        end

        # Permission check
        def command_allowed?(cmd)
          @settings.command_allowed?(cmd)
        end

        def file_accessible?(file_path)
          @settings.file_accessible?(file_path)
        end
      end
    end
  end
end
