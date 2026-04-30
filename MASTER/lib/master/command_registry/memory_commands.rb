# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("forget ")
            key = arg.sub("forget ", "").strip
            memory.forget(key)
            "forgot: #{key}"
          elsif arg.start_with?("remember ")
            parts = arg.sub("remember ", "").split("=", 2)
            key = parts[0].strip
            val = parts[1]&.strip
            val ? (memory.remember(key, val); "remembered: #{key}") : "usage: /memory remember key=value"
          elsif arg.start_with?("search ")
            query = arg.sub("search ", "").strip
            hits = if memory.respond_to?(:semantic_recall)
                     memory.semantic_recall(query)
                   else
                     memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
                   end
            hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
          elsif arg.empty?
            entries = memory.all
            entries.empty? ? "(no memories)" : entries.map { |k, v| "#{k}: #{v}" }.join("\n")
          else
            val = memory.recall(arg)
            val ? "#{arg}: #{val}" : "(not found: #{arg})"
          end
        },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary = memory.recall("_consolidated_summary")
            lines = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end
  end
end
