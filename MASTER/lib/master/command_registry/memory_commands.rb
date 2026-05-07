# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) { dispatch_memory(memory, ctx[:args].to_s.strip) },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries  = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active   = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary  = memory.recall("_consolidated_summary")
            lines    = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end

    def dispatch_memory(memory, arg)
      case arg
      when /\Aforget (.+)/  then memory.forget($1.strip); "forgot: #{$1.strip}"
      when /\Aremember (.+)/
        key, value = $1.split("=", 2).map(&:strip)
        value ? (memory.remember(key, value); "remembered: #{key}") : "usage: /memory remember key=value"
      when /\Asearch (.+)/ then memory_search(memory, $1.strip)
      when ""
        (e = memory.all).empty? ? "(no memories)" : e.map { |k, v| "#{k}: #{v}" }.join("\n")
      else
        (r = memory.recall(arg)) ? "#{arg}: #{r}" : "(not found: #{arg})"
      end
    end

    def memory_search(memory, query)
      if memory.respond_to?(:semantic_recall)
        hits = memory.semantic_recall(query)
        return "(no matches: #{query})" if hits.empty?
        hits.map { |h| "#{h[:key]}: #{h[:value]}" }.join("\n")
      else
        hits = memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
        hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end
