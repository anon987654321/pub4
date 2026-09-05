# frozen_string_literal: true

module Master
  module Ground
    module Policy
      module Subagent
        ALWAYS_EXCLUDED = %w[
          spawn_agent resume_agent wait_agent send_input close_agent
          team_create team_delete team_broadcast rebuild evolve self_improve
        ].freeze

        TOOL_ALIASES = {
          "read_file" => %w[ReadFile read_file],
          "list_dir" => %w[ListDir list_dir],
          "search_files" => %w[SearchFiles search_files glob grep],
          "search_knowledge" => %w[SearchKnowledge search_knowledge search],
          "symbol_lookup" => %w[SymbolLookup symbol_lookup],
          "tree" => %w[Tree tree],
          "str_replace" => %w[StrReplace str_replace],
          "write_file" => %w[WriteFile write_file atomic_write],
          "ast_edit" => %w[AstEdit ast_edit],
          "batch_replace" => %w[BatchReplace batch_replace],
          "shell" => %w[zsh Shell shell bash],
          "web_search" => %w[WebSearch web_search],
          "web_fetch" => %w[WebFetch web_fetch fetch http_request],
          "scan" => %w[scan],
          "council_call" => %w[council_call],
          "deepwiki" => %w[deepwiki],
        }.freeze

        SWARM_ROLE_MAP = {
          analyst: :explore,
          researcher: :research,
          coder: :code,
          reviewer: :verify,
        }.freeze

        TYPES = {
          general: {
            label: "general",
            prompt: "General-purpose sub-agent. Complete the task using available non-recursive tools.",
            allow: nil,
          },
          explore: {
            label: "explore",
            prompt: "Codebase exploration agent. Search and read thoroughly. Do not modify files.",
            allow: %w[read_file list_dir search_files symbol_lookup tree glob grep ls search fetch fetch_file],
          },
          plan: {
            label: "plan",
            prompt: "Architecture planning agent. Read current state and produce a concrete " \
                    "file-by-file plan. Do not modify files.",
            allow: %w[read_file search_knowledge list_dir glob grep ls search fetch fetch_file],
          },
          code: {
            label: "code",
            prompt: "Implementation agent. Make precise changes, follow existing patterns, and verify the result.",
            allow: nil,
          },
          research: {
            label: "research",
            prompt: "Research agent. Search/read public or local sources. Do not modify files.",
            allow: %w[read_file search_files search_knowledge web_search web_fetch glob grep ls search fetch fetch_file],
          },
          verify: {
            label: "verify",
            prompt: "Verification agent. Run checks and report pass/fail with evidence.",
            allow: %w[shell scan council_call zsh],
          },
        }.freeze

        module_function

        def taxonomy_types
          data = Master.agent_taxonomy
          data.fetch("agent_types", {}).transform_keys(&:to_sym)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SubagentPolicy.taxonomy_types")
          {}
        end

        def parse(value)
          key = value.to_s.downcase.tr("-", "_").to_sym
          case key
          when :search, :find then :explore
          when :architect, :design then :plan
          when :implement, :write then :code
          when :web, :lookup then :research
          when :check, :test then :verify
          else TYPES.key?(key) || taxonomy_types.key?(key) ? key : :general
          end
        end

        def prompt_for(type)
          spec = taxonomy_types[parse(type)]
          return spec["purpose"].to_s if spec && spec["purpose"]

          TYPES.fetch(parse(type)).fetch(:prompt)
        end

        def excluded?(tool_name)
          ALWAYS_EXCLUDED.include?(tool_name.to_s)
        end

        def allow_list_for(type)
          spec = taxonomy_types[parse(type)]
          list = spec ? Array(spec["tools"]) : TYPES.fetch(parse(type)).fetch(:allow)
          list&.map(&:to_s)
        end

        def resolve_runtime_names(alias_name)
          TOOL_ALIASES.fetch(alias_name.to_s, [alias_name.to_s])
        end

        def allowed_tool_names(type, parent_tools = nil)
          allow = allow_list_for(type)
          parent_names = Array(parent_tools).flat_map do |tool|
            klass = tool.class
            [klass.name.split("::").last, klass.const_defined?(:NAME) ? klass::NAME : nil]
          end.compact.map(&:to_s).uniq

          if allow.nil?
            return parent_names.reject { |name| excluded?(name) }
          end

          allow.flat_map { |alias_name| resolve_runtime_names(alias_name) }
               .select { |name| parent_names.empty? || parent_names.include?(name) }
               .reject { |name| excluded?(name) }
               .uniq
        end

        def allowed?(type, tool_name)
          name = tool_name.to_s
          return false if excluded?(name)

          allow = allow_list_for(type)
          return true if allow.nil?

          allowed_tool_names(type).any? { |allowed| allowed == name }
        end

        def filter(type, tool_names)
          allowed = allowed_tool_names(type)
          tool_names.map(&:to_s).select { |name| !excluded?(name) && (allowed.empty? || allowed.include?(name)) }
        end

        def type_for_swarm_role(role)
          SWARM_ROLE_MAP.fetch(role.to_sym, :general)
        end

        def context_for_swarm_role(role, parent_tools = nil)
          type = type_for_swarm_role(role)
          { type:, allowed: allowed_tool_names(type, parent_tools) }
        end

        def brief(type = :general)
          policy = TYPES.fetch(parse(type))
          allowed = allow_list_for(type)
          allowed_text = allowed ? allowed.join(", ") : "all parent tools minus recursive/dangerous tools"
          "Subagent policy: #{policy[:label]} gets #{allowed_text}; always exclude #{ALWAYS_EXCLUDED.join(', ')}."
        end
      end
    end
  end
end
