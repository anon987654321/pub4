# frozen_string_literal: true

require "securerandom"

module Master
  module Ground
    module Antigravity
      # Subagents provides programmatic Antigravity subagent lifecycle management,
      # custom agent type definitions, messaging, and scheduled timers/crons.
      class Subagents
        attr_reader :active_subagents, :defined_types, :schedules

        def initialize(event_bus: nil)
          @bus = event_bus
          @active_subagents = {}
          @defined_types = default_subagent_types
          @schedules = {}
        end

        def define_subagent(name:, description:, system_prompt:, enable_write_tools: true, enable_mcp_tools: true, enable_subagent_tools: false)
          @defined_types[name.to_s] = {
            name: name.to_s,
            description: description.to_s,
            system_prompt: system_prompt.to_s,
            enable_write_tools: !!enable_write_tools,
            enable_mcp_tools: !!enable_mcp_tools,
            enable_subagent_tools: !!enable_subagent_tools,
          }
          @bus&.publish("subagent:defined", name:)
          @defined_types[name.to_s]
        end

        def invoke_subagent(type_name:, role:, prompt:, model: "inherit", workspace: "inherit")
          conversation_id = SecureRandom.uuid
          entry = {
            conversation_id:,
            type: type_name.to_s,
            role: role.to_s,
            prompt: prompt.to_s,
            model: model.to_s,
            workspace: workspace.to_s,
            state: "running",
            created_at: Time.now.utc.iso8601,
            messages: [{ role: "user", content: prompt.to_s }],
          }
          @active_subagents[conversation_id] = entry
          @bus&.publish("subagent:invoked", conversation_id:, role:, type: type_name)
          entry
        end

        def manage_subagents(action:, conversation_ids: [])
          case action.to_s
          when "list"
            @active_subagents.values.map do |sa|
              {
                "conversationId" => sa[:conversation_id],
                "role" => sa[:role],
                "type" => sa[:type],
                "state" => sa[:state],
              }
            end
          when "kill"
            Array(conversation_ids).each do |cid|
              if @active_subagents[cid]
                @active_subagents[cid][:state] = "killed"
                @bus&.publish("subagent:killed", conversation_id: cid)
              end
            end
            { success: true }
          when "kill_all"
            @active_subagents.each_value do |sa|
              sa[:state] = "killed"
            end
            @bus&.publish("subagent:kill_all")
            { success: true }
          else
            { error: "Unknown action #{action}" }
          end
        end

        def send_message(recipient_id:, message:)
          subagent = @active_subagents[recipient_id.to_s]
          return { error: "Subagent not found" } unless subagent

          subagent[:messages] << { role: "user", content: message.to_s }
          @bus&.publish("subagent:message_sent", recipient_id:, message:)
          { success: true, recipient: recipient_id }
        end

        def schedule(prompt:, duration_seconds: nil, cron_expression: nil, timer_condition: "never", max_iterations: nil)
          task_id = "task-#{SecureRandom.hex(4)}"
          schedule_entry = {
            task_id:,
            prompt:,
            duration_seconds:,
            cron_expression:,
            timer_condition:,
            max_iterations:,
            created_at: Time.now.utc.iso8601,
            state: "active",
          }
          @schedules[task_id] = schedule_entry
          @bus&.publish("schedule:created", task_id:, prompt:)
          schedule_entry
        end

        private

        def default_subagent_types
          {
            "self" => {
              name: "self",
              description: "Subagent that inherits parent full configuration.",
              enable_write_tools: true,
              enable_mcp_tools: true,
              enable_subagent_tools: true,
            },
            "research" => {
              name: "research",
              description: "Research subagent with read-only tools for exploring codebase and docs.",
              enable_write_tools: false,
              enable_mcp_tools: false,
              enable_subagent_tools: false,
            },
          }
        end
      end
    end
  end
end
