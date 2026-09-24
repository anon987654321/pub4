# frozen_string_literal: true

module Master
  module Review
    class LLMDispatcher
      module ToolRegistry
        private

        def llm_tools(selected_model)
          return [] if Fiber[:master_no_tools]
          return [] unless tool_capable?(selected_model)

          profile = Ground::Tool::Profile.current
          evidence_mode = Fiber[:master_evidence_mode]
          @llm_tools_by_tier ||= {}
          cache_key = [profile, evidence_mode]
          @llm_tools_by_tier[cache_key] ||= build_llm_tools(profile:)
        end

        def build_llm_tools(visitor: false, profile: nil)
          profile ||= visitor ? :public : Ground::Tool::Profile.current
          evidence_mode = Fiber[:master_evidence_mode]
          allowed = Ground::Tool::Profile.allowlist(profile)
          tier = @model_router&.tier_for_model(@config.model).to_s
          @tools.filter_map do |tool|
            next mcp_tool(tool, allowed:, tier:) if tool.is_a?(::RubyLLM::Tool)

            wrapper = LLM_TOOL_MAP[tool.class]
            next unless wrapper
            name = tool.class.name.split("::").last
            meta = @tool_registry.fetch(name, {})
            # A tool data/tools.yml never classified is withheld until elevation:
            # what nobody has judged is not safe by omission.
            elevated = meta.fetch("elevated", true) != false
            next unless tool_available_for_context?(meta)
            next if allowed && !allowed.include?(name)
            next if allowed.nil? && !Fiber[:master_elevated] && elevated
            next unless evidence_tool_admitted?(name, evidence_mode)
            next if tier == "cheap" && elevated
            wrapper.new(tool, bus: @bus)
          end
        rescue StandardError => err
          @bus&.publish("agent:llm_tools_error", error: err.message)
          []
        end

        # MCP wrappers now carry their own Governor boundary. They still require
        # an elevated session here, because the server's capabilities are
        # operator-defined and are not represented in data/tools.yml.
        def mcp_tool(tool, allowed:, tier:)
          return if allowed || !Fiber[:master_elevated] || tier == "cheap"

          tool
        end

        def load_tool_registry
          path = File.join(Master::ROOT, "data", "tools.yml")
          rows = Master.load_yaml(path)
          base = rows.is_a?(Array) ? rows.select { |row| row.is_a?(Hash) } : []
          base.to_h { |row| [row["name"].to_s, row] }
        end

        EVIDENCE_TOOL_MAP = {
          repository: %w[ReadFile ListDir SearchFiles SearchKnowledge SymbolLookup Tree GitContext],
          web_current: %w[WebSearch WebFetch SearchKnowledge],
          deep_research: %w[SearchKnowledge WebSearch WebFetch AskLlm],
          browser: %w[WebFetch PluginCall WebSearch],
          device: %w[PluginCall],
          unknown: %w[SearchKnowledge WebSearch WebFetch AskLlm],
        }.freeze

        def evidence_tool_admitted?(name, mode)
          return true unless mode
          names = EVIDENCE_TOOL_MAP[mode.to_sym]
          return true unless names
          return true if names.include?(name.to_s)
          !%w[WriteFile StrReplace BatchReplace AstEdit Shell Clean DynamicHttp].include?(name.to_s)
        end

        def tool_available_for_context?(meta)
          required = Array(meta["file_types"]).filter_map { |ext| normalize_file_type(ext) }
          return true if required.empty?

          active = active_file_types
          return true if active.empty?

          (required & active).any?
        end

        def active_file_types
          sources = []
          sources << @session.topic if @session.respond_to?(:topic)
          sources.concat(Array(@session.respond_to?(:messages) ? @session.messages : nil).map { |msg| msg[:content] || msg["content"] })
          sources.compact.flat_map do |text|
            text.to_s.split(/\s+/).filter_map do |token|
              cleaned = token.to_s.strip.delete_prefix("(").delete_suffix(")").delete_suffix(",").delete_suffix(".")
              next unless cleaned.include?(".")

              ext = File.extname(cleaned).downcase
              next unless ext.match?(/\A\.[a-z][a-z0-9]*\z/i)

              ext
            end
          end.uniq
        end

        def normalize_file_type(ext)
          ext = ext.to_s.strip.downcase
          return if ext.empty?

          ext.start_with?(".") ? ext : ".#{ext}"
        end
      end
    end
  end
end
