# frozen_string_literal: true

module Master
  module Ground
    module SubagentPolicy
      ALWAYS_EXCLUDED = %w[
        spawn_agent resume_agent wait_agent send_input close_agent
        team_create team_delete team_broadcast rebuild evolve self_improve,
      ].freeze

      TYPES = {.freeze
        general: {
          label: "general",
          prompt: "General-purpose sub-agent. Complete the task using available non-recursive tools.",
          allow: nil,
        },
        explore: {
          label: "explore",
          prompt: "Codebase exploration agent. Search and read thoroughly. Do not modify files.",
          allow: %w[read_file glob grep ls search fetch fetch_file],
        },
        plan: {
          label: "plan",
          prompt: "Architecture planning agent. Read current state and produce a concrete " \
                  "file-by-file plan. Do not modify files.",
          allow: %w[read_file glob grep ls search fetch fetch_file bash],
        },
        code: {
          label: "code",
          prompt: "Implementation agent. Make precise changes, follow existing patterns, and verify the result.",
          allow: nil,
        },
        research: {
          label: "research",
          prompt: "Research agent. Search/read public or local sources. Do not modify files.",
          allow: %w[read_file glob grep ls search fetch fetch_file web_search http_request],
        },
      }.freeze

      module_function

      def parse(value)
        key = value.to_s.downcase.tr("-", "_").to_sym
        case key
        when :search, :find then :explore
        when :architect, :design then :plan
        when :implement, :write then :code
        when :web, :lookup then :research
        else TYPES.key?(key) ? key : :general
        end
      end

      def prompt_for(type)
        TYPES.fetch(parse(type)).fetch(:prompt)
      end

      def excluded?(tool_name)
        ALWAYS_EXCLUDED.include?(tool_name.to_s)
      end

      def allowed?(type, tool_name)
        name = tool_name.to_s
        return false if excluded?(name)

        allow = TYPES.fetch(parse(type)).fetch(:allow)
        allow.nil? || allow.include?(name)
      end

      def filter(type, tool_names)
        tool_names.map(&:to_s).select { |name| allowed?(type, name) }
      end

      def brief(type = :general)
        policy = TYPES.fetch(parse(type))
        allowed = policy[:allow] ? policy[:allow].join(", ") : "all parent tools minus recursive/dangerous tools"
        "Subagent policy: #{policy[:label]} gets #{allowed}; always exclude #{ALWAYS_EXCLUDED.join(', ')}."
      end
    end
  end
end
