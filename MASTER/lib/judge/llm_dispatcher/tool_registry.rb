# frozen_string_literal: true

module Master
  module Judge
    class LLMDispatcher
      module ToolRegistry
        private

        def llm_tools(selected_model)
          return [] unless tool_capable?(selected_model)
          return build_llm_tools(visitor: true) if Fiber[:master_visitor]

          tier = Fiber[:master_elevated] ? :elevated : :standard
          @llm_tools_by_tier ||= {}
          @llm_tools_by_tier[tier] ||= build_llm_tools
        end

        def build_llm_tools(visitor: false)
          tier = @model_router&.tier_for_model(@config.model).to_s
          @tools.filter_map do |tool|
            wrapper = LLM_TOOL_MAP[tool.class]
            next unless wrapper
            name = tool.class.name.split("::").last
            meta = @tool_registry.fetch(name, {})
            next unless tool_available_for_context?(meta)
            next if visitor && meta["visitor"] != true
            next if !visitor && !Fiber[:master_elevated] && meta["tier"] == "dangerous"
            next if tier == "cheap" && meta["tier"] == "dangerous"
            wrapper.new(tool)
          end
        rescue StandardError => err
          @bus&.publish("agent:llm_tools_error", error: err.message)
          []
        end

        def load_tool_registry
          path = File.join(Master::ROOT, "data", "tools.yml")
          rows = Master.load_yaml(path)
          return {} unless rows.is_a?(Array)
          rows.each_with_object({}) { |row, h| h[row["name"].to_s] = row if row.is_a?(Hash) }
        end

        def tool_available_for_context?(meta)
          required = Array(meta["file_types"]).map { |ext| normalize_file_type(ext) }.compact
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
